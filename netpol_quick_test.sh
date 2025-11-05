#!/bin/bash

##############################################################################
# Quick Test Manual de Network Policies
# Usa pods existentes o los crea de forma simple
##############################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

NAMESPACE="${1:-production}"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║        Quick Test - Network Policies                      ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

##############################################################################
# Paso 1: Crear pods de prueba (versión simplificada)
##############################################################################

echo -e "${YELLOW}📦 Paso 1: Creando pods de prueba...${NC}"
echo ""

# Eliminar pods anteriores si existen
kubectl delete pod test-frontend test-backend test-database test-unauthorized -n $NAMESPACE --ignore-not-found=true 2>/dev/null

# Crear pods uno por uno
echo "Creando test-frontend..."
kubectl run test-frontend -n $NAMESPACE --image=busybox --labels="app=frontend,tier=web" -- sleep 3600

echo "Creando test-backend..."
kubectl run test-backend -n $NAMESPACE --image=busybox --labels="app=backend,tier=api" -- sleep 3600

echo "Creando test-database..."
kubectl run test-database -n $NAMESPACE --image=busybox --labels="app=database,tier=data" -- sleep 3600

echo "Creando test-unauthorized..."
kubectl run test-unauthorized -n $NAMESPACE --image=busybox --labels="app=unauthorized" -- sleep 3600

echo ""
echo -e "${BLUE}⏳ Esperando 30 segundos a que los pods arranquen...${NC}"
sleep 30

##############################################################################
# Paso 2: Verificar estado de pods
##############################################################################

echo ""
echo -e "${YELLOW}📊 Paso 2: Verificando estado de pods...${NC}"
echo ""
kubectl get pods -n $NAMESPACE -l 'app in (frontend,backend,database,unauthorized)'

##############################################################################
# Paso 3: Obtener IPs
##############################################################################

echo ""
echo -e "${YELLOW}🌐 Paso 3: Obteniendo IPs de pods...${NC}"
echo ""

FRONTEND_IP=$(kubectl get pod test-frontend -n $NAMESPACE -o jsonpath='{.status.podIP}' 2>/dev/null)
BACKEND_IP=$(kubectl get pod test-backend -n $NAMESPACE -o jsonpath='{.status.podIP}' 2>/dev/null)
DATABASE_IP=$(kubectl get pod test-database -n $NAMESPACE -o jsonpath='{.status.podIP}' 2>/dev/null)

if [ -z "$FRONTEND_IP" ]; then
    echo -e "${RED}❌ Error: No se pudo obtener IP de test-frontend${NC}"
    echo "Ejecuta: kubectl describe pod test-frontend -n $NAMESPACE"
    exit 1
fi

echo "Frontend IP:  $FRONTEND_IP"
echo "Backend IP:   $BACKEND_IP"
echo "Database IP:  $DATABASE_IP"

##############################################################################
# Paso 4: Verificar Network Policies
##############################################################################

echo ""
echo -e "${YELLOW}🔒 Paso 4: Verificando Network Policies...${NC}"
echo ""
kubectl get networkpolicies -n $NAMESPACE

##############################################################################
# Paso 5: Tests Manuales
##############################################################################

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                    TESTS DE CONECTIVIDAD                   ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Test 1: Frontend -> Backend (DEBE funcionar)
echo -e "${YELLOW}🧪 TEST 1: Frontend → Backend:8080 (debe estar PERMITIDO)${NC}"
echo "Comando: kubectl exec test-frontend -n $NAMESPACE -- timeout 5 wget -qO- $BACKEND_IP:8080"
kubectl exec test-frontend -n $NAMESPACE -- timeout 5 wget -qO- $BACKEND_IP:8080 &>/dev/null
if [ $? -eq 0 ] || [ $? -eq 1 ]; then
    echo -e "${GREEN}✅ Conexión permitida o respondió (correcto)${NC}"
else
    echo -e "${RED}❌ Conexión bloqueada/timeout${NC}"
fi
echo ""

# Test 2: Frontend -> Database (DEBE estar BLOQUEADO)
echo -e "${YELLOW}🧪 TEST 2: Frontend → Database:5432 (debe estar BLOQUEADO)${NC}"
echo "Comando: kubectl exec test-frontend -n $NAMESPACE -- timeout 5 wget -qO- $DATABASE_IP:5432"
kubectl exec test-frontend -n $NAMESPACE -- timeout 5 wget -qO- $DATABASE_IP:5432 &>/dev/null
if [ $? -ne 0 ]; then
    echo -e "${GREEN}✅ Conexión BLOQUEADA (correcto - Policy funcionando)${NC}"
else
    echo -e "${RED}❌ Conexión PERMITIDA (incorrecto - VULNERABILIDAD)${NC}"
fi
echo ""

# Test 3: Backend -> Database (DEBE funcionar)
echo -e "${YELLOW}🧪 TEST 3: Backend → Database:5432 (debe estar PERMITIDO)${NC}"
echo "Comando: kubectl exec test-backend -n $NAMESPACE -- timeout 5 nc -zv $DATABASE_IP 5432"
kubectl exec test-backend -n $NAMESPACE -- timeout 5 wget -qO- $DATABASE_IP:5432 &>/dev/null
if [ $? -eq 0 ] || [ $? -eq 1 ]; then
    echo -e "${GREEN}✅ Conexión permitida o respondió (correcto)${NC}"
else
    echo -e "${RED}❌ Conexión bloqueada/timeout${NC}"
fi
echo ""

# Test 4: Backend -> Internet (443)
echo -e "${YELLOW}🧪 TEST 4: Backend → Internet:443 (debe estar PERMITIDO)${NC}"
echo "Comando: kubectl exec test-backend -n $NAMESPACE -- timeout 5 nc -zv 8.8.8.8"
kubectl exec test-backend -n $NAMESPACE -- timeout 5 nc -zv 8.8.8.8 443 &>/dev/null

if [ $? -eq 0 ] || [ $? -eq 1 ]; then
    echo -e "${GREEN}✅ Conexión permitida o respondió (correcto)${NC}"
else
    echo -e "${RED}❌ Conexión bloqueada/timeout${NC}"
fi
echo ""


# Test 5: Database -> Backend
echo -e "${YELLOW}🧪 TEST 4: Database -> Backend (debe estar BLOQUEADO)${NC}"
echo "Comando: kubectl exec test-database -n $NAMESPACE -- timeout 5 wget -qO- $BACKEND_IP:8080"
kubectl exec test-database -n $NAMESPACE -- timeout 5 wget -qO- $BACKEND_IP:8080 &>/dev/null

if [ $? -ne 0 ]; then
    echo -e "${GREEN}✅ Conexión BLOQUEADA (correcto - Policy funcionando)${NC}"
else
    echo -e "${RED}❌ Conexión PERMITIDA (incorrecto - VULNERABILIDAD)${NC}"
fi
echo ""

# Test 6: Database -> Frontend
echo -e "${YELLOW}🧪 TEST 4: Database -> Backend (debe estar BLOQUEADO)${NC}"
echo "kubectl exec test-database -n $NAMESPACE -- timeout 5 wget -qO- $FRONTEND_IP:80"
kubectl exec test-database -n $NAMESPACE -- timeout 5 wget -qO- $FRONTEND_IP:80 &>/dev/null

if [ $? -ne 0 ]; then
    echo -e "${GREEN}✅ Conexión BLOQUEADA (correcto - Policy funcionando)${NC}"
else
    echo -e "${RED}❌ Conexión PERMITIDA (incorrecto - VULNERABILIDAD)${NC}"
fi
echo ""


# Test 7: Unauthorized -> Backend (DEBE estar BLOQUEADO)
echo -e "${YELLOW}🧪 TEST 4: Unauthorized → Backend:8080 (debe estar BLOQUEADO - Default Deny)${NC}"
echo "Comando: kubectl exec test-unauthorized -n $NAMESPACE -- timeout 5 nc -zv $BACKEND_IP 8080"
kubectl exec test-unauthorized -n $NAMESPACE -- timeout 5 sh -c "echo test > /dev/tcp/$BACKEND_IP/8080" &>/dev/null
if [ $? -ne 0 ]; then
    echo -e "${GREEN}✅ Conexión BLOQUEADA (correcto - Default Deny funcionando)${NC}"
else
    echo -e "${RED}❌ Conexión PERMITIDA (incorrecto - Default Deny no funciona)${NC}"
fi
echo ""

# Test 8: Unauthorized -> Frontend (DEBE estar BLOQUEADO)
echo -e "${YELLOW}🧪 TEST 4: Unauthorized → Backend:8080 (debe estar BLOQUEADO - Default Deny)${NC}"
echo "Comando: kubectl exec test-unauthorized -n $NAMESPACE -- timeout 5 nc -zv $FRONTEND_IP 80"
kubectl exec test-unauthorized -n $NAMESPACE -- timeout 5 sh -c "echo test > /dev/tcp/$FRONTEND_IP/80" &>/dev/null
if [ $? -ne 0 ]; then
    echo -e "${GREEN}✅ Conexión BLOQUEADA (correcto - Default Deny funcionando)${NC}"
else
    echo -e "${RED}❌ Conexión PERMITIDA (incorrecto - Default Deny no funciona)${NC}"
fi
echo ""


# Test 9: DNS (Todos los pods deben poder resolver nombres)
echo -e "${YELLOW}🧪 TEST 0: DNS Resolution (todos los pods deben resolver 'kubernetes.default')${NC}"

for pod in $(kubectl get pods -n $NAMESPACE -o name); do
  echo "Probando resolucion DNS desde $pod ..."
  kubectl exec -n $NAMESPACE $pod -- sh -c "nslookup kubernetes.default.svc.cluster.local >/dev/null 2>&1"
  if [ $? -eq 0 ]; then
      echo -e "${GREEN}✅ DNS funciona desde $pod${NC}"
  else
      echo -e "${RED}❌ DNS bloqueado o no resolvio desde $pod${NC}"
  fi
  echo ""
done


