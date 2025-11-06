# 📥 Guía de Instalación Completa

> **Tiempo estimado total**: 15-20 minutos  
> **Nivel de dificultad**: Intermedio  
> **Prerequisito**: Acceso administrativo al cluster de Kubernetes

## 📋 Tabla de Contenidos

1. [Verificación de Prerequisitos](#verificación-de-prerequisitos)
2. [Preparación del Entorno](#preparación-del-entorno)
3. [Instalación de Falco](#instalación-de-falco)
4. [Exponer Dashboard UI](#exponer-dashboard-UI)
5. [Aplicación de Reglas Custom](#aplicación-de-reglas-custom)
6. [Integracion con Slack](#integracion-con-slack)
7. [Despliegue de Network Policies](#despliegue-de-network-policies)
8. [Verificación Post-Instalación](#verificación-post-instalación)
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
git clone https://github.com/jluisar7575/proyecto-equipo-4.git

# Entrar al directorio
cd proyecto-equipo-4/

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
### 2.2 Copiar todos los archivos necesarios al home
```bash
cp ~/proyecto-equipo-4/manifests/*.yaml ~/
cp ~/proyecto-equipo-4/scripts/*.sh ~/
```
### 2.2 Copiar todos los archivos necesarios al home
```bash
cp ~/proyecto-equipo-4/manifests/*.yaml ~/
cp ~/proyecto-equipo-4/scripts/*.sh ~/
```
### 2.3 Crear un volumen persistente en cada worker
```bash
#Cambiar el nombre del Nodo en el comando si cuentas con otros#
ssh k8s-worker01 'sudo mkdir -p /mnt/data/redis && sudo chmod 777 /mnt/data/redis'
ssh k8s-worker02 'sudo mkdir -p /mnt/data/redis && sudo chmod 777 /mnt/data/redis'
```
**¿Por qué el volumen?**  
Falcosidekick necesita un espacio para almacenar los eventos que generan sus reglas y si no lo creamos simplemente no correra.
Ademas es otro medio para ir generando un historial si es necesario
### 2.2 Aplicamos el manifiesto
```bash
kubectl apply -f storage_manifests.yaml

#Si los nodos tienen un nombre diferente debes entrar al manifiesto y editar donde se indica#
nano storage_manifests.yaml
```

**Output esperado**:
```
 - key: kubernetes.io/hostname
          operator: In
          values:
          - k8s-worker01  # ⚠️ CAMBIAR por tu nombre de nodo
```

**Output esperado**:
```
storageclass.storage.k8s.io/local-storage changed
persistentvolume/redis-pv-worker01 changed
persistentvolume/redis-pv-worker02 changed

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

### 3.2 Crear Archivo de Configuración o aplicar el ya descargado

```bash
#solo si no lo tienes descargado
# Crear archivo de valores personalizados
cat > falco-values.yaml <<'EOF'
# Driver configuration
driver:
  kind: modern_ebpf

# JSON output
falco:
  jsonOutput: true
  grpc:
    enabled: true
  grpcOutput:
    enabled: true

# Falcosidekick configuration
falcosidekick:
  enabled: true
  
  config:
    slack:
      webhookurl: "https://hooks.slack.com/services/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"
      minimumpriority: "warning"
      outputformat: "all"
  
  webui:
    enabled: true
    redis:
      enabled: true
      master:
        persistence:
          enabled: true
          size: 8Gi

# CUSTOM RULES - Corregidas para Falco 0.42.0
customRules:
  custom-rules.yaml: |-
    # 1. Detectar shells spawneados en containers
    - rule: Spawned shell in container
      desc: Detecta ejecución de shells dentro de contenedores
      condition: evt.type=execve and container.id != host and proc.name in (sh, bash, ash, zsh)
      output: "SHELL SPAWNED in container (user=%user.name cmd=%proc.cmdline container=%container.id)"
      priority: WARNING
      tags: [custom, container, shell]

    # 2. Alertar escrituras en /etc
    - rule: Write to Sensitive System Directories
      desc: Detecta escrituras en directorios críticos (/etc, /bin, /usr/bin) ignorando archivos de cache, logs, runtime y otros conocidos
      condition: >
        evt.type in (open, creat, openat, pwrite, write)
        and evt.is_open_write=true
        and (
          fd.name startswith /etc or
          fd.name startswith /bin or
          fd.name startswith /usr/bin
        )
        and not fd.name in (
          /etc/ld.so.cache,
          /etc/machine-id,
          /etc/hosts,
          /etc/resolv.conf,
          /etc/passwd,
          /etc/group,
          /etc/shadow
        )
        and not fd.name startswith /etc/ssl/certs
        and not fd.name startswith /etc/service/
        and not fd.name startswith /etc/sv/
        and not fd.name startswith /etc/systemd/
        and not fd.name startswith /var/cache/
        and not fd.name startswith /var/lib/
        and not fd.name startswith /usr/bin/.wh
      output: "ALERTA: Escritura en directorio sensible detectada (user=%user.name pid=%proc.pid file=%fd.name)"
      priority: WARNING
      tags: [filesystem, security, sensitive]
      
      
    # 3. Detectar lectura de /etc/shadow
    - rule: Read Sensitive Files (Filtered)
      desc: Detecta lecturas de archivos sensibles como /etc/shadow solo por procesos inesperados
      condition: >
        evt.type in (open, openat, read)
        and fd.name in (/etc/shadow, /etc/gshadow)
        and evt.is_open_read=true
        and not user.uid in (0, 1, 65534)
        and not proc.name in (sshd, systemd, login, getent)
      output: "ALERTA: Lectura sospechosa de archivo sensible detectada (user=%user.name pid=%proc.pid proc=%proc.name file=%fd.name)"
      priority: CRITICAL
      tags: [filesystem, security, sensitive]
          
      
    # 4. Alertar Conexion sospechosa
    - rule: Custom Suspicious Network Connection
      desc: Mi detección de conexiones de red sospechosas
      condition: >
        outbound and
        container and
        fd.l4proto=tcp and
        not fd.sport in (80, 443, 8080, 8443, 53, 3306, 5432, 6379, 9200, 27017) and
        not proc.name in (curl, wget, apt, apt-get, yum, dnf, npm, pip, gem, go) and
        not container.name in (calico-node, kube-proxy, coredns) and
        user.uid > 0
      output: >
        [CUSTOM] Outbound connection to non-standard port (user=%user.name 
        container=%container.name image=%container.image.repository 
        process=%proc.name cmdline=%proc.cmdline connection=%fd.name 
        k8s_ns=%k8s.ns.name k8s_pod=%k8s.pod.name)
      priority: WARNING
      tags: [network, mitre_command_and_control, T1071, custom]

    # 5. Detectar escalación de privilegios mediante sudo o su
    - rule: Privilege escalation
      desc: Detecta escalación de privilegios mediante uso de sudo o su
      condition: evt.type=execve and proc.name in (sudo, su)
      output: "ESCALACION DE PRIVILEGIOS (user=%user.name cmd=%proc.cmdline)"
      priority: CRITICAL
      tags: [custom, privilege]
      output: "ESCALACION DE PRIVILEGIOS (user=%user.name cmd=%proc.cmdline)"
      priority: CRITICAL
      tags: [custom, privilege]

    # 6. Alertar cambios en binarios críticos (/usr/sbin, /sbin)
    - rule: System Binary Modified (Filtered)
      desc: Detecta cambios en binarios del sistema ignorando actualizaciones legítimas
      condition: >
        evt.type in (open, creat, rename, unlink)
        and (fd.name startswith /bin or
             fd.name startswith /sbin or
             fd.name startswith /usr/bin or
             fd.name startswith /usr/sbin)
        and not proc.name in (rpm, dpkg, yum, dnf, apt, apt-get, zypper)
      output: "ALERTA: Cambio sospechoso en binario del sistema (user=%user.name pid=%proc.pid proc=%proc.name file=%fd.name)"
      priority: CRITICAL
      tags: [filesystem, integrity, custom]
  
  
      # 7. Detectar Capabilities
    - rule: Capabilities Sensibles Agregadas
      desc: Detecta cuando se agregan capabilities sensibles a contenedores
      condition: spawned_process and container and proc.name in (capsh, setcap, getcap) and not proc.pname in (dockerd, containerd)
      output: Modificación de capabilities detectada (container=%container.name process=%proc.name command=%proc.cmdline)
      priority: WARNING
      tags: [container, capabilities]

    # 8. Alertar Acceso a Secrets
    - rule: Acceso a Secrets de Kubernetes
      desc: Detecta cuando un proceso accede a archivos de secrets montados en contenedores
      condition: open_read and container and fd.name startswith /run/secrets/kubernetes.io and not proc.name in (kubelet, dockerd, containerd)
      output: Acceso a secret de Kubernetes detectado (container=%container.name image=%container.image.repository process=%proc.name file=%fd.name command=%proc.cmdline)
      priority: WARNING
      tags: [container, secrets, kubernetes]

    # 9. Detectar descarga de archivos con wget/curl
    - rule: Descarga de Archivos en Contenedor
      desc: Detecta uso de wget o curl para descargar archivos
      condition: evt.type=execve and container and proc.name in (wget, curl)
      output: "DESCARGA DETECTADA (container=%container.name process=%proc.name cmd=%proc.cmdline)"
      priority: WARNING
      tags: [custom, network, download]
    
    # 10. Detectar creación de usuarios
    - rule: Creacion de Usuario en Contenedor
      desc: Detecta intentos de crear nuevos usuarios
      condition: evt.type=execve and container and proc.name in (useradd, adduser)
      output: "CREACION DE USUARIO (container=%container.name process=%proc.name cmd=%proc.cmdline)"
      priority: WARNING
      tags: [custom, users, persistence]
    
    # 11. Detectar cambios de contraseña
    - rule: Cambio de Password en Contenedor
      desc: Detecta intentos de cambiar contraseñas
      condition: evt.type=execve and container and proc.name in (passwd, chpasswd)
      output: "CAMBIO DE PASSWORD (container=%container.name process=%proc.name cmd=%proc.cmdline)"
      priority: WARNING
      tags: [custom, users, credentials]
    
    # 12. Detectar escaneo de puertos
    - rule: Escaneo de Puertos Detectado
      desc: Detecta herramientas de escaneo de puertos
      condition: evt.type=execve and container and proc.name in (nmap, masscan, nc, netcat, ncat)
      output: "ESCANEO DE PUERTOS (container=%container.name process=%proc.name cmd=%proc.cmdline)"
      priority: WARNING
      tags: [custom, network, scanning]
    
    # 13. Detectar compilación de código
    - rule: Compilacion de Codigo en Contenedor
      desc: Detecta compiladores ejecutándose en contenedores
      condition: evt.type=execve and container and proc.name in (gcc, g++, cc, make, cmake)
      output: "COMPILADOR DETECTADO (container=%container.name process=%proc.name cmd=%proc.cmdline)"
      priority: INFO
      tags: [custom, compilation, development]
    
    # 14. Detectar instalación de paquetes
    - rule: Instalacion de Paquetes en Runtime
      desc: Detecta gestores de paquetes instalando software
      condition: evt.type=execve and container and proc.name in (apt-get, yum, apk, dnf, pip, npm)
      output: "INSTALACION DE PAQUETES (container=%container.name process=%proc.name cmd=%proc.cmdline)"
      priority: WARNING
      tags: [custom, package, runtime]
    
    # 15. Detectar creación de cron jobs
    - rule: Creacion de Cron Job en Contenedor
      desc: Detecta creación o modificación de tareas programadas
      condition: evt.type=execve and container and proc.name in (crontab, at)
      output: "CRON JOB DETECTADO (container=%container.name process=%proc.name cmd=%proc.cmdline)"
      priority: WARNING
      tags: [custom, persistence, cron]
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
| `customRules` |  | Agregar reglas independientes a las que falco trae cargadas por default |
| `webhookurl` |  | Es la parte donde se colocara el WeebHook generado de Slack |

### 3.3 Instalar Falco + Falcosidekick + CustomRules

```bash
# Instalar con el archivo de valores descargado o generado
helm install falco falcosecurity/falco \
  -n falco \
  -f falco-values.yaml
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

**¿Qué hace `-n y -f `?**  
-n sirve para crear un namespace y -f es para forzar a que se instale con los valores del manifiesto

**⏱️ Duración**: 3-5 minutos

### 3.4 Verificar Despliegue de Falco

```bash
# Ver pods de Falco (debe haber uno por nodo)
kubectl get pods -n falco
```

**Output esperado**:
```
NAME                                      READY   STATUS        RESTARTS      AGE
falco-falcosidekick-b84c95f6d-5tfcf       1/1     Running       0             29h
falco-falcosidekick-b84c95f6d-9trlc       1/1     Running       0             29h
falco-falcosidekick-b84c95f6d-qgl2s       1/1     Running       0             18m
falco-falcosidekick-b84c95f6d-s4mqs       1/1     Running       0             18m
falco-falcosidekick-ui-77ddb87b6d-74kqd   1/1     Running       0             18m
falco-falcosidekick-ui-77ddb87b6d-rmftp   1/1     Running       0             34h
falco-falcosidekick-ui-77ddb87b6d-vk622   1/1     Running       0             34h
falco-falcosidekick-ui-77ddb87b6d-xftxt   1/1     Running       0             18m
falco-falcosidekick-ui-redis-0            1/1     Running       0             34h
falco-mkznd                               2/2     Running       0             29h
falco-nhmw5                               2/2     Running       0             29h
falco-xv5d5                               2/2     Running       0             29h

```



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

### 4. Exponer Dashboard UI

```bash
# Crear NodePort para acceso externo

kubectl port-forward -n falco svc/falco-falcosidekick-ui 2802:2802 --address=0.0.0.0

```

**Output esperado**:
```
Forwarding from 0.0.0.0:2802 -> 2802
```

**¿Cómo acceder?**  
Reemplaza `<NODE-IP>:<NODE-PORT>` con la IP de cualquier nodo de tu cluster y el puerto en tu navegador.

---

## 5. Aplicación de Reglas Custom

**⏱️ Tiempo**: 2 minutos

### 5.1 Aplicar nuevas reglas

```bash
# Editar el manifiesto con la nueva regla
nano falco-values.yaml
```

**¿Porque de esta manera?**  
Al momento de instalar falco nosotros le dimos reglas ya pre-cargadas las cuales ejecuta desde su instalacion y
si se quiere agregar mas solo debemos modificar el manifiesto y asi aseguramos la integridad de las configuraciones.

### 5.2 Reiniciar Falco para Cargar Reglas

```bash
#Actualizar Reglas
helm upgrade falco falcosecurity/falco \
  -n falco \
  -f falco-values.yaml

# Reiniciar DaemonSet
kubectl rollout restart daemonset/falco -n falco

# Esperar a que se complete

```

**Output esperado**:
```
daemonset.apps/falco restarted
Waiting for daemon set "falco" rollout to finish: 1 out of 3 new pods have been updated...
Waiting for daemon set "falco" rollout to finish: 2 out of 3 new pods have been updated...
daemon set "falco" successfully rolled out
```

**⏱️ Duración**: 30-60 segundos

---

## 6. Integracion con Slack

**⏱️ Tiempo**: 1 minuto  
**Nota**: Ya debes tener el Weebhoock de tu aplicacion de no tenerlos ve a la documentacion de configuracion o lee el README.md

### 6.1 Editar el manifiesto

```bash
#Editar el falco-values.yaml en la seccion del webhook
nano falco-values.yaml

#Aplicar los cambios como en el paso anterior
helm upgrade falco falcosecurity/falco \
  -n falco \
  -f falco-values.yaml
```

**¿Para qué sirve el weebhook?**  
Un webhook es una forma de comunicación automática entre aplicaciones.
Permite que una aplicación envíe información a otra en tiempo real, sin que la segunda tenga que pedirla.

---

## 7. Creacion de Network Policies

**⏱️ Tiempo**: 5 minuto  
**Nota**: Se agrego un manifiesto con una arquitectura de ejemplo (se puede modificar de acuerdo a las necesidades)

### 7.1 Crear y etiquetar namespace
```bash
kubectl create namespace production
kubectl label namespace production name=production
```
### 7.2 Aplicar el manifiesto 

```bash
kubectl apply -f netpol_default_deny.yaml
```

**¿Para qué las network policies?**  
Permiten definir quién puede comunicarse con quién (Ingress) y a dónde pueden salir los pods (Egress), mejorando la seguridad y aislamiento dentro del clúster.

---
## 8. Verificacion post-instalacion

**⏱️ Tiempo**: 2-3 minutos  

### 8.1 Verificar CustomRules

```bash
#En el navegador se deben de observar los eventos al igual que en Slack
```

### 8.2 Verificar NetworkPolicies

```bash
#Dar permisos de ejecucion y ejecutar
chmod +x netpol_quick_test.sh
./netpol_quick_test.sh
```
**Output esperado**:
```
🧪 TEST 1: Frontend → Backend:8080 (debe estar PERMITIDO)
Comando: kubectl exec test-frontend -n production -- timeout 5 wget -qO- 10.244.69.211:8080
✅ Conexión permitida o respondió (correcto)

🧪 TEST 2: Frontend → Database:5432 (debe estar BLOQUEADO)
Comando: kubectl exec test-frontend -n production -- timeout 5 wget -qO- 10.244.79.85:5432
✅ Conexión BLOQUEADA (correcto - Policy funcionando)

🧪 TEST 3: Backend → Database:5432 (debe estar PERMITIDO)
Comando: kubectl exec test-backend -n production -- timeout 5 nc -zv 10.244.79.85 5432
✅ Conexión permitida o respondió (correcto)

🧪 TEST 4: Backend → Internet:443 (debe estar PERMITIDO)
Comando: kubectl exec test-backend -n production -- timeout 5 nc -zv 8.8.8.8
✅ Conexión permitida o respondió (correcto)

🧪 TEST 5: Database -> Backend (debe estar BLOQUEADO)
Comando: kubectl exec test-database -n production -- timeout 5 wget -qO- 10.244.69.211:8080
✅ Conexión BLOQUEADA (correcto - Policy funcionando)

🧪 TEST 6: Database -> Frontend (debe estar BLOQUEADO)
kubectl exec test-database -n production -- timeout 5 wget -qO- 10.244.79.84:80
✅ Conexión BLOQUEADA (correcto - Policy funcionando)

🧪 TEST 7: Unauthorized → Backend:8080 (debe estar BLOQUEADO - Default Deny)
Comando: kubectl exec test-unauthorized -n production -- timeout 5 nc -zv 10.244.69.211 8080
✅ Conexión BLOQUEADA (correcto - Default Deny funcionando)

🧪 TEST 8: Unauthorized → FRONTEND:80 (debe estar BLOQUEADO - Default Deny)
Comando: kubectl exec test-unauthorized -n production -- timeout 5 nc -zv 10.244.79.84 80
✅ Conexión BLOQUEADA (correcto - Default Deny funcionando)

🧪 TEST 9: DNS Resolution (todos los pods deben resolver 'kubernetes.default')
Probando resolucion DNS desde pod/test-backend ...
✅ DNS funciona desde pod/test-backend

Probando resolucion DNS desde pod/test-database ...
✅ DNS funciona desde pod/test-database

Probando resolucion DNS desde pod/test-frontend ...
✅ DNS funciona desde pod/test-frontend

Probando resolucion DNS desde pod/test-unauthorized ...
✅ DNS funciona desde pod/test-unauthorized
```

---

