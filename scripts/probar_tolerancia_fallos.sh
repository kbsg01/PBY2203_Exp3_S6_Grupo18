#!/usr/bin/env bash
# Demuestra el Circuit Breaker (Resilience4j) de bff-web: detiene core-service a proposito y
# repite la consulta de cuenta hasta que el circuito abre, mostrando que bff-web responde con
# un 503 controlado (via CoreServiceNoDisponibleException) en vez de un error crudo o un
# timeout colgado. Pensado para correr DESPUES de scripts/probar_apis.sh, ya que mata el
# proceso de core-service (no lo vuelve a levantar).
#
# Requiere: curl, jq, pgrep. Asume que los 6 servicios (config-server, eureka-server,
# core-service y los 3 BFF) ya estan arriba en sus puertos por defecto.
set -euo pipefail

WEB=https://localhost:8081

echo "=== Deteniendo core-service para forzar la apertura del circuit breaker ==="
PID_CORE=$(pgrep -f core-service/target/core-service.jar || true)
if [ -z "$PID_CORE" ]; then
  echo "No se encontro el proceso de core-service en ejecucion (¿ya estaba detenido?)."
  exit 1
fi
kill "$PID_CORE"
sleep 3

TOKEN=$(curl -s -k -X POST "$WEB/api/web/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"cuentaId":101,"nombre":"John Doe"}' | jq -r .token)

echo "=== Llamadas repetidas a bff-web con core-service caido ==="
echo "(la config de bff-web abre el circuito tras 5 llamadas con 50% de fallos; las primeras devuelven"
echo " la excepcion cruda del RestTemplate, las siguientes ya devuelven el 503 controlado del fallback)"
for i in $(seq 1 8); do
  echo "--- intento $i ---"
  curl -s -k -w "HTTP %{http_code}\n" -H "Authorization: Bearer $TOKEN" \
    "$WEB/api/web/cuentas/101"
done
