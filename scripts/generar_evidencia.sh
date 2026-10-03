#!/usr/bin/env bash
# Orquesta una corrida completa del ecosistema BancoXYZ (Spring Cloud + Kafka) en local y guarda
# toda la evidencia de ejecucion en evidencias/, con el mismo esquema de nombres que usa
# .github/workflows/evidencia-ejecucion.yml (evidencia01-build.log ... evidencia11-notificaciones-escalabilidad.log).
# Pensado para regenerar la evidencia sin depender de GitHub Actions, por ejemplo antes de tomar
# las capturas de pantalla que pide el enunciado.
#
# Funciona igual en Linux/macOS y en Windows (via Git Bash, que ya es un requisito de
# scripts/probar_apis.sh): levanta Kafka (docker compose) y los 9 procesos Java en orden
# (config-server, eureka-server, auth-server, core-service, los 3 BFF y 2 instancias de
# notificaciones-service), corre las pruebas OAuth 2.0, las end-to-end, las de transferencias
# (Saga+Kafka) y la de tolerancia a fallos, y al terminar detiene todo lo que este script levanto
# (incluso si algo falla a mitad de camino).
#
# Para la variante 100% contenerizada (Semana 8: todo en docker-compose.yaml) ver
# scripts/generar_evidencia_docker.sh.
#
# Requiere: JDK 21 (con jps), Maven, curl, jq, Docker (Desktop en Windows/macOS, o Docker Engine
# en Linux) corriendo, para el broker Kafka de la Semana 7. Puertos libres 8080-8085, 8761, 8888,
# 9000, 9092 y 18081-18083 (actuator de los BFF).
#
# Uso:
#   bash scripts/generar_evidencia.sh                       # compila y corre todo
#   bash scripts/generar_evidencia.sh --skip-build           # reusa los jars ya compilados
#   bash scripts/generar_evidencia.sh --skip-tolerancia-fallos  # no mata core-service al final
set -uo pipefail

cd "$(dirname "$0")/.."
source scripts/_common.sh

SKIP_BUILD=false
SKIP_TOLERANCIA=false
for arg in "$@"; do
  case "$arg" in
    --skip-build) SKIP_BUILD=true ;;
    --skip-tolerancia-fallos) SKIP_TOLERANCIA=true ;;
    *) echo "Argumento desconocido: $arg (usar --skip-build o --skip-tolerancia-fallos)" >&2; exit 1 ;;
  esac
done

mkdir -p evidencias
PIDS_LEVANTADOS=()
ULTIMO_PID=""

detener_todo() {
  echo
  echo "=== Deteniendo los procesos levantados por este script ==="
  for pid in "${PIDS_LEVANTADOS[@]:-}"; do
    detener_pid "$pid"
  done
  echo "=== Deteniendo Kafka (docker compose down) ==="
  docker compose down >/dev/null 2>&1 || true
}
trap detener_todo EXIT

levantar() {
  local nombre="$1" jar="$2" log="$3"
  echo "--- Levantando $nombre ---"
  nohup java -jar "$jar" > "evidencias/$log" 2>&1 &
  # En Windows (Git Bash/MSYS), "$!" NO es el PID real de java.exe: es un identificador interno
  # de MSYS para el wrapper del proceso nativo, y matarlo con taskkill no termina el java.exe
  # real (se detecto probando este mismo script: el proceso seguia vivo pese a un taskkill
  # "exitoso"). jps si reporta el PID real de la JVM en los tres entornos, asi que se usa ese
  # para todo lo que venga despues (verificacion y limpieza final).
  local pid=""
  for _ in $(seq 1 20); do
    pid=$(pid_de_jar "$jar")
    [ -n "$pid" ] && break
    sleep 0.5
  done
  if [ -z "$pid" ]; then
    echo "No se pudo determinar el PID de $nombre tras iniciarlo (revisa evidencias/$log)." >&2
    exit 1
  fi
  PIDS_LEVANTADOS+=("$pid")
  ULTIMO_PID="$pid"
  echo "$nombre PID $pid (log: evidencias/$log)"
}

# Variante para una SEGUNDA instancia del MISMO jar (notificaciones-service): recibe el/los PID
# de instancia(s) ya conocidas para poder distinguir, via pid_de_jar_excluyendo, cual PID nuevo
# corresponde a esta instancia recien lanzada. "env_extra" es una asignacion tipo VAR=valor que
# se aplica solo a este proceso (ej. SERVER_PORT=8085), sin afectar al resto del script.
levantar_instancia_adicional() {
  local nombre="$1" jar="$2" log="$3" env_extra="$4" pid_conocido="$5"
  echo "--- Levantando $nombre ---"
  env "$env_extra" nohup java -jar "$jar" > "evidencias/$log" 2>&1 &
  local pid=""
  for _ in $(seq 1 20); do
    pid=$(pid_de_jar_excluyendo "$jar" "$pid_conocido")
    [ -n "$pid" ] && break
    sleep 0.5
  done
  if [ -z "$pid" ]; then
    echo "No se pudo determinar el PID de $nombre tras iniciarlo (revisa evidencias/$log)." >&2
    exit 1
  fi
  PIDS_LEVANTADOS+=("$pid")
  ULTIMO_PID="$pid"
  echo "$nombre PID $pid (log: evidencias/$log)"
}

# Version de verificar_arriba que recibe el PID EXACTO a comprobar en vez de re-derivarlo por
# patron de jar: imprescindible cuando hay mas de un proceso corriendo el mismo jar (las 2
# instancias de notificaciones-service), donde pid_de_jar por si solo seria ambiguo.
verificar_arriba_pid() {
  local nombre="$1" pid="$2" url="$3" log="$4" intentos="${5:-40}" espera_minima="${6:-8}"
  local intento
  for ((intento = 1; intento <= intentos; intento++)); do
    if curl -sk -o /dev/null "$url" \
        && [ "$intento" -ge "$espera_minima" ] \
        && jps -l | awk '{print $1}' | grep -qx "$pid"; then
      return 0
    fi
    sleep 1
  done
  echo "$nombre no quedo arriba de forma estable en $url." >&2
  echo "--- ultimas lineas de evidencias/$log ---" >&2
  tail -n 20 "evidencias/$log" >&2
  exit 1
}

# No basta con que la URL responda: si el puerto ya estaba ocupado por OTRO proceso (ej. una
# app del sistema que tambien escucha ahi), curl igual recibe respuesta aunque el jar que nos
# interesa en realidad haya fallado al iniciar. Ademas, como los 4 servicios de negocio ahora
# dependen de config-server y del registro en Eureka, un fallo por puerto ocupado tarda varios
# segundos en manifestarse (Spring difiere el intento real de bind del puerto hasta despues de
# esas llamadas) - se midio ese fallo tardando ~5s en este mismo proyecto. Por eso no basta con
# revisar una vez: se exige que la URL responda Y que el proceso siga vivo (jps) despues de
# esperar como minimo "espera_minima" segundos desde que se lanzo, dandole tiempo a un fallo
# tardio para manifestarse antes de aceptar el resultado como valido.
verificar_arriba() {
  local nombre="$1" jar="$2" url="$3" log="$4" intentos="${5:-40}" espera_minima="${6:-8}"
  local intento
  for ((intento = 1; intento <= intentos; intento++)); do
    if curl -sk -o /dev/null "$url" \
        && [ "$intento" -ge "$espera_minima" ] \
        && [ -n "$(pid_de_jar "$jar")" ]; then
      return 0
    fi
    sleep 1
  done
  echo "$nombre no quedo arriba de forma estable en $url." >&2
  echo "Si el proceso ya no esta corriendo, es probable que otro proceso ya estuviera usando ese puerto." >&2
  echo "--- ultimas lineas de evidencias/$log ---" >&2
  tail -n 20 "evidencias/$log" >&2
  exit 1
}

if [ "$SKIP_BUILD" = false ]; then
  echo "=== Compilando los 8 modulos (Maven) ==="
  mvn -B -DskipTests package | tee evidencias/evidencia01-build.log
  if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    echo "La compilacion fallo, revisa evidencias/evidencia01-build.log" >&2
    exit 1
  fi
fi

echo "=== Levantando Kafka (docker compose) - Semana 7 ==="
if ! command -v docker >/dev/null 2>&1; then
  echo "No se encontro el comando 'docker'. Instala y abre Docker Desktop (Windows/macOS) o" >&2
  echo "Docker Engine (Linux); el broker Kafka de la Semana 7 se levanta con docker compose," >&2
  echo "ver docker-compose.yml y README.md seccion 12." >&2
  exit 1
fi
docker compose up -d kafka
esperar_kafka 30 || exit 1

levantar "config-server" config-server/target/config-server.jar evidencia01b-config-server.log
verificar_arriba "config-server" "config-server/target/config-server.jar" "http://localhost:8888/core-service/default" evidencia01b-config-server.log

levantar "eureka-server" eureka-server/target/eureka-server.jar evidencia01c-eureka-server.log
verificar_arriba "eureka-server" "eureka-server/target/eureka-server.jar" "http://localhost:8761/" evidencia01c-eureka-server.log

levantar "auth-server" auth-server/target/auth-server.jar evidencia01d-auth-server.log
verificar_arriba "auth-server" "auth-server/target/auth-server.jar" "http://localhost:9000/actuator/health" evidencia01d-auth-server.log

levantar "core-service" core-service/target/core-service.jar evidencia02-core-service.log
verificar_arriba "core-service" "core-service/target/core-service.jar" "http://localhost:8080/actuator/health" evidencia02-core-service.log

levantar "bff-web" bff-web/target/bff-web.jar evidencia03-bff-web.log
verificar_arriba "bff-web" "bff-web/target/bff-web.jar" "https://localhost:8081/api/web/auth/login" evidencia03-bff-web.log

levantar "bff-mobile" bff-mobile/target/bff-mobile.jar evidencia04-bff-mobile.log
verificar_arriba "bff-mobile" "bff-mobile/target/bff-mobile.jar" "https://localhost:8082/api/mobile/auth/login" evidencia04-bff-mobile.log

levantar "bff-atm" bff-atm/target/bff-atm.jar evidencia05-bff-atm.log
verificar_arriba "bff-atm" "bff-atm/target/bff-atm.jar" "https://localhost:8083/api/atm/sesion" evidencia05-bff-atm.log

echo "=== Levantando notificaciones-service (2 instancias, mismo consumer group) - Semana 7 ==="
levantar "notificaciones-service (instancia A, :8084)" notificaciones-service/target/notificaciones-service.jar evidencia09a-notificaciones-A.log
verificar_arriba "notificaciones-service-A" "notificaciones-service/target/notificaciones-service.jar" "http://localhost:8084/actuator/health" evidencia09a-notificaciones-A.log
PID_NOTIF_A="$ULTIMO_PID"

levantar_instancia_adicional "notificaciones-service (instancia B, :8085)" notificaciones-service/target/notificaciones-service.jar \
  evidencia09b-notificaciones-B.log "SERVER_PORT=8085" "$PID_NOTIF_A"
verificar_arriba_pid "notificaciones-service-B" "$ULTIMO_PID" "http://localhost:8085/actuator/health" evidencia09b-notificaciones-B.log

echo "=== Esperando a que los 4 servicios de negocio completen su registro en Eureka ==="
# Antes esto era un "sleep 8" fijo. Eso alcanzaba a veces, pero no siempre: el registro en
# Eureka (y la propagacion a la cache local de cada BFF, que es lo que usa @LoadBalanced
# RestTemplate para resolver "http://core-service") es asincrono y puede tardar mas que eso.
# Se observo en una corrida real de este mismo proyecto que 8s no alcanzaron: el login de
# bff-web fallo con "No servers available for service: core-service" y la foto de Eureka de
# evidencia07 solo llego a mostrar 2 de los 4 servicios. Ver el javadoc de
# esperar_registro_eureka en scripts/_common.sh para el detalle completo.
esperar_registro_eureka 60 "CORE-SERVICE" "BFF-WEB" "BFF-MOBILE" "BFF-ATM" "NOTIFICACIONES-SERVICE"

echo "=== Ejecutando pruebas OAuth 2.0 (scripts/probar_oauth2.sh, Semana 8) ==="
bash scripts/probar_oauth2.sh 2>&1 | tee evidencias/evidencia12-oauth2.log
if [ "${PIPESTATUS[0]}" -ne 0 ]; then
  echo "Las pruebas OAuth 2.0 fallaron, revisa evidencias/evidencia12-oauth2.log" >&2
  exit 1
fi

echo "=== Ejecutando pruebas end-to-end (scripts/probar_apis.sh) ==="
bash scripts/probar_apis.sh 2>&1 | tee evidencias/evidencia06-pruebas-apis.log
if [ "${PIPESTATUS[0]}" -ne 0 ]; then
  echo "Las pruebas end-to-end fallaron, revisa evidencias/evidencia06-pruebas-apis.log" >&2
  exit 1
fi

echo "=== Capturando evidencia de registro en Eureka ==="
curl -s -H "Accept: application/json" http://localhost:8761/eureka/apps | tee evidencias/evidencia07-eureka-apps.log
echo

echo "=== Ejecutando pruebas de transferencias (Saga + Kafka, Semana 7) ==="
bash scripts/probar_transferencias.sh 2>&1 | tee evidencias/evidencia10-pruebas-transferencias.log
if [ "${PIPESTATUS[0]}" -ne 0 ]; then
  echo "Las pruebas de transferencias fallaron, revisa evidencias/evidencia10-pruebas-transferencias.log" >&2
  exit 1
fi

echo "=== Verificando el reparto de particiones entre las 2 instancias de notificaciones-service ==="
{
  echo "--- Mensajes procesados por la instancia A (:8084) ---"
  grep "Notificacion procesada" evidencias/evidencia09a-notificaciones-A.log || echo "(ninguno)"
  echo
  echo "--- Mensajes procesados por la instancia B (:8085) ---"
  grep "Notificacion procesada" evidencias/evidencia09b-notificaciones-B.log || echo "(ninguno)"
} | tee evidencias/evidencia11-notificaciones-escalabilidad.log
CONTEO_A=$(grep -c "Notificacion procesada" evidencias/evidencia09a-notificaciones-A.log || true)
CONTEO_B=$(grep -c "Notificacion procesada" evidencias/evidencia09b-notificaciones-B.log || true)
{
  echo
  echo "Instancia A proceso ${CONTEO_A:-0} mensaje(s); instancia B proceso ${CONTEO_B:-0} mensaje(s)."
  if [ "${CONTEO_A:-0}" -eq 0 ] || [ "${CONTEO_B:-0}" -eq 0 ]; then
    echo "Advertencia: una de las 2 instancias no proceso ningun mensaje en esta corrida (el reparto de"
    echo "particiones entre pocos mensajes no siempre es perfectamente parejo). No se aborta el script por esto."
  fi
} | tee -a evidencias/evidencia11-notificaciones-escalabilidad.log

if [ "$SKIP_TOLERANCIA" = false ]; then
  echo "=== Ejecutando prueba de tolerancia a fallos (detiene core-service) ==="
  # "2>&1" antes del pipe: sin esto, un "exit 1" temprano del script (ej. no encontro el PID de
  # core-service) imprime su motivo por stderr, que se ve en la terminal pero NO queda guardado
  # en evidencia08-circuit-breaker.log (tee solo captura stdout) - exactamente lo que paso en una
  # corrida real de este proyecto, donde el log quedo con una sola linea sin ninguna pista del
  # porque.
  bash scripts/probar_tolerancia_fallos.sh 2>&1 | tee evidencias/evidencia08-circuit-breaker.log
  if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    echo "La prueba de tolerancia a fallos fallo, revisa evidencias/evidencia08-circuit-breaker.log" >&2
    echo "(no se aborta el script por esto: la evidencia de las secciones anteriores ya quedo guardada)" >&2
  fi
fi

echo
echo "=== Listo. Evidencia generada en evidencias/: ==="
ls -1 evidencias/*.log
