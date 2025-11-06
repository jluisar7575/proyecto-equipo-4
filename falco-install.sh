#!/bin/bash
# =========================================================
# 🚀 Instalación automatizada de Falco + Falco UI
# Genera storage_manifests.yaml dinámicamente según los nodos del clúster
# y aplica la instalación con un falco-values.yaml existente.
# =========================================================

set -e

echo "=========================================="
echo "🚀 Iniciando instalación de Falco y Falco UI"
echo "=========================================="

# =========================================================
# 1️⃣ Detectar nodos worker dinámicamente
# =========================================================
echo ""
echo "🔍 Detectando nodos worker..."

# Obtener todos los nodos excepto el master/control-plane
WORKERS=($(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | grep -vE "master|control-plane"))

if [ ${#WORKERS[@]} -eq 0 ]; then
  echo "❌ No se detectaron nodos worker. Verifica tu clúster."
  exit 1
fi

echo "✅ Nodos detectados: ${WORKERS[*]}"

# =========================================================
# 2️⃣ Crear directorios en cada worker vía SSH
# =========================================================
echo ""
echo "📦 Creando directorios /mnt/data/redis en los workers..."

for NODE in "${WORKERS[@]}"; do
  echo " -> Configurando $NODE ..."
  ssh "$NODE" 'sudo mkdir -p /mnt/data/redis && sudo chmod 777 /mnt/data/redis'
done

echo "✅ Directorios creados correctamente en todos los workers."

# =========================================================
# 3️⃣ Generar storage_manifests.yaml dinámico
# =========================================================
echo ""
echo "🧩 Generando archivo storage_manifests.yaml ..."

cat <<EOF > storage_manifests.yaml
# =========================================
# STORAGE CLASS Y PERSISTENT VOLUMES
# =========================================

# StorageClass para local storage
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-storage
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Retain

---
EOF

i=1
for NODE in "${WORKERS[@]}"; do
cat <<EOF >> storage_manifests.yaml
# PersistentVolume en ${NODE}
apiVersion: v1
kind: PersistentVolume
metadata:
  name: redis-pv-${NODE}
  labels:
    type: local
    app: redis
spec:
  capacity:
    storage: 8Gi
  volumeMode: Filesystem
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local-storage
  local:
    path: /mnt/data/redis
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - ${NODE}

---
EOF
((i++))
done

echo "✅ storage_manifests.yaml generado correctamente."
echo ""

# =========================================================
# 4️⃣ Aplicar manifiesto de almacenamiento
# =========================================================
echo "📤 Aplicando manifiesto de almacenamiento..."
kubectl apply -f storage_manifests.yaml

echo ""
kubectl get storageclass
kubectl get pv

# =========================================================
# 5️⃣ Instalar Falco con tu falco-values.yaml existente
# =========================================================
echo ""
echo "📦 Instalando Falco con tu falco-values.yaml existente..."

helm repo add falcosecurity https://falcosecurity.github.io/charts
helm repo update

kubectl create namespace falco --dry-run=client -o yaml | kubectl apply -f -

helm install falco falcosecurity/falco \
  -n falco \
  -f falco-values.yaml


echo "✅ Falco instalado correctamente."

# =========================================================
# 6️⃣ Crear namespace y aplicar NetworkPolicy
# =========================================================
echo ""
echo "🌐 Creando namespace 'production' y aplicando políticas de red..."

kubectl create namespace production --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace production name=production --overwrite

kubectl apply -f netpol_default_deny.yaml -n production

echo ""
echo "✅ Namespace y política de red aplicados correctamente."

# =========================================================
# ✅ Finalización
# =========================================================
echo ""
echo "🎉 Instalación completada exitosamente."
echo "👉 Revisa los recursos con:"
echo "   kubectl get pods -A"
echo "   kubectl get pv"
echo "   kubectl get netpol -n production"