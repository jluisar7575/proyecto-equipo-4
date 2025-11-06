
# 🧠 Falco + Network Policies (Runtime Security)

## 📘 Descripción del Proyecto

Este proyecto implementa un entorno de **seguridad en Kubernetes** utilizando **Falco con UI (Falcosidekick UI)**,  y **Network Policies** en un clúster desplegado sobre **Rocky Linux** en el cual las alertas generadas por **Falco** se mostraran tanto en el **Dashboard** como en una aplicacion de terceros como lo es **Slack**.

El objetivo principal es **detectar comportamientos anómalos y controlar la comunicación entre pods**, garantizando un entorno seguro y monitoreado.

Falco actúa como un **IDS (Intrusion Detection System)** en tiempo real para contenedores y Kubernetes, mientras que las **Network Policies** limitan el tráfico entre pods para minimizar la superficie de ataque.  
El proyecto incluye además **reglas personalizadas (Custom Rules)** que permiten ajustar el comportamiento de Falco a los requerimientos específicos del entorno.

---

## 🏗️ Arquitectura del Proyecto

### 🔹 Componentes principales:

| Componente | Función |
|-------------|----------|
| **Falco DaemonSet** | Monitorea los eventos del kernel en cada nodo del clúster |
| **Falcosidekick** | Recibe las alertas de Falco y las reenvía a integraciones externas (Slack, UI, etc.) |
| **Falcosidekick UI** | Panel visual donde se muestran las alertas en tiempo real |
| **Slack Integration** | Notificaciones inmediatas en un canal de Slack |
| **Network Policies** | Restringen el tráfico entre pods para prevenir movimientos laterales |
| **Custom Rules** | Reglas personalizadas para detectar comportamientos específicos |

### 🔹 Diagrama de arquitectura

```mermaid
graph TD
    subgraph Cluster Kubernetes
        F[Pods del Cluster] -->|Eventos del contenedor / K8s API| A[Pod Falco DaemonSet]
        E[Kernel Host] -->|Syscalls / Eventos del sistema| A
        A -->|Alertas JSON| B[Falcosidekick Pod]
        B -->|Notificaciones| C[Falcosidekick UI]
        B -->|HTTP Webhook| D[Slack Channel]
        G[Network Policies] -->|Restringen tráfico| F
    end
    C -->|Dashboard visual| H[Usuario / Admin]
    D -->|Alertas en tiempo real| H
```
### 🔹 Prerrequisitos
| Requisito                           | Descripción                                    |
| ----------------------------------- | ---------------------------------------------- |
| **Sistema Operativo**               | Rocky Linux 9 o superior                       |
| **Kubernetes**                      | v1.28+ (instalado y funcionando)               |
| **kubectl**                         | Configurado para acceder al clúster            |
| **Helm**                            | v3 o superior                                  |
| **Falcoctl (opcional)**             | Para manejar reglas de Falco                   |
| **Conexión a Internet**             | Para descargar charts e imágenes de contenedor |
| **Permisos administrativos (sudo)** | Requeridos para instalación                    |

### 🔹 Instalación (Todo se hace desde el nodo Master)
- **Obtener el Webhook para slack**
    - Ve a https://api.slack.com/apps
    - Click en "Create New App" → "From scratch"
    - Dale un nombre (ej: "Falco Alerts") y selecciona tu workspace
    - En el menú lateral, ve a "Incoming Webhooks"
    - Activa "Activate Incoming Webhooks"
    - Click en "Add New Webhook to Workspace"
    - Selecciona el canal donde quieres recibir las alertas
    - Copia la URL del webhook (se ve como: https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXX)
    - Editar el falco-values.yaml en la seccion del webhook (se indica en el manifiesto)
      
- **Instalar HELM (si aun no lo tienes)**
    - $ curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash**
- **Crear los volumenes persistentes donde se almacenaran los eventos de falco**
    - **NOTA: SI LOS NOMBRES DE TU HOST SON DIFERENTES A k8s-worker01 y k8s-worker02 CAMBIAR POR LOS QUE CORRESPONDEN**
    - $ ssh k8s-worker01 'sudo mkdir -p /mnt/data/redis && sudo chmod 777 /mnt/data/redis'
    - $ ssh k8s-worker02 'sudo mkdir -p /mnt/data/redis && sudo chmod 777 /mnt/data/redis'
      
- **Aplicar el manifiesto para el almacenamiento**
    - **NOTA: SI CAMBIASTE LOS NOMBRES DE HOST ABRE EL MANIFIESTO Y APLICA LOS NUEVOS NOMBRES DONDE SE INDICA**
    - $ kubectl apply -f storage_manifests.yaml

- **Agregar el repositorio de Falco**
    - $ helm repo add falcosecurity https://falcosecurity.github.io/charts
    - $ helm repo update
  
- **Instalar falco mediante un manifiesto (mas limpio, seguro y controlable )**
    - **NOTA: EL MANIFIESTO YA TIENE REGLAS CUSTOM CARGADAS PERO SE PUEDEN QUITAR BORRANDO LA SECCION**
    - $ helm install falco falcosecurity/falco -n falco -f falco-values.yaml
      
- **Agregar las Network Police**
    - **NOTA: EL MANIFIESTO CONTIENE UNA CIERTA TOPOLOGIA PARA MOSTRAR EL FUNCIONAMIENTO SI TU ENTORNO TIENE OTRA DEBES DE TRABAJAR DE ACUERDO A ELLA**
    - $ kubectl create namespace production
    - $ kubectl label namespace production name=production

- Aplicar el manifiesto con las Network Police
- $ kubectl apply -f netpol_default_deny.yaml

chmod +x netpol_quick_test.sh
./netpol_quick_test.sh



### 🔹 Configuración explicada

⚙️ Configuración

Falco Rules Path: /etc/falco/rules.d/

Custom Rules Mount: Se monta el ConfigMap falco-custom-rules

Logs: se visualizan con kubectl logs -n falco <falco-pod>

Falco UI: se expone por NodePort en el puerto 30080


### 🔹 Comandos de validación

kubectl get pods -n falco

kubectl logs -n falco -l app=falco

kubectl run test-nc --image=alpine --restart=Never -it -- nc 1.1.1.1 80

kubectl exec -it <otro-pod> -- wget -qO- backend:8080
