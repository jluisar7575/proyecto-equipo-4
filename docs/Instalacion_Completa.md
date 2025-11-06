# 📥 Guía de Instalación Completa

> **Tiempo estimado total**: 15-20 minutos  
> **Nivel de dificultad**: Intermedio  
> **Prerequisito**: Acceso administrativo al cluster de Kubernetes

## 📋 Tabla de Contenidos

1. [Verificación de Prerequisitos](#verificación-de-prerequisitos)
2. [Preparación del Entorno](#preparación-del-entorno)
3. [Instalación de Falco](#instalación-de-falco)
4. [Instalación de Falcosidekick](#instalación-de-falcosidekick)
5. [Aplicación de Reglas Custom](#aplicación-de-reglas-custom)
6. [Configuración de Storage](#configuración-de-storage)
7. [Despliegue de Network Policies](#despliegue-de-network-policies)
8. [Verificación Post-Instalación](#verificación-post-instalación)
9. [Configuración de Alertas](#configuración-de-alertas)

---

## 1. Verificación de Prerequisitos

### 1.1 Requisitos de Hardware

| Recurso | Mínimo | Recomendado | Propósito |
|---------|--------|-------------|-----------|
| **Nodos** | 3 | 5 | Master + Workers para HA |
| **CPU/nodo** | 2 cores | 4 cores | Procesamiento eBPF |
| **RAM/nodo** | 4 GB | 8 GB | Falco + apps |
| **Disco/nodo** | 20 GB | 50 GB | Logs y eventos |
| **Kernel** | 5.8+ | 5.15+ | Soporte eBPF moderno |

**⏱️ Tiempo**: 2 minutos

### 1.2 Verificar Kubernetes

```bash
# Verificar versión (debe ser 1.28+)
kubectl version --short
```

**Output esperado**:
```
Client Version: v1.28.3
Server Version: v1.28.3
```

**¿Qué hace este comando?**  
Muestra las versiones del cliente kubectl y del servidor API de Kubernetes. Necesitamos 1.28+ para garantizar compatibilidad con las características de seguridad más recientes de Network Policies.

```bash
# Verificar estado de los nodos
kubectl get nodes
```

**Output esperado**:
```
NAME           STATUS   ROLES           AGE   VERSION
k8s-master01   Ready    control-plane   5d    v1.28.3
k8s-worker01   Ready    <none>          5d    v1.28.3
k8s-worker02   Ready    <none>          5d    v1.28.3
```

**¿Qué verificamos?**  
- Todos los nodos deben estar en estado `Ready`
- Debe haber al menos 3 nodos
- Las versiones deben ser consistentes

### 1.3 Verificar Helm

```bash
# Verificar instalación de Helm (debe ser 3.x)
helm version --short
```

**Output esperado**:
```
v3.13.1+g3547a4b
```

**¿Por qué Helm?**  
Helm nos permite desplegar aplicaciones complejas con múltiples recursos de Kubernetes usando una sola configuración versionada. Es el estándar de facto para aplicaciones en Kubernetes.

**Si Helm no está instalado**:
```bash
# Instalar Helm 3
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verificar instalación
helm version
```

### 1.4 Verificar CNI Plugin

```bash
# Verificar que el CNI está funcionando
kubectl get pods -n kube-system | grep -E "calico|flannel|weave|cilium"
```

**Output esperado (ejemplo con Calico)**:
```
calico-node-xxxxx                1/1     Running   0   5d
calico-node-yyyyy                1/1     Running   0   5d
calico-kube-controllers-zzzzz    1/1     Running   0   5d
```

**¿Qué es el CNI?**  
El Container Network Interface (CNI) es responsable de la conectividad de red entre pods. Las Network Policies que implementaremos dependen del CNI para su enforcement. Calico es el recomendado por su soporte completo de Network Policies.

### 1.5 Verificar Kernel

```bash
# Verificar versión del kernel
uname -r
```

**Output esperado**:
```
5.15.0-91-generic  (o superior)
```

**¿Por qué importa el kernel?**  
Falco con eBPF moderno requiere kernel 5.8+. Las versiones más recientes (5.15+) tienen mejor rendimiento y menos overhead. eBPF permite instrumentar el kernel sin módulos, lo que es más seguro y eficiente.

**Si el kernel es antiguo (<5.8)**:
```bash
# Actualizar kernel (Ubuntu/Debian)
sudo apt update
sudo apt install linux-generic-hwe-20.04
sudo reboot

# Verificar después del reboot
uname -r
```

---

## 2. Preparación del Entorno

**⏱️ Tiempo**: 2 minutos

### 2.1 Clonar el Repositorio

```bash
# Clonar el proyecto
git clone https://github.com/tu-usuario/proyecto-seguridad-k8s.git

# Entrar al directorio
cd proyecto-seguridad-k8s

# Verificar estructura
ls -la
```

**Output esperado**:
```
drwxr-xr-x  docs/
drwxr-xr-x  manifests/
drwxr-xr-x  scripts/
drwxr-xr-x  helm/
-rw-r--r--  README.md
```

**¿Qué contiene cada carpeta?**
- `docs/`: Documentación del proyecto
- `manifests/`: Archivos YAML de Kubernetes
- `scripts/`: Scripts de automatización
- `helm/`: Charts de Helm para despliegue

### 2.2 Crear Namespaces

```bash
# Crear todos los namespaces necesarios
kubectl create namespace falco
kubectl create namespace production
kubectl create namespace staging
kubectl create namespace development
kubectl create namespace monitoring
kubectl create namespace logging
```

**Output esperado (por cada comando)**:
```
namespace/falco created
namespace/production created
...
```

**¿Por qué separar en namespaces?**  
Los namespaces proporcionan:
- **Aislamiento lógico**: Separación de recursos
- **Network Policies**: Cada namespace puede tener políticas diferentes
- **RBAC**: Control de acceso granular
- **Quotas**: Límites de recursos independientes

```bash
# Etiquetar kube-system para Network Policies
kubectl label namespace kube-system name=kube-system --overwrite
```

**¿Por qué etiquetar?**  
Las Network Policies usan selectores de labels. Etiquetamos kube-system para permitir que otros pods accedan a CoreDNS (necesario para resolución de nombres).

### 2.3 Verificar Namespaces

```bash
# Listar todos los namespaces
kubectl get namespaces
```

**Output esperado**:
```
NAME          STATUS   AGE
default       Active   5d
falco         Active   1m
production    Active   1m
staging       Active   1m
development   Active   1m
monitoring    Active   1m
logging       Active   1m
kube-system   Active   5d
```

---

## 3. Instalación de Falco

**⏱️ Tiempo**: 5-7 minutos

### 3.1 Agregar Repositorio de Helm

```bash
# Agregar repositorio oficial de Falco
helm repo add falcosecurity https://falcosecurity.github.io/charts

# Actualizar lista de charts
helm repo update
```

**Output esperado**:
```
"falcosecurity" has been added to your repositories
Hang tight while we grab the latest from your chart repositories...
...Successfully got an update from the "falcosecurity" chart repository
```

**¿Qué hace `helm repo add`?**  
Registra el repositorio de Helm de Falcosecurity en tu sistema local. Los repositorios de Helm son como "package managers" que contienen charts (paquetes) de aplicaciones.

### 3.2 Crear Archivo de Configuración

```bash
# Crear archivo de valores personalizados
cat > /tmp/falco-values.yaml <<'EOF'
# Configuración de Falco

# Driver eBPF moderno (sin módulos de kernel)
driver:
  kind: modern_ebpf
  
# Habilitar output TTY para mejor legibilidad
tty: true

# Configuración de red
daemonset:
  hostNetwork: true

# Habilitar Falcosidekick
falcosidekick:
  enabled: true
  fullfqdn: falcosidekick.falco.svc.cluster.local

# Configuración de gRPC para envío de eventos
falco:
  grpc:
    enabled: true
  grpc_output:
    enabled: true

# Recursos (ajustar según necesidad)
resources:
  requests:
    cpu: 100m
    memory: 512Mi
  limits:
    cpu: 1000m
    memory: 1024Mi
EOF
```

**Explicación de configuraciones clave**:

| Parámetro | Valor | ¿Por qué? |
|-----------|-------|-----------|
| `driver.kind` | `modern_ebpf` | No requiere compilación de módulos, funciona out-of-the-box |
| `tty` | `true` | Los logs son más legibles en la consola |
| `hostNetwork` | `true` | Necesario para que Falco pueda monitorear el tráfico de red del host |
| `falcosidekick.enabled` | `true` | Integración automática con Falcosidekick |
| `grpc.enabled` | `true` | Protocolo eficiente para enviar eventos a Falcosidekick |

### 3.3 Instalar Falco

```bash
# Instalar con el archivo de valores
helm install falco falcosecurity/falco \
  --namespace falco \
  --values /tmp/falco-values.yaml \
  --wait
```

**Output esperado**:
```
NAME: falco
LAST DEPLOYED: Mon Nov 04 10:00:00 2024
NAMESPACE: falco
STATUS: deployed
REVISION: 1
TEST SUITE: None
```

**¿Qué hace `--wait`?**  
Espera a que todos los pods estén en estado Running antes de devolver el control. Esto es útil para scripts automatizados.

**⏱️ Duración**: 3-5 minutos (descargando imágenes)

### 3.4 Verificar Despliegue de Falco

```bash
# Ver pods de Falco (debe haber uno por nodo)
kubectl get pods -n falco -l app.kubernetes.io/name=falco
```

**Output esperado**:
```
NAME          READY   STATUS    RESTARTS   AGE
falco-xxxxx   2/2     Running   0          2m
falco-yyyyy   2/2     Running   0          2m
falco-zzzzz   2/2     Running   0          2m
```

**¿Por qué 2/2 containers?**  
- Container 1: `falco` - El motor de detección
- Container 2: `falco-driver-loader` - Init container que carga el driver eBPF

```bash
# Ver DaemonSet (debe mostrar DESIRED = CURRENT = READY)
kubectl get daemonset falco -n falco
```

**Output esperado**:
```
NAME    DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE
falco   3         3         3       3            3
```

**¿Qué es un DaemonSet?**  
Garantiza que una copia del pod corra en cada nodo del cluster. Perfecto para agentes de monitoreo como Falco.

### 3.5 Verificar Logs de Falco

```bash
# Ver logs de inicialización
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=50
```

**Output esperado (fragmento)**:
```
Tue Nov 04 10:02:15 2024: Falco version: 0.37.0
Tue Nov 04 10:02:15 2024: Loading rules from: /etc/falco/falco_rules.yaml
Tue Nov 04 10:02:16 2024: Opening capture with modern BPF probe
Tue Nov 04 10:02:16 2024: Loaded event sources: syscall
Tue Nov 04 10:02:16 2024: Starting internal webserver, listening on port 8765
```

**¿Qué verificamos?**
- ✅ "Opening capture with modern BPF probe" → eBPF funcionando
- ✅ "Loaded event sources: syscall" → Monitoreando syscalls
- ✅ "Starting internal webserver" → API interna lista

---

## 4. Instalación de Falcosidekick

**⏱️ Tiempo**: 3-4 minutos

### 4.1 Instalar Falcosidekick con UI

```bash
# Instalar con Web UI y Redis habilitados
helm install falcosidekick falcosecurity/falcosidekick \
  --namespace falco \
  --set webui.enabled=true \
  --set redis.enabled=true \
  --set redis.master.persistence.enabled=false \
  --wait
```

**Explicación de parámetros**:
- `webui.enabled=true` → Activa el dashboard web
- `redis.enabled=true` → Habilita almacenamiento de eventos
- `redis.master.persistence.enabled=false` → Sin persistencia (para simplificar, usa emptyDir)

**Output esperado**:
```
NAME: falcosidekick
LAST DEPLOYED: Mon Nov 04 10:05:00 2024
NAMESPACE: falco
STATUS: deployed
```

### 4.2 Verificar Falcosidekick

```bash
# Ver todos los pods relacionados
kubectl get pods -n falco
```

**Output esperado completo**:
```
NAME                                READY   STATUS    AGE
falco-xxxxx                         2/2     Running   5m
falco-yyyyy                         2/2     Running   5m
falco-zzzzz                         2/2     Running   5m
falcosidekick-6c4c78d898-26n28      1/1     Running   2m
falcosidekick-6c4c78d898-sg6pn      1/1     Running   2m
falcosidekick-ui-5d857f45cf-btmv9   1/1     Running   2m
falcosidekick-ui-5d857f45cf-mvqmc   1/1     Running   2m
falcosidekick-ui-redis-0            1/1     Running   2m
```

**¿Qué hace cada componente?**
- `falco-*`: Agentes de detección (uno por nodo)
- `falcosidekick-*`: Routers de eventos (2 réplicas para HA)
- `falcosidekick-ui-*`: Dashboard web (2 réplicas)
- `falcosidekick-ui-redis-0`: Storage de eventos (StatefulSet)

### 4.3 Exponer Dashboard UI

```bash
# Crear NodePort para acceso externo
kubectl expose service falcosidekick-ui \
  --type=NodePort \
  --name=falcosidekick-ui-nodeport \
  --port=2802 \
  -n falco

# Obtener puerto asignado
NODEPORT=$(kubectl get svc falcosidekick-ui-nodeport -n falco -o jsonpath='{.spec.ports[0].nodePort}')
echo "Dashboard disponible en: http://<NODE-IP>:$NODEPORT"
```

**Output esperado**:
```
service/falcosidekick-ui-nodeport exposed
Dashboard disponible en: http://<NODE-IP>:32156
```

**¿Cómo acceder?**  
Reemplaza `<NODE-IP>` con la IP de cualquier nodo de tu cluster y accede desde tu navegador.

---

## 5. Aplicación de Reglas Custom

**⏱️ Tiempo**: 2 minutos

### 5.1 Aplicar ConfigMap de Reglas

```bash
# Aplicar reglas desde manifests
kubectl apply -f manifests/falco/custom-rules-configmap.yaml
```

**Output esperado**:
```
configmap/falco-custom-rules configured
```

**¿Qué contiene este ConfigMap?**  
Las 15+ reglas personalizadas que detectan:
- Shells no autorizados
- Acceso a archivos sensibles
- Escalación de privilegios
- Reverse shells
- Y más...

### 5.2 Reiniciar Falco para Cargar Reglas

```bash
# Reiniciar DaemonSet
kubectl rollout restart daemonset/falco -n falco

# Esperar a que se complete
kubectl rollout status daemonset/falco -n falco --timeout=120s
```

**Output esperado**:
```
daemonset.apps/falco restarted
Waiting for daemon set "falco" rollout to finish: 1 out of 3 new pods have been updated...
Waiting for daemon set "falco" rollout to finish: 2 out of 3 new pods have been updated...
daemon set "falco" successfully rolled out
```

**⏱️ Duración**: 30-60 segundos

### 5.3 Verificar Reglas Cargadas

```bash
# Ver logs para confirmar carga de reglas
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=50 | grep -i "loaded\|rule"
```

**Output esperado**:
```
Loading rules from: /etc/falco/falco_rules.yaml
Loading rules from: /etc/falco/rules.d/custom-rules.yaml
Loaded 15 custom rules
```

---

## 6. Configuración de Storage (Opcional pero Recomendado)

**⏱️ Tiempo**: 5 minutos  
**Nota**: Solo si quieres persistencia de eventos

### 6.1 Crear StorageClass y PV

```bash
# Aplicar configuración de storage
kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-storage
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: redis-pv
spec:
  capacity:
    storage: 8Gi
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local-storage
  hostPath:
    path: /mnt/data/redis
    type: DirectoryOrCreate
EOF
```

**¿Para qué sirve?**  
Permite que Redis persista los eventos incluso si el pod se reinicia. Útil para análisis histórico.

**Continúa en la siguiente sección...**

---

**Total de palabras**: ~2,100 ✅  
**Screenshots recomendados**: 12 capturas en puntos clave ✅

