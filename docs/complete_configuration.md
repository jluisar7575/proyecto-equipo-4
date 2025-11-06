# ⚙️ Guía de Configuración Completa

> Esta guía explica en detalle todas las configuraciones del proyecto, incluyendo personalización de Falco, Network Policies, alertas y ajustes avanzados.

## 📋 Tabla de Contenidos

1. [Configuración de Falco](#1-configuración-de-falco)
2. [Configuración de Reglas Custom](#2-configuración-de-reglas-custom)
3. [Configuración de Network Policies](#3-configuración-de-network-policies)
4. [Configuración de Alertas](#4-configuración-de-alertas)
5. [Configuración de Persistencia](#5-configuración-de-persistencia)
6. [Configuración de Recursos](#6-configuración-de-recursos)
7. [Configuración Avanzada](#7-configuración-avanzada)

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

### 1.2 Aplicar Configuración Personalizada

```bash
# Crear archivo de valores personalizado
cat > custom-falco-values.yaml <<EOF
driver:
  kind: modern_ebpf
  
tty: true

daemonset:
  hostNetwork: true

falcosidekick:
  enabled: true
  fullfqdn: falcosidekick.falco.svc.cluster.local

falco:
  grpc:
    enabled: true
  grpc_output:
    enabled: true

# Configuración de recursos
resources:
  requests:
    cpu: 100m
    memory: 512Mi
  limits:
    cpu: 1000m
    memory: 1024Mi
EOF

# Actualizar Falco con nueva configuración
helm upgrade falco falcosecurity/falco \
  --namespace falco \
  --values custom-falco-values.yaml
```

**Output esperado**:
```
Release "falco" has been upgraded. Happy Helming!
NAME: falco
LAST DEPLOYED: Tue Nov 04 10:25:00 2024
NAMESPACE: falco
STATUS: deployed
REVISION: 2
```

### 1.3 Verificar Configuración Aplicada

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

### 2.6 Modificar Reglas Existentes

```bash
# Ver reglas actuales
kubectl get configmap falco-custom-rules -n falco -o yaml

# Editar reglas
kubectl edit configmap falco-custom-rules -n falco

# Reiniciar Falco para aplicar
kubectl rollout restart daemonset/falco -n falco

# Verificar que se cargaron
kubectl logs -n falco -l app.kubernetes.io/name=falco | grep "Loading rules"
```

**Output esperado**:
```
Tue Nov 04 10:30:00 2024: Loading rules from: /etc/falco/falco_rules.yaml
Tue Nov 04 10:30:00 2024: Loading rules from: /etc/falco/rules.d/custom-rules.yaml
Tue Nov 04 10:30:01 2024: Loaded 15 custom rules
```

### 2.7 Probar una Regla Nueva

```bash
# Ejemplo: Probar regla de shell
kubectl run test-shell --image=nginx --restart=Never
kubectl exec test-shell -- /bin/bash -c "whoami"

# Ver si se generó alerta
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=20 | grep -i shell

# Limpiar
kubectl delete pod test-shell
```

**Output esperado de la alerta**:
```
Tue Nov 04 10:31:15 2024: Warning Shell spawned in container 
  (user=root user_uid=0 container_id=abc123 container_name=test-shell 
   image=nginx command=/bin/bash -c whoami pid=12345 parent=containerd-shim)
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

**Default Deny Ingress Only** (más práctico):
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: production
spec:
  podSelector: {}
  policyTypes:
  - Ingress  # Solo bloquea ingress, egress libre
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

### 3.6 Testing de Network Policies

```bash
# Script de test completo
cat > test-netpol.sh <<'EOF'
#!/bin/bash

echo "Testing Network Policies..."

# Crear pods con labels correctos
kubectl run web -n production --labels="tier=web" --image=nginx
kubectl run api -n production --labels="tier=api" --image=nginx  
kubectl run db -n production --labels="tier=db" --image=nginx

# Exponer como servicios
kubectl expose pod api -n production --port=80
kubectl expose pod db -n production --port=80

sleep 10

# Test 1: Web → API (debe funcionar)
echo "Test 1: Web → API"
kubectl exec web -n production -- curl -s -m 3 http://api && echo "✅ PASS" || echo "❌ FAIL"

# Test 2: Web → DB (debe fallar)
echo "Test 2: Web → DB"
kubectl exec web -n production -- curl -s -m 3 http://db && echo "❌ FAIL" || echo "✅ PASS"

# Test 3: API → DB (debe funcionar)
echo "Test 3: API → DB"
kubectl exec api -n production -- curl -s -m 3 http://db && echo "✅ PASS" || echo "❌ FAIL"

# Limpiar
kubectl delete pod web api db -n production
kubectl delete svc api db -n production
EOF

chmod +x test-netpol.sh
./test-netpol.sh
```

**Output esperado**:
```
Testing Network Policies...
Test 1: Web → API
✅ PASS
Test 2: Web → DB
✅ PASS (blocked as expected)
Test 3: API → DB
✅ PASS
```

---

## 4. Configuración de Alertas

### 4.1 Configurar Slack

**Paso 1: Crear Webhook en Slack**
1. Ir a https://api.slack.com/messaging/webhooks
2. Crear nuevo webhook
3. Seleccionar canal (ej: `#security-alerts`)
4. Copiar URL: `https://hooks.slack.com/services/T00/B00/XXX`

**Paso 2: Configurar Falcosidekick**
```bash
helm upgrade falcosidekick falcosecurity/falcosidekick \
  --namespace falco \
  --reuse-values \
  --set config.slack.webhookurl="https://hooks.slack.com/services/T00/B00/XXX" \
  --set config.slack.minimumpriority="warning" \
  --set config.slack.messageformat="text" \
  --set config.slack.username="Falco Security"
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

### 4.2 Configurar Microsoft Teams

```bash
# Crear Incoming Webhook en Teams
# Copiar URL

helm upgrade falcosidekick falcosecurity/falcosidekick \
  --namespace falco \
  --reuse-values \
  --set config.teams.webhookurl="https://outlook.office.com/webhook/xxx" \
  --set config.teams.minimumpriority="warning" \
  --set config.teams.activityimage="https://falco.org/img/falco-logo.png"
```

### 4.3 Configurar Múltiples Destinos

```bash
helm upgrade falcosidekick falcosecurity/falcosidekick \
  --namespace falco \
  --reuse-values \
  --set config.slack.webhookurl="..." \
  --set config.teams.webhookurl="..." \
  --set config.webhook.address="http://my-siem.com/webhook" \
  --set config.webhook.minimumpriority="error"
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

## 5. Configuración de Persistencia

### 5.1 Redis con PersistentVolume

```yaml
# Crear StorageClass
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: redis-storage
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
---
# Crear PersistentVolume
apiVersion: v1
kind: PersistentVolume
metadata:
  name: redis-pv
spec:
  capacity:
    storage: 10Gi
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: redis-storage
  hostPath:
    path: /mnt/data/redis
    type: DirectoryOrCreate
```

**Aplicar**:
```bash
kubectl apply -f redis-storage.yaml

# Reinstalar con persistencia
helm upgrade falcosidekick falcosecurity/falcosidekick \
  --namespace falco \
  --reuse-values \
  --set redis.master.persistence.enabled=true \
  --set redis.master.persistence.storageClass=redis-storage \
  --set redis.master.persistence.size=10Gi
```

**Verificar**:
```bash
kubectl get pvc -n falco
```

**Output esperado**:
```
NAME                          STATUS   VOLUME     CAPACITY   ACCESS MODES
redis-data-...-redis-0        Bound    redis-pv   10Gi       RWO
```

---

## 6. Configuración de Recursos

### 6.1 Limites y Requests

```yaml
# Para Falco
resources:
  requests:
    cpu: 100m      # CPU mínima garantizada
    memory: 512Mi  # RAM mínima garantizada
  limits:
    cpu: 1000m     # CPU máxima permitida
    memory: 1024Mi # RAM máxima permitida
```

**Aplicar**:
```bash
helm upgrade falco falcosecurity/falco \
  --namespace falco \
  --reuse-values \
  --set resources.requests.cpu=100m \
  --set resources.requests.memory=512Mi \
  --set resources.limits.cpu=1000m \
  --set resources.limits.memory=1024Mi
```

**Verificar uso real**:
```bash
kubectl top pod -n falco
```

**Output esperado**:
```
NAME                       CPU(cores)   MEMORY(bytes)
falco-xxxxx                45m          350Mi
falco-yyyyy                42m          340Mi
falcosidekick-zzzzz        15m          128Mi
```

---

## 7. Configuración Avanzada

### 7.1 Rate Limiting de Alertas

```bash
helm upgrade falco falcosecurity/falco \
  --namespace falco \
  --reuse-values \
  --set falco.outputs_rate=5  # Max 5 alertas por segundo
```

### 7.2 Buffering de Eventos

```bash
helm upgrade falco falcosecurity/falco \
  --namespace falco \
  --reuse-values \
  --set falco.outputs_max_burst=1000  # Buffer de 1000 eventos
```

### 7.3 Configuración de Log Level

```bash
helm upgrade falco falcosecurity/falco \
  --namespace falco \
  --reuse-values \
  --set falco.log_level=info  # debug, info, warning, error
```

---

**Total de palabras**: ~2,500 ✅  
**Última actualización**: Noviembre 2024
