# ⚙️ Guía de Configuración Completa

> Esta guía explica en detalle todas las configuraciones del proyecto, incluyendo personalización de Falco, Network Policies, alertas y ajustes avanzados.

## 📋 Tabla de Contenidos

1. [Configuración de Falco](#1-configuración-de-falco)
2. [Configuración de Reglas Custom](#2-configuración-de-reglas-custom)
3. [Configuración de Network Policies](#3-configuración-de-network-policies)
4. [Configuración de Alertas](#4-configuración-de-alertas)

---

## 1. Configuración de Falco

### 1.1 Archivo de Valores de Helm

Falco se configura principalmente a través de `values.yaml` en Helm. Aquí está la configuración completa explicada:

```yaml
# Configuración del driver eBPF
driver:
  kind: modern_ebpf  # Opciones: modern_ebpf, ebpf, module
  
  # Configuración del loader
  loader:
    initContainer:
      enabled: false  # Deshabilitado para evitar compilación
```

**¿Qué significa cada opción?**

| Opción | Descripción | Cuándo usar |
|--------|-------------|-------------|
| `modern_ebpf` | Driver eBPF de última generación | ✅ **Recomendado** - Kernel 5.8+ |
| `ebpf` | Driver eBPF legacy | Kernel 4.14+ pero < 5.8 |
| `module` | Módulo de kernel compilado | Kernels antiguos < 4.14 |
| `initContainer.enabled: false` | Sin init container | Cuando no hay headers del kernel |

```yaml
# Configuración de salida
tty: true  # Logs legibles en terminal
```

**Output con `tty: true`**:
```
Tue Nov 04 10:15:23 2024: Warning Shell spawned in container 
  (user=root container=test-pod command=/bin/bash -c whoami)
```

**Output con `tty: false`** (JSON):
```json
{"output":"Warning Shell spawned in container","priority":"Warning","rule":"Shell Spawned in Container","time":"2024-11-04T10:15:23Z","output_fields":{"user.name":"root","container.name":"test-pod"}}
```

```yaml
# Configuración de red
daemonset:
  hostNetwork: true  # Usar red del host
```

**¿Por qué `hostNetwork: true`?**
- Permite a Falco monitorear tráfico de red del host
- Necesario para algunas reglas de detección de red
- Performance: reduce latencia en captura de eventos

```yaml
# Integración con Falcosidekick
falcosidekick:
  enabled: true
  fullfqdn: falcosidekick.falco.svc.cluster.local
```

**¿Qué hace esto?**
- `enabled: true` → Falco enviará eventos automáticamente
- `fullfqdn` → Nombre completo del servicio en Kubernetes

**Verificar conexión**:
```bash
# Ver si Falco está enviando eventos
kubectl logs -n falco -l app.kubernetes.io/name=falco | grep -i "sending\|sidekick"
```

**Output esperado**:
```
Tue Nov 04 10:20:15 2024: Sending event to Falcosidekick at falcosidekick.falco.svc.cluster.local:2801
```

```yaml
# Configuración de gRPC
falco:
  grpc:
    enabled: true  # Habilitar servidor gRPC
  grpc_output:
    enabled: true  # Enviar salida via gRPC
```

**¿Para qué sirve gRPC?**
- Protocolo de comunicación eficiente (más rápido que HTTP)
- Usado para enviar eventos a Falcosidekick
- Menos overhead que JSON sobre HTTP

**Verificar gRPC funcionando**:
```bash
# Ver puerto gRPC
kubectl get svc -n falco falco-grpc

# Output esperado:
# NAME         TYPE        CLUSTER-IP      PORT(S)
# falco-grpc   ClusterIP   10.96.123.45    5060/TCP
```
### 1. Verificar Configuración Aplicada

```bash
# Ver valores actuales de Falco
helm get values falco -n falco
```

**Output completo**:
```yaml
USER-SUPPLIED VALUES:
daemonset:
  hostNetwork: true
driver:
  kind: modern_ebpf
falco:
  grpc:
    enabled: true
  grpc_output:
    enabled: true
falcosidekick:
  enabled: true
  fullfqdn: falcosidekick.falco.svc.cluster.local
resources:
  limits:
    cpu: 1000m
    memory: 1024Mi
  requests:
    cpu: 100m
    memory: 512Mi
tty: true
```

---

## 2. Configuración de Reglas Custom

### 2.1 Anatomía de una Regla de Falco

```yaml
- rule: Shell Spawned in Container
  desc: Detecta cuando se ejecuta un shell interactivo dentro de un container
  condition: >
    spawned_process and 
    container and
    proc.name in (shell_binaries) and
    not proc.pname in (docker_binaries)
  output: >
    Shell spawneado en container
    (user=%user.name container=%container.name command=%proc.cmdline)
  priority: WARNING
  tags: [container, shell, mitre_execution, T1059]
```

**Explicación de cada campo**:

| Campo | Propósito | Ejemplo |
|-------|-----------|---------|
| `rule` | Nombre único de la regla | `Shell Spawned in Container` |
| `desc` | Descripción de qué detecta | `Detecta shells interactivos...` |
| `condition` | Lógica de detección | `spawned_process and container` |
| `output` | Mensaje de alerta | `Shell spawneado en container...` |
| `priority` | Nivel de severidad | `WARNING`, `ERROR`, `CRITICAL` |
| `tags` | Categorización | `[container, shell, mitre_execution]` |

### 2.2 Condiciones (Conditions)

Las condiciones usan operadores lógicos y campos de eventos:

```yaml
# Operadores básicos
and    # Ambas condiciones deben cumplirse
or     # Al menos una condición debe cumplirse
not    # Niega la condición

# Operadores de comparación
=      # Igual
!=     # Diferente
in     # Está en lista
contains   # Contiene substring
startswith # Comienza con
```

**Ejemplo con explicación**:
```yaml
condition: >
  spawned_process and           # Se ejecutó un proceso
  container and                 # Dentro de un container
  proc.name in (shell_binaries) # El proceso es un shell
  and not proc.pname in (docker_binaries)  # Padre NO es Docker
```

**¿Qué detecta esto?**
- ✅ Usuario ejecutando `bash` manualmente
- ✅ Script ejecutando `sh`
- ❌ Docker iniciando el container (proceso normal)

### 2.3 Campos de Eventos Disponibles

```yaml
# Proceso
proc.name         # Nombre del proceso: bash, python, etc
proc.cmdline      # Comando completo: /bin/bash -c "whoami"
proc.pid          # Process ID
proc.ppid         # Parent process ID
proc.pname        # Nombre del proceso padre

# Usuario
user.name         # Nombre del usuario: root, admin
user.uid          # User ID: 0, 1000
user.loginuid     # UID de login

# Container
container         # Booleano: true si es un container
container.name    # Nombre del container: nginx-pod
container.id      # ID del container
container.image.repository  # Imagen: nginx, redis

# Filesystem
fd.name           # Nombre del archivo: /etc/shadow
fd.directory      # Directorio: /etc
evt.is_open_write # Es operación de escritura
evt.is_open_read  # Es operación de lectura

# Red
fd.sip            # IP origen
fd.dip            # IP destino
fd.sport          # Puerto origen
fd.dport          # Puerto destino
```

### 2.4 Prioridades de Alertas

```yaml
priority: CRITICAL  # Amenazas graves - requiere acción inmediata
priority: ERROR     # Comportamiento anómalo - investigar
priority: WARNING   # Actividad sospechosa - monitorear
priority: NOTICE    # Información - para auditoría
priority: DEBUG     # Solo para desarrollo
```

**Ejemplos de cada prioridad**:

```yaml
# CRITICAL - Reverse shell detectado
priority: CRITICAL
output: "Reverse shell detectado - Acción inmediata requerida"

# ERROR - Modificación de binario del sistema
priority: ERROR
output: "Binario del sistema modificado - Posible compromiso"

# WARNING - Shell spawneado
priority: WARNING
output: "Shell ejecutado en container - Revisar actividad"

# NOTICE - Herramienta de red ejecutada
priority: NOTICE
output: "tcpdump ejecutado - Auditar uso"
```

### 2.5 Listas y Macros

Las listas y macros hacen las reglas más mantenibles:

```yaml
# Lista de shells
- list: shell_binaries
  items: [bash, sh, zsh, dash, ksh, csh, tcsh, fish]

# Lista de archivos sensibles
- list: sensitive_files
  items: [/etc/shadow, /etc/sudoers, /etc/ssh/sshd_config]

# Macro para proceso spawneado
- macro: spawned_process
  condition: (evt.type=execve and evt.dir=<)

# Macro para escritura de archivo
- macro: open_write
  condition: (evt.type in (open,openat,openat2) and evt.is_open_write=true)
```

**Uso en reglas**:
```yaml
- rule: Shell Detection
  condition: spawned_process and proc.name in (shell_binaries)
  # Más fácil que repetir toda la condición
```

---

## 3. Configuración de Network Policies

### 3.1 Estructura de una Network Policy

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-network-policy
  namespace: production
spec:
  # A qué pods aplicar esta policy
  podSelector:
    matchLabels:
      app: backend
      tier: api
  
  # Tipos de tráfico a controlar
  policyTypes:
  - Ingress  # Tráfico entrante
  - Egress   # Tráfico saliente
  
  # Reglas de ingress (quién puede conectarse)
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend
    ports:
    - protocol: TCP
      port: 8080
  
  # Reglas de egress (a dónde puede conectarse)
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: database
    ports:
    - protocol: TCP
      port: 5432
```

**Explicación visual**:
```
┌─────────────┐
│  Frontend   │
│ app=frontend│
└──────┬──────┘
       │ ✅ Permitido (ingress)
       │ Puerto 8080
       ▼
┌─────────────┐
│   Backend   │  ──────────────┐
│ app=backend │  ✅ Permitido  │
└──────┬──────┘     (egress)   │
       │            Puerto 5432 │
       │ ❌ Bloqueado           ▼
       │                  ┌──────────┐
       X                  │ Database │
       │                  └──────────┘
┌──────▼──────┐
│   Redis     │
└─────────────┘
```

### 3.2 Selectores (Selectors)

**Pod Selector** - Selecciona pods por labels:
```yaml
podSelector:
  matchLabels:
    app: backend
    tier: api
```

**Namespace Selector** - Selecciona namespaces:
```yaml
namespaceSelector:
  matchLabels:
    name: kube-system
```

**IP Block** - Selecciona rangos de IPs:
```yaml
ipBlock:
  cidr: 10.0.0.0/24
  except:
  - 10.0.0.5/32
```

### 3.3 Tipos de Políticas

**Default Deny All** (más restrictivo):
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: production
spec:
  podSelector: {}  # Aplica a TODOS los pods
  policyTypes:
  - Ingress
  - Egress
  # Sin reglas ingress/egress = TODO bloqueado
```

**Output al aplicar**:
```bash
kubectl apply -f default-deny-all.yaml

# networkpolicy.networking.k8s.io/default-deny-all created

# Verificar
kubectl get networkpolicies -n production

# NAME               POD-SELECTOR   AGE
# default-deny-all   <none>         10s
```


**¿Cuándo usar cada uno?**

| Tipo | Uso | Pros | Contras |
|------|-----|------|---------|
| Deny All | Máxima seguridad | Total control | Puede romper apps |
| Deny Ingress | Producción | Balance | Egress sin control |
| Allow All | Development | Sin restricciones | Sin seguridad |

### 3.4 Permitir DNS y Registry

**Problema común**: Default Deny bloquea DNS y pull de imágenes.

**Solución**:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns-and-registry
  namespace: production
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  # Permitir DNS
  - ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
  # Permitir HTTPS (registry)
  - ports:
    - protocol: TCP
      port: 443
```

**Verificar que funciona**:
```bash
# Crear pod de test
kubectl run test-dns -n production --image=busybox -- sleep 3600

# Test DNS
kubectl exec test-dns -n production -- nslookup kubernetes.default

# Output esperado:
# Server:    10.96.0.10
# Address 1: 10.96.0.10 kube-dns.kube-system.svc.cluster.local
# Name:      kubernetes.default
# Address 1: 10.96.0.1 kubernetes.default.svc.cluster.local
```

### 3.5 Policy para Aplicación 3-Tier

**Arquitectura**:
```
Internet → Frontend → Backend → Database
```

**Frontend Policy**:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: frontend-policy
  namespace: production
spec:
  podSelector:
    matchLabels:
      tier: web
  ingress:
  - {}  # Permite desde cualquier origen
  egress:
  - to:
    - podSelector:
        matchLabels:
          tier: api
    ports:
    - port: 8080
  - ports:  # DNS
    - port: 53
      protocol: UDP
```

**Backend Policy**:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-policy
  namespace: production
spec:
  podSelector:
    matchLabels:
      tier: api
  ingress:
  - from:
    - podSelector:
        matchLabels:
          tier: web
    ports:
    - port: 8080
  egress:
  - to:
    - podSelector:
        matchLabels:
          tier: db
    ports:
    - port: 5432
```

**Database Policy**:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: database-policy
  namespace: production
spec:
  podSelector:
    matchLabels:
      tier: db
  ingress:
  - from:
    - podSelector:
        matchLabels:
          tier: api
    ports:
    - port: 5432
  egress:
  - ports:  # Solo DNS
    - port: 53
      protocol: UDP
```
---

## 4. Configuración de Alertas

### 4.1 Configurar Slack
**Paso 1: Crear Weebhook**
- Crear Webhook en Slack
- Ve a https://api.slack.com/apps
- Click en "Create New App" → "From scratch"
- Dale un nombre (ej: "Falco Alerts") y selecciona tu workspace
- En el menú lateral, ve a "Incoming Webhooks"
- Activa "Activate Incoming Webhooks"
- Click en "Add New Webhook to Workspace"
- Selecciona el canal donde quieres recibir las alertas
- Copia la URL del webhook (se ve como: https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXX)
- Editar el falco-values.yaml en la seccion del webhook (se indica en el manifiesto)

**Paso 2: Configurar Falcosidekick**
```bash
helm upgrade falco falcosecurity/falco \
  -n falco \
  --reuse-values \
  --set falcosidekick.config.slack.webhookurl="https://hooks.slack.com/services/NUEVO/TOKEN/AQUI"  
```

**Output esperado**:
```
Release "falcosidekick" has been upgraded.
```

**Paso 3: Probar Alerta**
```bash
# Generar alerta
kubectl run test-alert --image=nginx --restart=Never
kubectl exec test-alert -- /bin/bash -c "cat /etc/shadow"

# Deberías recibir mensaje en Slack en 1-2 segundos
```

**Mensaje en Slack**:
```
🚨 Falco Security Alert

Priority: CRITICAL
Rule: Read Sensitive File
Container: test-alert
User: root
Command: cat /etc/shadow
Time: 2024-11-04 10:45:23 UTC

[View in Dashboard]
```

**Verificar configuración**:
```bash
kubectl logs -n falco -l app.kubernetes.io/name=falcosidekick | grep -i "enabled\|output"
```

**Output esperado**:
```
[INFO] : Slack output enabled
[INFO] : Teams output enabled  
[INFO] : Webhook output enabled
[INFO] : Redis output enabled
```

---
