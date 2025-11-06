# 🌐 Diagrama de Flujos de Red

## Arquitectura de Red con Network Policies

Este diagrama muestra todos los flujos de red permitidos y bloqueados en el cluster.

```mermaid
graph TB
    subgraph Internet["🌐 Internet"]
        Users[👥 Usuarios]
    end
    
    subgraph IngressNS["Namespace: ingress-nginx"]
        Ingress[🚪 Ingress Controller<br/>Puerto 80/443]
    end
    
    subgraph ProdNS["Namespace: production"]
        subgraph Frontend["Frontend Tier"]
            FE[🖥️ Frontend App<br/>nginx:80,443]
        end
        
        subgraph Backend["Backend Tier"]
            BE[⚙️ Backend API<br/>app:8080]
        end
        
        subgraph Database["Database Tier"]
            DB[(🗄️ PostgreSQL<br/>postgres:5432)]
        end
        
        subgraph Cache["Cache Tier"]
            Redis[(📦 Redis<br/>redis:6379)]
        end
    end
    
    subgraph MonitoringNS["Namespace: monitoring"]
        Prometheus[📊 Prometheus<br/>:9090]
        Grafana[📈 Grafana<br/>:3000]
    end
    
    subgraph LoggingNS["Namespace: logging"]
        ES[🔍 Elasticsearch<br/>:9200,9300]
        Kibana[📊 Kibana<br/>:5601]
        Fluentd[📝 Fluentd]
    end
    
    subgraph KubeSystem["Namespace: kube-system"]
        DNS[🌐 CoreDNS<br/>:53 UDP/TCP]
    end
    
    subgraph FalcoNS["Namespace: falco"]
        FalcoDaemon[🛡️ Falco DaemonSet<br/>eBPF Monitor]
        FalcoSK[📢 Falcosidekick<br/>Alert Router]
        FalcoUI[🖥️ Falcosidekick UI<br/>:2802]
    end
    
    subgraph External["🌍 Servicios Externos"]
        ExtAPI[🔌 APIs Externas<br/>:443]
        Slack[💬 Slack/Teams<br/>Webhooks]
    end
    
    %% Flujos de usuarios
    Users -->|HTTP/HTTPS| Ingress
    Ingress -->|HTTP/HTTPS| FE
    
    %% Flujos internos de aplicación
    FE -->|REST API :8080| BE
    FE -.->|❌ BLOQUEADO| DB
    BE -->|SQL :5432| DB
    BE -->|Cache :6379| Redis
    BE -->|HTTPS :443| ExtAPI
    
    %% Flujos de DNS (todos los pods)
    FE -.->|DNS :53| DNS
    BE -.->|DNS :53| DNS
    DB -.->|DNS :53| DNS
    Redis -.->|DNS :53| DNS
    Prometheus -.->|DNS :53| DNS
    
    %% Flujos de monitoreo
    Prometheus -->|Scrape :8080| FE
    Prometheus -->|Scrape :8080| BE
    Prometheus -->|Scrape :9090| DB
    Grafana -->|Query :9090| Prometheus
    
    %% Flujos de logging
    Fluentd -->|Logs :9200| ES
    Kibana -->|Query :9200| ES
    ES <-->|Cluster :9300| ES
    
    %% Flujos de Falco
    FalcoDaemon -->|Events| FalcoSK
    FalcoSK -->|Alerts| Slack
    FalcoSK -->|Dashboard| FalcoUI
    
    %% Estilos
    classDef allowed fill:#90EE90,stroke:#006400,stroke-width:2px
    classDef blocked fill:#FFB6C6,stroke:#8B0000,stroke-width:2px,stroke-dasharray: 5 5
    classDef security fill:#FFD700,stroke:#FF8C00,stroke-width:3px
    classDef external fill:#87CEEB,stroke:#4682B4,stroke-width:2px
    
    class FE,BE,DB,Redis,Prometheus,Grafana allowed
    class FalcoDaemon,FalcoSK,FalcoUI security
    class ExtAPI,Slack external
```

## Leyenda

### Colores y Estilos

- 🟢 **Verde sólido**: Flujo PERMITIDO por Network Policy
- 🔴 **Rojo punteado**: Flujo BLOQUEADO por Network Policy
- 🟡 **Amarillo**: Componentes de seguridad (Falco)
- 🔵 **Azul claro**: Servicios externos

### Símbolos

- **→** Flecha sólida: Conexión permitida
- **⇢** Flecha punteada: Conexión bloqueada
- **↔** Doble flecha: Comunicación bidireccional

## Flujos Permitidos

### Production Namespace

| Origen | Destino | Puerto | Protocolo | Justificación |
|--------|---------|--------|-----------|---------------|
| Internet | Frontend | 80, 443 | TCP | Acceso público a la aplicación |
| Frontend | Backend | 8080 | TCP | Consumo de API REST |
| Backend | Database | 5432 | TCP | Consultas SQL |
| Backend | Redis | 6379 | TCP | Cache de datos |
| Backend | Internet | 443 | TCP | Llamadas a APIs externas |
| Todos | CoreDNS | 53 | UDP/TCP | Resolución de nombres |

### Flujos BLOQUEADOS

| Origen | Destino | Razón |
|--------|---------|-------|
| Frontend | Database | ❌ Violación de arquitectura 3-tier |
| Frontend | Redis | ❌ Solo backend puede acceder al cache |
| Internet | Backend | ❌ Backend no debe ser accesible directamente |
| Internet | Database | ❌ Database nunca debe ser pública |
| Database | Internet | ❌ Database no necesita salida a internet |

## Network