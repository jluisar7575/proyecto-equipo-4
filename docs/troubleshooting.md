# 🧩 TROUBLESHOOTING GUIDE

Guía centralizada de resolución de problemas del proyecto.  
Documenta incidencias técnicas, sus causas, soluciones y pasos de verificación.

---

## 📘 Índice

- [Formato de registro de incidentes](#-formato-de-registro-de-incidentes)
- [Guías de resolución](#-guías-de-resolución)
- [Historial de cambios](#-historial-de-cambios)

---

## 🧾 Formato de registro de incidentes

Cada nuevo problema debe documentarse con el siguiente formato:

---

### ⚙️ Problema 1: *Falco no registra correctamente los eventos después de la instalación con Helm*

#### 🧱 Entorno 
- **Sistema operativo:** Rocky Linux 9  
- **Kernel:** 5.14.0-570.55.1.el9_6.x86_64  
- **Kubernetes:** 1.28.15  
- **CNI:** Calico 3.27.0  
- **Falco:** 0.42.0  

---

#### 🔍 Descripción
Falco no registra eventos en sus logs.

---

#### 🚨 Síntomas

- Los pods de Falco corren correctamente, pero los logs muestran errores:

```bash
kubectl logs -n falco falco-pt675 -c falco-driver-loader
make: *** [Makefile:23: all] Error 2 
2025-11-04 01:06:44 ERROR failed: failed to build all requested drivers
```

- Falco nunca termina de iniciar:

```bash
kubectl logs -n falco -l app.kubernetes.io/name=falco -c falco --tail=50
Tue Nov 04 01:12:23 2025: Opening 'syscall' source with BPF probe.
Tue Nov 04 01:12:23 2025: [libs]: Trying to open the right engine!
```

- Los pods no levantan correctamente:

```bash
kubectl get pods -n falco -o wide
NAME          READY   STATUS       RESTARTS   AGE     IP              NODE
falco-pt675   0/2     Init:Error   2 (27s ago)   5m53s   10.244.32.132   k8s-master01
falco-rg2xb   0/2     Init:Error   3 (40s ago)   5m53s   10.244.79.69    k8s-worker01
```

---

#### 🧩 Causa raíz

El módulo del kernel no es compatible con la versión instalada.  
Falco usa distintos métodos para interactuar con el kernel y detectar las **syscalls**:

- **Falco Kernel Module (falco.ko)**  
  Más eficiente, pero requiere recompilar el kernel.

- **eBPF (Extended Berkeley Packet Filter)**  
  Compatible con kernels ≥ 4.14, no necesita recompilar el kernel, pero requiere dependencias y puntos de montaje activos.

---

#### 🧰 Solución aplicada

**1️⃣ Verificar compatibilidad del kernel e instalar headers**

```bash
uname -r
dnf install -y kernel-devel-$(uname -r) kernel-headers-$(uname -r)
```

**2️⃣ Crear punto de montaje para eBPF**

```bash
mkdir -p /sys/fs/bpf
mount | grep bpffs || mount -t bpf bpffs /sys/fs/bpf
echo "bpffs /sys/fs/bpf bpf defaults 0 0" >> /etc/fstab
```

**3️⃣ Verificar dependencias**

```bash
grep cgroup /proc/filesystems
mount | grep cgroup
```

**4️⃣ Verificar estado de containerd y kubelet**

```bash
systemctl status containerd --no-pager
systemctl status kubelet --no-pager
```

**5️⃣ Ejemplo de salida exitosa**

```text
# Kernel
5.14.0-570.55.1.el9_6.x86_64

# eBPF habilitado
CONFIG_BPF=y
CONFIG_BPF_SYSCALL=y
CONFIG_BPF_JIT=y
CONFIG_BPF_JIT_ALWAYS_ON=y
CONFIG_BPF_EVENTS=y
CONFIG_BPF_LSM=y

# bpffs montado
bpffs on /sys/fs/bpf type bpf (rw,relatime)

# containerd
Active: active (running)

# kubelet
Active: active (running)
```

**6️⃣ Instalar Falco con driver eBPF**

```bash
helm install falco falcosecurity/falco   --namespace falco --create-namespace   --version 7.0.0   --set driver.kind=bpf   --set ebpf.enabled=true
```

---

### ⚙️ Problema 2: *Carga de reglas personalizadas en Falco*

#### 🧱 Entorno 
- **Sistema operativo:** Rocky Linux 9  
- **Kernel:** 5.14.0-570.55.1.el9_6.x86_64  
- **Kubernetes:** 1.28.15  
- **CNI:** Calico 3.27.0  
- **Falco:** 0.42.0  

---

#### 🔍 Descripción
Falco no carga las reglas personalizadas de los siguientes directorios:

- `/etc/falco/falco_rules.yaml`  
- `/etc/falco/falco_rules.local.yaml`  
- `/etc/falco/k8s_audit_rules.yaml`

---

#### 🚨 Síntomas

No se reflejan las reglas agregadas en los logs de inicio.

---

#### 🧩 Causa raíz

Falco solo carga las reglas definidas al momento de la instalación.  
Verificado con:

```bash
kubectl logs -n falco -l app.kubernetes.io/name=falco -c falco | grep -A3 "Loading rules from"
```

**Salida:**

```text
Wed Nov 05 06:18:27 2025: Loading rules from:
Wed Nov 05 06:18:27 2025:    /etc/falco/falco_rules.yaml | schema validation: ok
Wed Nov 05 06:18:27 2025: Hostname value has been overridden via environment variable to: k8s-worker01
```

---

#### 🧰 Solución aplicada

Agregar las reglas personalizadas directamente en el YAML de instalación o actualización de Falco:

```yaml
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
```

---

### ⚙️ Problema 3: *Error de conexión entre pods*

#### 🧱 Entorno 
- **Sistema operativo:** Rocky Linux 9  
- **Kernel:** 5.14.0-570.55.1.el9_6.x86_64  
- **Kubernetes:** 1.28.15  
- **CNI:** Calico 3.27.0  
- **Falco:** 0.42.0  

---

#### 🔍 Descripción
Los pods no pueden comunicarse entre sí.

---

#### 🚨 Síntomas

```bash
kubectl get pod -o wide
```

```text
NAME    READY   STATUS      RESTARTS   AGE     IP             NODE
test    0/1     Completed   0          22h     10.244.1.183   k8s-worker01
test1   1/1     Running     0          2m17s   10.244.2.48    k8s-worker02
test2   1/1     Running     0          2m4s    10.244.1.93    k8s-worker01
```

Prueba de ping:

```bash
kubectl exec -it test1 -- ping -c 3 10.244.2.48
```

**Salida:**
```text
PING 10.244.2.48 (10.244.2.48): 56 data bytes
.^C
--- 10 ping statistics ---
2 packets transmitted, 0 received, 100% packet loss
command terminated with exit code 1
```

---

#### 🧩 Causa raíz

El servicio **firewalld** interfiere con la comunicación entre pods y los túneles de red de Calico.

---

#### 🧰 Solución aplicada

Desactivar temporalmente el servicio `firewalld`:

```bash
systemctl stop firewalld
# o permanentemente
systemctl disable firewalld
```

> ⚠️ **Nota:** Dependiendo del entorno, deberás permitir manualmente los puertos usados por Kubernetes y Calico en producción, pero para pruebas rápidas se recomienda detener temporalmente el firewall.

---

## 🕓 Historial de cambios

| Fecha | Autor | Descripción |
|-------|--------|--------------|
| 2025-11-05 | R. Martínez | Creación inicial del documento de troubleshooting |
| 2025-11-05 | R. Martínez | Agregado casos Falco driver y reglas custom |
