graph TB
    subgraph Internet["🌐 Internet"]
        Users[👥 Usuarios]
    end
    
    subgraph Cluster["☸️ Kubernetes Cluster - 3 Nodos"]
        subgraph Master["🎛️ Master Node"]
            API[API Server]
            Scheduler[Scheduler]
            ETCD[(etcd)]
            FalcoM[🛡️ Falco Agent]
        end
        
        subgraph Worker1["⚙️ Worker Node 1"]
            FalcoW1[🛡️ Falco Agent]
            Pods1[Application Pods]
            Kernel1[Kernel - Syscalls]
        end
        
        subgraph Worker2["⚙️ Worker Node 2"]
            FalcoW2[🛡️ Falco Agent]
            Pods2[Application Pods]
            Kernel2[Kernel - Syscalls]
        end
        
        subgraph FalcoNS["📦 Namespace: falco"]
            Falcosidekick[📢 Falcosidekick<br/>Alert Router]
            Redis[(💾 Redis<br/>Event Storage)]
            FalcoUI[🖥️ Dashboard UI<br/>Port 2802]
        end
        
        subgraph ProdNS["📦 Namespace: production"]
            Frontend[🌐 Frontend<br/>nginx:80/443]
            Backend[⚙️ Backend API<br/>Port 8080]
            Database[(🗄️ PostgreSQL<br/>Port 5432)]
            NetPol[🔒 Network Policies<br/>Default Deny]
        end
        
        subgraph DNSService["📦 Namespace: kube-system"]
            DNS[🌐 CoreDNS<br/>Port 53]
        end
    end
    
    subgraph External["🌍 External Services"]
        Slack[💬 Slack/Teams]
        ExternalAPI[🔌 External APIs<br/>Port 443]
    end
    
    subgraph Matrix["📊 MATRIZ DE CONECTIVIDAD"]
        direction TB
        M1["✅ Internet → Frontend :80/443<br/>Tráfico público via Ingress"]
        M2["✅ Frontend → Backend :8080<br/>Llamadas API desde capa web"]
        M3["❌ Frontend ⛔ Database :5432<br/>BLOQUEADO - No acceso directo"]
        M4["✅ Backend → Database :5432<br/>Única fuente autorizada"]
        M5["✅ Backend → External APIs :443<br/>Integraciones externas"]
        M6["❌ Database ⛔ Cualquiera<br/>BLOQUEADO - DB Aislada"]
        M7["✅ Todos → DNS :53<br/>Resolución de nombres"]
        M8["❌ Pods sin policy ⛔ Cualquiera<br/>BLOQUEADO - Default Deny"]
    end
    
    %% Conexiones permitidas (verde)
    Users -->|HTTPS :80/443| Frontend
    Frontend -->|API :8080| Backend
    Backend -->|SQL :5432| Database
    Backend -->|HTTPS :443| ExternalAPI
    Frontend -.->|DNS :53| DNS
    Backend -.->|DNS :53| DNS
    
    %% Conexiones bloqueadas (rojo)
    Frontend -.->|❌ BLOCKED :5432| Database
    Database -.->|❌ BLOCKED| ExternalAPI
    
    %% Falco Monitoring
    Kernel1 -->|Syscalls/Eventos| FalcoW1
    Kernel2 -->|Syscalls/Eventos| FalcoW2
    Pods1 -.->|K8s API Events| FalcoW1
    Pods2 -.->|K8s API Events| FalcoW2
    API -.->|K8s API Events| FalcoM
    
    FalcoM -->|Alertas JSON| Falcosidekick
    FalcoW1 -->|Alertas JSON| Falcosidekick
    FalcoW2 -->|Alertas JSON| Falcosidekick
    
    Falcosidekick -->|Store Events| Redis
    Falcosidekick -->|HTTP Webhook| Slack
    Falcosidekick -->|Dashboard Feed| FalcoUI
    
    %% Network Policy Enforcement
    NetPol -.->|Enforce Rules| Frontend
    NetPol -.->|Enforce Rules| Backend
    NetPol -.->|Enforce Rules| Database
    
    %% Admin Access
    FalcoUI -->|Visual Dashboard| Users
    Slack -->|Real-time Alerts| Users
    
    %% Estilos
    classDef security fill:#FFD700,stroke:#FF8C00,stroke-width:3px
    classDef blocked fill:#FFB6C6,stroke:#8B0000,stroke-width:2px,stroke-dasharray: 5 5
    classDef allowed fill:#90EE90,stroke:#006400,stroke-width:2px
    classDef matrix fill:#E6F3FF,stroke:#0066CC,stroke-width:2px
    classDef netpol fill:#FFE4B5,stroke:#8B4513,stroke-width:2px
    
    class FalcoM,FalcoW1,FalcoW2,Falcosidekick,FalcoUI,Redis security
    class M3,M6,M8 blocked
    class M1,M2,M4,M5,M7 allowed
    class Matrix matrix
    class NetPol netpol