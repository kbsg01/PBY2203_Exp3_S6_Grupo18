#!/usr/bin/env bash
# Evidencia de ejecucion de la Semana 8: TODO el ecosistema corriendo en contenedores Docker,
# orquestado por docker-compose.yaml (a diferencia de scripts/generar_evidencia.sh, donde los
# microservicios corren como procesos "java -jar" en el host y solo Kafka va en Docker).
#
# Pasos:
#   1. Compila los 8 jars con Maven (las imagenes se construyen a partir de ellos).
#   2. Construye las 8 imagenes (docker compose build) y lista su tamano.
#   3. Levanta los 10 contenedores (kafka + 8 servicios, notificaciones x2) con
#      "docker compose up -d --wait": respeta depends_on/service_healthy y espera a que TODOS
#      esten sanos segun su HEALTHCHECK.
#   4. Corre, contra los contenedores, las mismas pruebas de las semanas anteriores mas la de
#      OAuth 2.0: probar_oauth2.sh, probar_apis.sh, probar_transferencias.sh.
#   5. Verifica el reparto de mensajes Kafka entre las 2 replicas de notificaciones-service.
#   6. Corre la prueba de tolerancia a fallos en modo --docker (caida, circuito abierto,
#      recuperacion automatica y restart policy).
#   7. Guarda los logs de cada contenedor y baja todo (docker compose down), incluso si algo
#      falla a mitad de camino.
#
# Toda la evidencia queda en evidencias/docker/.
#
# Requiere: JDK 21 + Maven, Docker (Desktop en Windows/macOS o Engine en Linux) con el plugin
# "docker compose" v2, curl y jq. Puertos libres: 8080-8083, 8761, 8888, 9000, 9092.
#
# Uso:
#   bash scripts/generar_evidencia_docker.sh               # compila, construye y prueba todo
#   bash scripts/generar_evidencia_docker.sh --skip-build  # reusa los jars ya compilados
#   bash scripts/generar_evidencia_docker.sh --keep-up     # no baja los contenedores al final
set -uo pipefail

cd "$(dirname "$0")/.."
source scripts/_common.sh

SKIP_BUILD=false
KEEP_UP=false
for arg in "$@"; do
  case "$arg" in
    --skip-build) SKIP_BUILD=true ;;
    --keep-up) KEEP_UP=true ;;
    *) echo "Argumento desconocido: $arg (usar --skip-build o --keep-up)" >&2; exit 1 ;;
  esac
done

EV=evidencias/docker
mkdir -p "$EV"
SERVICIOS=(kafka config-server eureka-server auth-server core-service bff-web bff-mobile bff-atm notificaciones-service)

finalizar() {
  echo
  echo "=== Guardando los logs de cada contenedor en $EV/ ==="
  local s
  for s in "${SERVICIOS[@]}"; do
    docker compose logs --no-color "$s" > "$EV/docker10-logs-$s.log" 2>&1 || true
  done
  if [ "$KEEP_UP" = false ]; then
    echo "=== Deteniendo el ecosistema (docker compose down) ==="
    docker compose down --remove-orphans >/dev/null 2>&1 || true
  else
    echo "=== --keep-up: los contenedores siguen corriendo (detener con: docker compose down) ==="
  fi
}
trap finalizar EXIT

if ! docker compose version >/dev/null 2>&1; then
  echo "No se encontro 'docker compose' (v2). Instala/abre Docker Desktop o Docker Engine." >&2
  exit 1
fi

{
  if [ "$SKIP_BUILD" = false ]; then
    echo "=== 1. Compilando los 8 modulos (mvn -DskipTests package) ==="
    mvn -B -DskipTests package || { echo "La compilacion fallo" >&2; exit 1; }
  fi
  echo
  echo "=== 2. Construyendo las imagenes Docker (docker compose build) ==="
  docker compose build || exit 1
} 2>&1 | tee "$EV/docker01-build.log"
[ "${PIPESTATUS[0]}" -eq 0 ] || { echo "Fallo la compilacion o la construccion de imagenes, revisa $EV/docker01-build.log" >&2; exit 1; }

{
  echo "=== Imagenes construidas (una por microservicio) ==="
  docker image ls --format 'table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}' | grep -E 'REPOSITORY|bancoxyz/'
  echo
  echo "=== Usuario con el que corre cada imagen (no root) ==="
  for img in $(docker image ls --format '{{.Repository}}:{{.Tag}}' | grep '^bancoxyz/' | sort); do
    echo "$img -> USER $(docker image inspect -f '{{.Config.User}}' "$img") | HEALTHCHECK: $(docker image inspect -f '{{join .Config.Healthcheck.Test " "}}' "$img")"
  done
} 2>&1 | tee "$EV/docker02-imagenes.log"

{
  echo "=== 3. Levantando el ecosistema completo (docker compose up -d --wait) ==="
  INICIO=$(date +%s)
  docker compose up -d --wait --wait-timeout 420
  CODIGO=$?
  echo "docker compose up termino con codigo $CODIGO en $(( $(date +%s) - INICIO ))s"
  echo
  docker compose ps --format 'table {{.Name}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
  echo
  echo "=== Red interna ==="
  docker network inspect bancoxyz-net -f '{{range .Containers}}{{.Name}} {{.IPv4Address}}{{println}}{{end}}' | sort
  exit $CODIGO
} 2>&1 | tee "$EV/docker03-compose-up.log"
[ "${PIPESTATUS[0]}" -eq 0 ] || { echo "No todos los contenedores quedaron sanos, revisa $EV/docker03-compose-up.log" >&2; exit 1; }

echo "=== Esperando el registro de los servicios en Eureka ==="
esperar_registro_eureka 60 "CORE-SERVICE" "BFF-WEB" "BFF-MOBILE" "BFF-ATM" "NOTIFICACIONES-SERVICE"
# Margen para que la cache local de Eureka de cada BFF (refresco cada 30s) ya incluya core-service.
sleep 20
curl -s -H "Accept: application/json" http://localhost:8761/eureka/apps \
  | jq -r '.applications.application[] | "\(.name): \([.instance[] | "\(.instanceId) [\(.ipAddr)] \(.status)"] | join(", "))"' \
  | tee "$EV/docker04-eureka-apps.log"

echo "=== 4. Pruebas OAuth 2.0 ==="
bash scripts/probar_oauth2.sh 2>&1 | tee "$EV/docker05-oauth2.log"
[ "${PIPESTATUS[0]}" -eq 0 ] || { echo "Fallaron las pruebas OAuth 2.0" >&2; exit 1; }

echo "=== 4.1 Pruebas end-to-end de los 3 canales ==="
bash scripts/probar_apis.sh 2>&1 | tee "$EV/docker06-pruebas-apis.log"
[ "${PIPESTATUS[0]}" -eq 0 ] || { echo "Fallaron las pruebas end-to-end" >&2; exit 1; }

echo "=== 4.2 Pruebas de transferencias (Saga + Kafka) ==="
bash scripts/probar_transferencias.sh 2>&1 | tee "$EV/docker07-pruebas-transferencias.log"
[ "${PIPESTATUS[0]}" -eq 0 ] || { echo "Fallaron las pruebas de transferencias" >&2; exit 1; }

echo "=== 5. Reparto de mensajes Kafka entre las replicas de notificaciones-service ==="
{
  docker compose logs --no-color notificaciones-service 2>/dev/null | grep "Notificacion procesada" || echo "(ninguno)"
  echo
  for c in $(docker compose ps -q notificaciones-service); do
    nombre=$(docker inspect -f '{{.Name}}' "$c" | sed 's#^/##')
    echo "$nombre proceso $(docker logs "$c" 2>&1 | grep -c 'Notificacion procesada') mensaje(s)" \
         "| particiones asignadas: $(docker logs "$c" 2>&1 | grep -o 'partitions assigned: \[[^]]*\]' | tail -n1)"
  done
} | tee "$EV/docker08-notificaciones-escalabilidad.log"

echo "=== Tokens emitidos por auth-server durante las pruebas (auditoria) ==="
docker compose logs --no-color auth-server 2>/dev/null | grep "Access token emitido" | tee "$EV/docker11-auth-server-tokens.log"

echo "=== 6. Tolerancia a fallos en Docker (circuit breaker, recuperacion y restart policy) ==="
bash scripts/probar_tolerancia_fallos.sh --docker 2>&1 | tee "$EV/docker09-tolerancia-fallos.log"
[ "${PIPESTATUS[0]}" -eq 0 ] || echo "La prueba de tolerancia a fallos fallo (la evidencia anterior ya quedo guardada)" >&2

echo
echo "=== Listo. Evidencia generada en $EV/: ==="
ls -1 "$EV"
