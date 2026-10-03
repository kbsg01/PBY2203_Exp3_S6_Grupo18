#!/usr/bin/env bash
# Ejercita, con curl, los cuatro servicios del proyecto (core-service + los tres BFF) usando
# datos reales del dataset oficial (bank_legacy_data, semana_3, cuenta_id=101 y cuenta_id=105
# tras la validacion/upsert aplicada por CargaDatosService: ver README.md, tabla de
# "Credenciales de demostracion"). Se usa como evidencia de ejecucion en
# .github/workflows/evidencia-ejecucion.yml y tambien sirve para probar el proyecto en un
# entorno local.
#
# Requiere: curl, jq. Se asume que los 4 servicios ya estan arriba en los puertos por defecto
# (core-service:8080, bff-web:8081, bff-mobile:8082, bff-atm:8083).
#
# Los tres BFF (web/movil/atm) exponen HTTPS con un certificado autofirmado de uso academico
# (ver server.ssl en cada application.yml); por eso las llamadas a esos tres usan -k (curl
# ignora la validacion de la cadena de confianza, como se haria con un cliente que aun no
# confia en la CA interna del banco). core-service NO se expone a ningun frontend (solo lo
# consumen los BFF con un access token OAuth 2.0 desde la Semana 8), por lo que se mantiene en
# HTTP dentro de la red interna, una decision documentada en el README (seccion "Seguridad de
# transporte"). El detalle del flujo OAuth 2.0 se prueba aparte en scripts/probar_oauth2.sh.
set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/_common.sh

CORE=http://localhost:8080
WEB=https://localhost:8081
MOBILE=https://localhost:8082
ATM=https://localhost:8083

separador() { echo; echo "=== $1 ==="; }

# Corta la ejecucion con un mensaje claro si un login/apertura de sesion no devolvio un token
# valido, en vez de seguir silenciosamente con "Bearer null" o un X-Atm-Session vacio. Sin esto,
# un fallo aguas arriba (ej. bff-web todavia sin terminar de registrarse en Eureka, con lo que su
# @LoadBalanced RestTemplate no encuentra "core-service" y el login responde sin token) se
# manifestaba varios pasos despues como codigos HTTP inesperados (401 en vez de 403) dificiles de
# relacionar con la causa real - se observo exactamente este caso en una corrida real de este
# proyecto, con el log mostrando "Token web obtenido: null...".
verificar_token() {
  local nombre="$1" valor="$2"
  if [ -z "$valor" ] || [ "$valor" = "null" ]; then
    echo "ERROR: no se obtuvo un $nombre valido. Verifique que el servicio y sus dependencias" >&2
    echo "(config-server, eureka-server, core-service) ya esten completamente arriba - en" >&2
    echo "particular, que el registro en Eureka ya se haya propagado (ver esperar_registro_eureka" >&2
    echo "en scripts/_common.sh)." >&2
    exit 1
  fi
}

separador "0. core-service NO debe responder sin un access token OAuth 2.0 (principio central del BFF)"
curl -s -o /dev/null -w "GET /internal/cuentas SIN token -> HTTP %{http_code} (se espera 401)\n" "$CORE/internal/cuentas"

separador "0.1 core-service SI responde con un access token valido emitido por auth-server (scope core.read)"
TOKEN_CORE=$(token_evidencia)
verificar_token "access token de auth-server" "$TOKEN_CORE"
curl -s -H "Authorization: Bearer $TOKEN_CORE" "$CORE/internal/cuentas/101" | jq .

separador "1. BFF WEB: login (cuenta 101, titular 'John Doe') y consulta completa de la cuenta"
TOKEN_WEB=$(curl -s -k -X POST "$WEB/api/web/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"cuentaId":101,"nombre":"John Doe"}' | jq -r .token)
verificar_token "token web" "$TOKEN_WEB"
echo "Token web obtenido: ${TOKEN_WEB:0:24}..."

curl -s -k -H "Authorization: Bearer $TOKEN_WEB" "$WEB/api/web/cuentas/101" | jq .

separador "1.1 BFF WEB: historial de movimientos filtrado por tipo=deposito (interfaz compleja)"
curl -s -k -H "Authorization: Bearer $TOKEN_WEB" "$WEB/api/web/cuentas/101/movimientos?tipo=deposito" | jq .

separador "1.2 BFF WEB: un token valido NO puede consultar la cuenta de otra persona (autorizacion)"
curl -s -k -o /dev/null -w "GET /api/web/cuentas/105 con token de la cuenta 101 -> HTTP %{http_code} (se espera 403)\n" \
  -H "Authorization: Bearer $TOKEN_WEB" "$WEB/api/web/cuentas/105"

separador "2. BFF MOVIL: login (cuenta 101, PIN determinista) y resumen liviano"
TOKEN_MOBILE=$(curl -s -k -X POST "$MOBILE/api/mobile/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"cuentaId":101,"pin":"7373"}' | jq -r .token)
verificar_token "token movil" "$TOKEN_MOBILE"
echo "Token movil obtenido: ${TOKEN_MOBILE:0:24}..."

curl -s -k -H "Authorization: Bearer $TOKEN_MOBILE" "$MOBILE/api/mobile/cuentas/101/resumen" | jq .
echo "(Comparar el tamano de esta respuesta con la de BFF WEB del paso 1: no trae titular, edad ni historial completo)"

separador "3. BFF CAJERO: apertura de sesion con tarjeta+PIN (cuenta 105, 'Steve Rogers')"
SESION_JSON=$(curl -s -k -X POST "$ATM/api/atm/sesion" \
  -H "Content-Type: application/json" \
  -d '{"numeroTarjeta":"4915000000000105","pin":"7665"}')
echo "$SESION_JSON" | jq .
TOKEN_ATM=$(echo "$SESION_JSON" | jq -r .sessionToken)
verificar_token "token de sesion ATM" "$TOKEN_ATM"

separador "3.1 BFF CAJERO: consulta de saldo (respuesta minima, sin nombre ni historial)"
curl -s -k -H "X-Atm-Session: $TOKEN_ATM" "$ATM/api/atm/cuentas/105/saldo" | jq .

separador "3.2 BFF CAJERO: retiro de \$1.000 (operacion critica)"
curl -s -k -X POST "$ATM/api/atm/cuentas/105/retiro" \
  -H "Content-Type: application/json" \
  -H "X-Atm-Session: $TOKEN_ATM" \
  -d '{"monto":1000}' | jq .

separador "3.3 BFF CAJERO: la sesion se invalida tras el retiro (debe fallar con HTTP 401)"
curl -s -k -o /dev/null -w "GET /api/atm/cuentas/105/saldo reusando la sesion ya usada -> HTTP %{http_code} (se espera 401)\n" \
  -H "X-Atm-Session: $TOKEN_ATM" "$ATM/api/atm/cuentas/105/saldo"

separador "3.4 BFF CAJERO: un retiro que excede el limite maximo por operacion debe rechazarse"
SESION_JSON_2=$(curl -s -k -X POST "$ATM/api/atm/sesion" \
  -H "Content-Type: application/json" \
  -d '{"numeroTarjeta":"4915000000000105","pin":"7665"}')
TOKEN_ATM_2=$(echo "$SESION_JSON_2" | jq -r .sessionToken)
verificar_token "token de sesion ATM (segundo intento)" "$TOKEN_ATM_2"
curl -s -k -X POST "$ATM/api/atm/cuentas/105/retiro" \
  -H "Content-Type: application/json" \
  -H "X-Atm-Session: $TOKEN_ATM_2" \
  -d '{"monto":999999}' | jq .

echo
echo "=== Fin de las pruebas ==="
