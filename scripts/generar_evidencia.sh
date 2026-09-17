#!/usr/bin/env bash
# Orquesta una corrida completa del ecosistema BancoXYZ (Spring Cloud) en local y guarda toda la
# evidencia de ejecucion en evidencias/, con el mismo esquema de nombres que usa
# .github/workflows/evidencia-ejecucion.yml (evidencia01-build.log ... evidencia08-circuit-breaker.log).
# Pensado para regenerar la evidencia sin depender de GitHub Actions, por ejemplo antes de tomar
# las capturas de pantalla que pide el enunciado.
#
# Funciona igual en Linux/macOS y en Windows (via Git Bash, que ya es un requisito de
# scripts/probar_apis.sh): compila, levanta los 6 servicios en orden, corre las pruebas
# end-to-end y la prueba de tolerancia a fallos, y al terminar detiene todo lo que este script
# levanto (incluso si algo falla a mitad de camino).
#
# Requiere: JDK 21 (con jps), Maven, curl, jq. Puertos libres 8080-8083, 8761, 8888.
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

detener_todo() {
  echo
  echo "=== Deteniendo los procesos levantados por este script ==="
  for pid in "${PIDS_LEVANTADOS[@]:-}"; do
    detener_pid "$pid"
  done
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
  echo "$nombre PID $pid (log: evidencias/$log)"
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
  echo "=== Compilando los 6 modulos (Maven) ==="
  mvn -B -DskipTests package | tee evidencias/evidencia01-build.log
  if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    echo "La compilacion fallo, revisa evidencias/evidencia01-build.log" >&2
    exit 1
  fi
fi

levantar "config-server" config-server/target/config-server.jar evidencia01b-config-server.log
verificar_arriba "config-server" "config-server/target/config-server.jar" "http://localhost:8888/core-service/default" evidencia01b-config-server.log

levantar "eureka-server" eureka-server/target/eureka-server.jar evidencia01c-eureka-server.log
verificar_arriba "eureka-server" "eureka-server/target/eureka-server.jar" "http://localhost:8761/" evidencia01c-eureka-server.log

levantar "core-service" core-service/target/core-service.jar evidencia02-core-service.log
verificar_arriba "core-service" "core-service/target/core-service.jar" "http://localhost:8080/internal/cuentas" evidencia02-core-service.log

levantar "bff-web" bff-web/target/bff-web.jar evidencia03-bff-web.log
verificar_arriba "bff-web" "bff-web/target/bff-web.jar" "https://localhost:8081/api/web/auth/login" evidencia03-bff-web.log

levantar "bff-mobile" bff-mobile/target/bff-mobile.jar evidencia04-bff-mobile.log
verificar_arriba "bff-mobile" "bff-mobile/target/bff-mobile.jar" "https://localhost:8082/api/mobile/auth/login" evidencia04-bff-mobile.log

levantar "bff-atm" bff-atm/target/bff-atm.jar evidencia05-bff-atm.log
verificar_arriba "bff-atm" "bff-atm/target/bff-atm.jar" "https://localhost:8083/api/atm/sesion" evidencia05-bff-atm.log

echo "=== Esperando a que los 4 servicios de negocio completen su registro en Eureka ==="
# Antes esto era un "sleep 8" fijo. Eso alcanzaba a veces, pero no siempre: el registro en
# Eureka (y la propagacion a la cache local de cada BFF, que es lo que usa @LoadBalanced
# RestTemplate para resolver "http://core-service") es asincrono y puede tardar mas que eso.
# Se observo en una corrida real de este mismo proyecto que 8s no alcanzaron: el login de
# bff-web fallo con "No servers available for service: core-service" y la foto de Eureka de
# evidencia07 solo llego a mostrar 2 de los 4 servicios. Ver el javadoc de
# esperar_registro_eureka en scripts/_common.sh para el detalle completo.
esperar_registro_eureka 60 "CORE-SERVICE" "BFF-WEB" "BFF-MOBILE" "BFF-ATM"

echo "=== Ejecutando pruebas end-to-end (scripts/probar_apis.sh) ==="
bash scripts/probar_apis.sh 2>&1 | tee evidencias/evidencia06-pruebas-apis.log
if [ "${PIPESTATUS[0]}" -ne 0 ]; then
  echo "Las pruebas end-to-end fallaron, revisa evidencias/evidencia06-pruebas-apis.log" >&2
  exit 1
fi

echo "=== Capturando evidencia de registro en Eureka ==="
curl -s -H "Accept: application/json" http://localhost:8761/eureka/apps | tee evidencias/evidencia07-eureka-apps.log
echo

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
