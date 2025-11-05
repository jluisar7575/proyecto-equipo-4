# proyecto-equipo-4

# 🧠 Proyecto de Seguridad en Kubernetes con Falco + UI + Custom Rules + Network Policies

## 📘 Descripción del Proyecto

Este proyecto implementa un entorno de **seguridad en Kubernetes** utilizando **Falco**, **Falco UI** y **Network Policies** en un clúster desplegado sobre **Rocky Linux**.  
El objetivo principal es **detectar comportamientos anómalos y controlar la comunicación entre pods**, garantizando un entorno seguro y monitoreado.

Falco actúa como un **IDS (Intrusion Detection System)** en tiempo real para contenedores y Kubernetes, mientras que las **Network Policies** limitan el tráfico entre pods para minimizar la superficie de ataque.  
El proyecto incluye además **reglas personalizadas (Custom Rules)** que permiten ajustar el comportamiento de Falco a los requerimientos específicos del entorno.

---

## 🏗️ Arquitectura del Proyecto

### 🔹 Componentes principales:
- **Falco DaemonSet:** monitorea eventos del kernel dentro de cada nodo del clúster.
- **Falco UI:** interfaz web para visualizar alertas generadas por Falco.
- **Custom Rules:** reglas personalizadas para detección específica (por ejemplo, uso de `netcat`, creación de shells, acceso a archivos sensibles, etc.).
- **Network Policies:** definen qué pods pueden comunicarse entre sí.

### 🔹 Diagrama de arquitectura

```mermaid
graph TD
    A[Usuario / DevOps] -->|kubectl / Falco UI| B[Falco Namespace]
    B --> C[Falco DaemonSet]
    B --> D[Falco UI Pod]
    C -->|Alertas| D
    D -->|Interfaz Web| A
    E[Pods del Cluster] -->|Syscalls / Eventos| C
    F[Network Policies] -->|Restringen tráfico entre pods| E
