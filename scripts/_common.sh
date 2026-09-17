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
