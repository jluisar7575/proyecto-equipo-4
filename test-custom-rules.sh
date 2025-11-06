#!/bin/bash
set +e  # permite continuar tras errores
# ============================================================
# test-falco.sh
# Script para probar reglas personalizadas de Falco 0.42.0
# Crea un pod Debian ligero y ejecuta pruebas controladas
# ============================================================

NAMESPACE="default"
POD_NAME="test-falco"
IMAGE="debian:bullseye-slim"

echo "[+] Creando pod de prueba $POD_NAME ..."
kubectl run $POD_NAME --image=$IMAGE -n $NAMESPACE --restart=Never -- sleep infinity

echo "[+] Esperando a que el pod esté en estado Running ..."
kubectl wait --for=condition=Ready pod/$POD_NAME -n $NAMESPACE --timeout=120s

echo "[+] Actualizando e instalando utilidades requeridas ..."
kubectl exec -n $NAMESPACE -it $POD_NAME -- bash -c "
  apt-get update -qq && apt-get install -y -qq \
  sudo netcat nmap gcc make libcap2-bin curl wget passwd cron procps
"

echo "[+] Listo. Ejecutando pruebas Falco personalizadas..."
echo "--------------------------------------------------------"

# 1. Shell en contenedor
echo "[1] Prueba: Spawned shell in container"
kubectl exec -n $NAMESPACE $POD_NAME -- bash -c "bash -c 'echo Shell abierta dentro del contenedor'"
#kubectl exec -n default test-falco -- bash -c "bash -c 'echo Shell abierta dentro del contenedor'"

# 2. Escritura en /etc
echo "[2] Prueba: Write to Sensitive System Directories"
/bin/echo "[TEST] Falco sensitive write" | kubectl exec -i -n $NAMESPACE $POD_NAME -- tee /etc/prueba_falco.txt >/dev/null
#/bin/echo "[TEST] Falco sensitive write" | kubectl exec -i -n default test-falco -- tee /etc/prueba_falco.txt >/dev/null

# 3. Lectura de /etc/shadow
echo "[3] Prueba: Read Sensitive Files (Filtered)"
kubectl exec -n $NAMESPACE -it $POD_NAME -- bash -c "cat /etc/shadow || true"
#kubectl exec -n default -it test-falco -- bash -c "cat /etc/shadow || true"

# 4. Conexión sospechosa
echo "[4] Prueba: Custom Suspicious Network Connection"
kubectl exec -n $NAMESPACE -it $POD_NAME -- bash -c "timeout 3s nc -vz 1.1.1.1 9000 || true"
#kubectl exec -n default -it test-falco -- bash -c "timeout 3s nc -vz 1.1.1.1 9000 || true"

# 5. Escalación de privilegios
echo "[5] Prueba: Privilege escalation"
kubectl exec -n $NAMESPACE -it $POD_NAME -- bash -c "sudo id || su -c id || true"
#kubectl exec -n default -it test-falco -- bash -c "sudo id || su -c id || true"

# 6. Modificación de binarios del sistema
echo "[6] Prueba: System Binary Modified (Filtered)"
kubectl exec -n $NAMESPACE -it $POD_NAME -- bash -c "touch /usr/bin/falco_test_bin || true"
#kubectl exec -n default -it test-falco -- bash -c "touch /usr/bin/falco_test_bin || true"

# 7. Modificación de capabilities
echo "[7] Prueba: Capabilities Sensibles Agregadas"
kubectl exec -n $NAMESPACE -it $POD_NAME -- bash -c "setcap cap_net_raw+ep /bin/ping || true"
#kubectl exec -n default -it test-falco -- bash -c "setcap cap_net_raw+ep /bin/ping || true"

# 8. Acceso a secrets
echo "[8] Prueba: Acceso a Secrets de Kubernetes"
kubectl exec -n $NAMESPACE -it $POD_NAME -- bash -c "cat /run/secrets/kubernetes.io/serviceaccount/token || true"
#kubectl exec -n default -it test-falco -- bash -c "cat /run/secrets/kubernetes.io/serviceaccount/token || true"

# 9. Descarga con wget/curl
echo "[9] Prueba: Descarga de Archivos en Contenedor"
kubectl exec -n $NAMESPACE -it $POD_NAME -- bash -c "wget -q https://example.com || curl -s https://example.com >/dev/null"
#kubectl exec -n default -it test-falco -- bash -c "wget -q https://example.com || curl -s https://example.com >/dev/null"

# 10. Creación de usuario
echo "[10] Prueba: Creacion de Usuario en Contenedor"
kubectl exec -n $NAMESPACE -it $POD_NAME -- bash -c "useradd testuser || adduser testuser --disabled-password --gecos '' || true"
#kubectl exec -n default -it test-falco -- bash -c "useradd testuser || adduser testuser --disabled-password --gecos '' || true"

# 11. Cambio de password
echo "[11] Prueba: Cambio de Password en Contenedor"
kubectl exec -n $NAMESPACE -it $POD_NAME -- bash -c "echo 'testuser:1234' | chpasswd || passwd testuser || true"
#kubectl exec -n default -it test-falco -- bash -c "echo 'testuser:1234' | chpasswd || passwd testuser || true"

# 12. Escaneo de puertos
echo "[12] Prueba: Escaneo de Puertos Detectado"
kubectl exec -n $NAMESPACE -it $POD_NAME -- bash -c "nmap -p 22,80,443 127.0.0.1 || true"
#kubectl exec -n default -it test-falco -- bash -c "nmap -p 22,80,443 127.0.0.1 || true"

# 13. Compilación de código
echo "[13] Prueba: Compilacion de Codigo en Contenedor"
kubectl exec -n $NAMESPACE -it $POD_NAME -- bash -c "echo 'int main(){return 0;}' > test.c && gcc test.c -o test && ./test"
#kubectl exec -n default -it test-falco -- bash -c "echo 'int main(){return 0;}' > test.c && gcc test.c -o test && ./test"

# 14. Instalación de paquetes
echo "[14] Prueba: Instalacion de Paquetes en Runtime"
kubectl exec -n $NAMESPACE -it $POD_NAME -- bash -c "apt-get install -y -qq cowsay || true"
#kubectl exec -n default -it test-falco -- bash -c "apt-get install -y -qq cowsay || true"

# 15. Creación de cron job
echo "[15] Prueba: Creacion de Cron Job en Contenedor"
kubectl exec -n $NAMESPACE -it $POD_NAME -- bash -c "echo '* * * * * echo test' | crontab -"
#kubectl exec -n default -it test-falco -- bash -c "echo '* * * * * echo test' | crontab -"

echo "--------------------------------------------------------"
echo "[✔] Todas las pruebas han sido ejecutadas."
echo "[ℹ] Puedes revisar las alertas Falco con:"
echo "    kubectl logs -n falco -l app.kubernetes.io/name=falco -c falco -f"
echo "    o en Falcosidekick-UI o Slack."

