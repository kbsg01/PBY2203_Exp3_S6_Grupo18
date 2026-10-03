#!/usr/bin/env bash
# Demuestra la tolerancia a fallos (Resilience4j) de bff-web frente a una caida de core-service:
# obtiene un token valido, detiene core-service a proposito y repite la consulta de cuenta,
# mostrando el estado REAL del circuit breaker (actuator) antes y despues:
#   - Cada peticion se reintenta (Retry "coreServiceLectura": 3 intentos con backoff 300/600 ms)
#     y, agotados los reintentos, el circuito cuenta UNA falla y responde 503 controlado.
#   - Tras 5 peticiones fallidas el circuito ABRE: las siguientes responden 503 al instante, sin
#     esperar timeouts ni reintentar (se protege tanto al cliente como a core-service).
#
# Dos modos:
#   bash scripts/probar_tolerancia_fallos.sh            # procesos "java -jar" (generar_evidencia.sh)
#       Detiene core-service (jps) y NO lo vuelve a levantar.
#   bash scripts/probar_tolerancia_fallos.sh --docker   # docker-compose (generar_evidencia_docker.sh)
#       Detiene el contenedor de core-service y ademas demuestra la RECUPERACION: lo vuelve a
#       iniciar y muestra el circuito pasando OPEN -> HALF_OPEN -> CLOSED sin intervencion manual,
#       y luego la restart policy de Docker (el proceso cae y Docker lo reinicia solo).
#
# El token se obtiene ANTES de detener core-service a proposito: el login tambien depende de
# core-service (AuthController valida cuentaId+nombre contra el).
#
# Requiere: curl, jq; jps (modo java -jar) o docker compose (modo --docker).
set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/_common.sh

MODO_DOCKER=false
[ "${1:-}" = "--docker" ] && MODO_DOCKER=true

WEB=https://localhost:8081

# Estado del circuit breaker "coreService" de bff-web, leido de su actuator. El puerto de gestion
# (18081) no se publica fuera de Docker, asi que en modo --docker se consulta desde DENTRO del
# propio contenedor.
estado_circuito() {
  local json
  if [ "$MODO_DOCKER" = true ]; then
    json=$(docker compose exec -T bff-web curl -s http://localhost:18081/actuator/circuitbreakers)
  else
    json=$(curl -s http://localhost:18081/actuator/circuitbreakers)
  fi
  echo "$json" | jq -c '.circuitBreakers.coreService | {state, failureRate, bufferedCalls, failedCalls, notPermittedCalls}'
}

log_bff_web() {
  if [ "$MODO_DOCKER" = true ]; then
    docker compose logs --no-log-prefix bff-web 2>/dev/null
  else
    cat evidencias/evidencia03-bff-web.log 2>/dev/null
  fi
}

consultar_cuenta() {
  curl -s -k -o /tmp/respuesta_cb.json -w "HTTP %{http_code} en %{time_total}s" \
    -H "Authorization: Bearer $TOKEN" "$WEB/api/web/cuentas/101"
  echo " -> $(jq -c '.error // {cuentaId, saldoActual}' /tmp/respuesta_cb.json 2>/dev/null || cat /tmp/respuesta_cb.json)"
}

echo "=== Obteniendo un token valido (core-service aun arriba) ==="
TOKEN=$(curl -s -k -X POST "$WEB/api/web/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"cuentaId":101,"nombre":"John Doe"}' | jq -r .token)
if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
  echo "No se pudo obtener un token (¿bff-web o core-service no estan arriba?)." >&2
  exit 1
fi
echo "Consulta de control con core-service arriba:"
consultar_cuenta
echo "Circuito antes de la falla: $(estado_circuito)"

echo
echo "=== Deteniendo core-service para forzar la apertura del circuit breaker ==="
if [ "$MODO_DOCKER" = true ]; then
  docker compose stop core-service
else
  PID_CORE=$(pid_de_jar "core-service/target/core-service.jar")
  if [ -z "$PID_CORE" ]; then
    echo "No se encontro el proceso de core-service en ejecucion (¿ya estaba detenido?)." >&2
    exit 1
  fi
  detener_pid "$PID_CORE"
fi
sleep 3

echo
echo "=== Llamadas repetidas a bff-web con core-service caido ==="
echo "(mientras el circuito esta CERRADO, cada peticion hace 3 intentos (Retry con backoff 300/600 ms)"
echo " y cada intento espera a que la conexion falle: ~1s si el puerto rechaza la conexion (java -jar),"
echo " o el connect-timeout de 5s si la IP ya no responde (contenedor detenido). El circuito ABRE cuando"
echo " >=50% de las ultimas 10 llamadas fallaron; desde ahi el 503 es inmediato, sin tocar la red)"
for i in $(seq 1 8); do
  printf -- "--- intento %d: " "$i"
  consultar_cuenta
done
echo "Circuito despues de las fallas: $(estado_circuito)"

echo
echo "=== Reintentos y transiciones registrados por Resilience4j en el log de bff-web ==="
log_bff_web | grep -E "Retry 'coreServiceLectura'|CircuitBreaker 'coreService'" | tail -n 8 || true

if [ "$MODO_DOCKER" = false ]; then
  echo
  echo "=== Fin (modo java -jar: core-service queda detenido) ==="
  exit 0
fi

echo
echo "=== Recuperacion automatica: se vuelve a iniciar core-service ==="
docker compose start core-service
for _ in $(seq 1 60); do
  [ "$(docker inspect -f '{{.State.Health.Status}}' bancoxyz-core-service)" = "healthy" ] && break
  sleep 2
done
echo "core-service: $(docker inspect -f '{{.State.Health.Status}}' bancoxyz-core-service)"
echo "Circuito ahora: $(estado_circuito)"
echo "(cada 10s pasa solo a HALF_OPEN y deja pasar 3 llamadas de prueba: si fallan -porque la cache de"
echo " Eureka de bff-web aun no ve a core-service- vuelve a OPEN; cuando tienen exito, se CIERRA)"
echo "Repitiendo la consulta hasta que bff-web vuelva a resolver core-service via Eureka..."
for i in $(seq 1 45); do
  CODIGO=$(curl -s -k -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $TOKEN" "$WEB/api/web/cuentas/101")
  if [ "$CODIGO" = "200" ]; then
    echo "Respuesta 200 tras $i intento(s) (~$((i * 2))s)."
    break
  fi
  sleep 2
done
for _ in 1 2 3; do consultar_cuenta; done
echo "Circuito tras la recuperacion: $(estado_circuito)"
echo "Transiciones del circuito durante toda la prueba (log de bff-web):"
log_bff_web | grep "CircuitBreaker 'coreService'" | sed 's/^/  /' || true

echo
echo "=== Restart policy de Docker (restart: unless-stopped): el proceso de core-service cae ==="
REINICIOS_ANTES=$(docker inspect -f '{{.RestartCount}}' bancoxyz-core-service)
echo "Reinicios de core-service antes: $REINICIOS_ANTES"
# SIGTERM al PID 1 del contenedor (la JVM): simula una caida del proceso, no un "docker stop"
# manual (que Docker respeta y no revierte).
INICIO_CAIDA=$(date +%s)
docker compose exec -T core-service sh -c 'kill -TERM 1' || true
# Primero se espera a que Docker registre el reinicio (la JVM hace un apagado ordenado de unos
# segundos antes de terminar), y recien despues a que el contenedor nuevo vuelva a estar sano.
for _ in $(seq 1 30); do
  [ "$(docker inspect -f '{{.RestartCount}}' bancoxyz-core-service)" -gt "$REINICIOS_ANTES" ] && break
  sleep 1
done
for _ in $(seq 1 60); do
  [ "$(docker inspect -f '{{.State.Health.Status}}' bancoxyz-core-service 2>/dev/null)" = "healthy" ] && break
  sleep 2
done
echo "Eventos de Docker del contenedor durante la caida (die con exitCode 143 = SIGTERM, y start automatico):"
docker events --since "$INICIO_CAIDA" --until 0s --filter container=bancoxyz-core-service \
  --filter event=die --filter event=start --format '  {{.Time}} evento={{.Action}} exitCode={{index .Actor.Attributes "exitCode"}}' \
  2>/dev/null || true
echo "Reinicios de core-service despues: $(docker inspect -f '{{.RestartCount}}' bancoxyz-core-service)" \
     "| estado: $(docker inspect -f '{{.State.Status}} ({{.State.Health.Status}})' bancoxyz-core-service)"
echo
echo "=== Fin de la prueba de tolerancia a fallos ==="
