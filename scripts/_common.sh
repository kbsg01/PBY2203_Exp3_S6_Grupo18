#!/usr/bin/env bash
# Funciones compartidas por los scripts de evidencia/pruebas de este proyecto. No se ejecuta
# directamente: se importa con "source scripts/_common.sh".

es_windows() {
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) return 0 ;;
    *) return 1 ;;
  esac
}

# Detiene un proceso por PID de forma confiable tanto en Linux/macOS como en Windows (Git Bash).
# En Git Bash, "kill" sobre un proceso nativo (java.exe, no un binario MSYS) a veces no reporta
# error pero tampoco termina el proceso realmente; "taskkill //F" si lo hace de forma consistente.
detener_pid() {
  local pid="$1"
  [ -z "$pid" ] && return 0
  if es_windows; then
    taskkill //PID "$pid" //F >/dev/null 2>&1 || true
  else
    kill "$pid" >/dev/null 2>&1 || true
  fi
}

# Encuentra el PID de un proceso Java lanzado con "java -jar <patron>...jar", usando jps (viene
# con el JDK, por lo que funciona igual en Linux, macOS y Windows sin depender de pgrep/ps -
# pgrep en particular no existe en Git Bash).
pid_de_jar() {
  local patron="$1"
  jps -l | grep "$patron" | awk '{print $1}' | head -n1
}

# Igual que pid_de_jar, pero descarta los PID ya conocidos (pasados como argumentos adicionales).
# Necesaria para localizar la instancia RECIEN lanzada cuando hay mas de un proceso corriendo con
# el MISMO jar (las 2 instancias de notificaciones-service, distinguidas solo por la variable de
# entorno SERVER_PORT, que "jps -l" no reporta): sin esto, pid_de_jar devolveria siempre la
# primera instancia que aparezca en la lista, sin importar cual se acaba de lanzar.
pid_de_jar_excluyendo() {
  local patron="$1"
  shift
  local excluidos=" $* "
  local pid
  for pid in $(jps -l | grep "$patron" | awk '{print $1}'); do
    if [[ "$excluidos" != *" $pid "* ]]; then
      echo "$pid"
      return 0
    fi
  done
  return 1
}

# Espera activamente a que los servicios de negocio indicados (nombres tal como los reporta
# Eureka, ej. "CORE-SERVICE") aparezcan registrados en http://localhost:8761/eureka/apps.
#
# Por que existe esta funcion: un chequeo de "¿responde el puerto HTTP?" (como el que ya hace
# verificar_arriba en generar_evidencia.sh) NO alcanza para saber si un servicio ya completo su
# registro en Eureka. Son dos cosas distintas: Tomcat puede estar arriba y respondiendo peticiones
# HTTP normales varios segundos antes de que el DiscoveryClient interno termine su primer ciclo de
# registro+heartbeat contra eureka-server. Si las pruebas empiezan antes de eso, dos problemas
# concretos aparecen (ambos se observaron en una corrida real de este mismo proyecto):
#   1. La foto de "http://localhost:8761/eureka/apps" que se guarda como evidencia puede mostrar
#      menos servicios de los que en realidad terminan registrandose segundos despues.
#   2. Un BFF que use @LoadBalanced RestTemplate para llamar a otro servicio por su nombre logico
#      (ej. bff-web -> "http://core-service") puede fallar con "No servers available for service:
#      core-service" si su propia cache local de Eureka todavia no incluye esa entrada - un fallo
#      transitorio de arranque, no un bug del codigo de negocio, pero que igual rompe la primera
#      llamada real (tipicamente el login) si no se le da tiempo a estabilizarse.
#
# Por eso esta espera es activa (reintenta consultando /eureka/apps) en vez de un "sleep" fijo:
# un sleep fijo tendria que sobreestimar el peor caso para ser confiable, mientras que esperar
# activamente avanza tan pronto como Eureka realmente confirma el registro, y solo se demora mas
# si hace falta.
esperar_registro_eureka() {
  local intentos="${1:-60}"
  shift || true
  local esperados=("$@")
  if [ "${#esperados[@]}" -eq 0 ]; then
    esperados=("CORE-SERVICE" "BFF-WEB" "BFF-MOBILE" "BFF-ATM")
  fi

  echo "Esperando el registro en Eureka de: ${esperados[*]} ..."
  local intento
  for ((intento = 1; intento <= intentos; intento++)); do
    local respuesta
    respuesta=$(curl -s -H "Accept: application/json" http://localhost:8761/eureka/apps 2>/dev/null || true)
    local faltantes=()
    local nombre
    for nombre in "${esperados[@]}"; do
      if ! grep -q "\"name\":\"$nombre\"" <<< "$respuesta"; then
        faltantes+=("$nombre")
      fi
    done
    if [ "${#faltantes[@]}" -eq 0 ]; then
      echo "Los ${#esperados[@]} servicios esperados ya figuran registrados en Eureka (intento $intento/$intentos)."
      return 0
    fi
    sleep 2
  done

  echo "Tras $intentos intentos (~$((intentos * 2))s), siguen sin aparecer en Eureka: ${faltantes[*]}." >&2
  echo "Se continua de todas formas, pero la evidencia para esos servicios puede salir incompleta." >&2
  return 1
}

# Espera a que el broker Kafka (levantado con "docker compose up -d kafka") acepte conexiones en
# localhost:9092, antes de levantar core-service/bff-web/notificaciones-service (que fallan al
# conectar si el broker todavia no esta listo). Usa /dev/tcp de bash (disponible en Linux, macOS
# y en Git Bash de Windows) en vez de un cliente Kafka, para no depender de tener kafka-topics.sh
# ni el propio Docker CLI dentro del PATH mas alla de "docker compose".
esperar_kafka() {
  local intentos="${1:-30}"
  echo "Esperando a que Kafka (localhost:9092) acepte conexiones..."
  local intento
  for ((intento = 1; intento <= intentos; intento++)); do
    if (exec 3<>/dev/tcp/localhost/9092) 2>/dev/null; then
      exec 3<&- 3>&- 2>/dev/null || true
      echo "Kafka esta aceptando conexiones (intento $intento/$intentos)."
      return 0
    fi
    sleep 2
  done
  echo "Kafka no respondio en localhost:9092 tras $intentos intentos (~$((intentos * 2))s)." >&2
  echo "¿Esta Docker Desktop corriendo? Probar: docker compose up -d kafka" >&2
  return 1
}

# Espera activamente a que una transferencia (identificada por su transferenciaId) deje de estar
# EN_PROCESO, consultando GET /api/web/transferencias/{id}. Necesaria por la misma razon de fondo
# que esperar_registro_eureka: el consumo de los eventos de la saga (core-service) es asincrono
# respecto de la respuesta HTTP 202 que ya devolvio bff-web, asi que el estado final puede tardar
# unos milisegundos-segundos en quedar disponible, y una prueba automatizada no puede asumir que
# ya esta listo apenas el POST retorna.
#
# Se imprime el JSON completo del estado final al terminar (o el ultimo visto, si se agotan los
# intentos), para que quede como evidencia legible en el log aunque la prueba haya fallado.
esperar_estado_transferencia() {
  local token="$1" transferencia_id="$2" intentos="${3:-15}"
  local intento respuesta estado
  for ((intento = 1; intento <= intentos; intento++)); do
    respuesta=$(curl -s -k -H "Authorization: Bearer $token" "https://localhost:8081/api/web/transferencias/$transferencia_id")
    estado=$(echo "$respuesta" | jq -r .estado 2>/dev/null || true)
    if [ "$estado" != "EN_PROCESO" ] && [ -n "$estado" ] && [ "$estado" != "null" ]; then
      echo "$respuesta"
      return 0
    fi
    sleep 1
  done
  echo "$respuesta"
  echo "La transferencia $transferencia_id sigue EN_PROCESO tras $intentos intentos (~${intentos}s)." >&2
  return 1
}

# ============================================================================================
# OAuth 2.0 (Semana 8)
# ============================================================================================
# URL de auth-server vista desde el HOST: igual en modo "java -jar" y en docker-compose (que lo
# publica en 127.0.0.1:9000). El claim "iss" de los tokens NO depende de esta URL (es fijo en
# auth-server/application.yml), por eso un token pedido aqui es valido tambien para un
# core-service que corre dentro de Docker.
AUTH_URL="${AUTH_URL:-http://localhost:9000}"

# Pide un access token con el flujo client_credentials (RFC 6749 seccion 4.4) y lo imprime
# (o "null" si auth-server lo rechaza). El secreto viaja por HTTP Basic, como exige
# client_secret_basic.
obtener_token_cliente() {
  local cliente="$1" secreto="$2" scope="$3"
  curl -s -u "$cliente:$secreto" \
    -d grant_type=client_credentials \
    --data-urlencode "scope=$scope" \
    "$AUTH_URL/oauth2/token" | jq -r .access_token
}

# Token de solo lectura para los scripts de pruebas/evidencia (cliente "evidencia-cli",
# registrado en auth-server con scope core.read y nada mas).
token_evidencia() {
  obtener_token_cliente evidencia-cli "${EVIDENCIA_CLI_SECRET:-secreto-evidencia-cli-banco-xyz-2026}" core.read
}

# Decodifica (SIN verificar firma, solo para mostrarlo en la evidencia) el payload de un JWT.
# Base64url -> base64 estandar + relleno "=" faltante.
decodificar_jwt() {
  local payload
  payload=$(cut -d. -f2 <<< "$1" | tr '_-' '/+')
  case $(( ${#payload} % 4 )) in
    2) payload="${payload}==" ;;
    3) payload="${payload}=" ;;
  esac
  base64 -d <<< "$payload" 2>/dev/null | jq .
}
