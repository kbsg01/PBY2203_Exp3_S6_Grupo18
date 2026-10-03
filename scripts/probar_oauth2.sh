#!/usr/bin/env bash
# Evidencia del flujo OAuth 2.0 de la Semana 8 (auth-server + core-service como Resource Server).
# Funciona igual con los servicios levantados con "java -jar" (scripts/generar_evidencia.sh) o
# con docker-compose (scripts/generar_evidencia_docker.sh): en ambos casos auth-server responde
# en localhost:9000 y core-service en localhost:8080 desde el host.
#
# Demuestra, con llamadas HTTP reales:
#   1. Metadatos publicos del servidor de autorizacion (RFC 8414) y su JWKS.
#   2. Emision de un access token (client_credentials) y su contenido (claims).
#   3. core-service rechaza (401) una peticion sin token y una con firma adulterada.
#   4. core-service acepta (200) un token valido con el scope correcto.
#   5. Menor privilegio: un token valido SIN el scope requerido recibe 403 (insufficient_scope).
#   6. auth-server se niega a emitir un scope no autorizado para el cliente (invalid_scope) y
#      rechaza un secreto incorrecto (invalid_client).
#   7. Los 3 BFF obtuvieron sus propios tokens para llamar a core-service (se ve en el log de
#      auth-server; aqui se verifica indirectamente con una llamada exitosa por cada canal en
#      scripts/probar_apis.sh).
#
# Requiere: curl, jq.
set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/_common.sh

CORE=http://localhost:8080
SECRETO_MOBILE="${BFF_MOBILE_CLIENT_SECRET:-secreto-bff-mobile-banco-xyz-2026}"
SECRETO_WEB="${BFF_WEB_CLIENT_SECRET:-secreto-bff-web-banco-xyz-2026}"
SECRETO_ATM="${BFF_ATM_CLIENT_SECRET:-secreto-bff-atm-banco-xyz-2026}"

separador() { echo; echo "=== $1 ==="; }
esperado() {
  local descripcion="$1" obtenido="$2" esperado="$3"
  if [ "$obtenido" = "$esperado" ]; then
    echo "OK   $descripcion -> HTTP $obtenido (se espera $esperado)"
  else
    echo "FALLA $descripcion -> HTTP $obtenido (se esperaba $esperado)" >&2
    FALLAS=$((FALLAS + 1))
  fi
}
FALLAS=0

separador "1. Metadatos del servidor de autorizacion (RFC 8414): $AUTH_URL/.well-known/oauth-authorization-server"
curl -s "$AUTH_URL/.well-known/oauth-authorization-server" \
  | jq '{issuer, token_endpoint, jwks_uri, grant_types_supported, token_endpoint_auth_methods_supported}'

separador "1.1 Llave publica para verificar firmas (JWKS) - es lo unico que core-service necesita de auth-server"
curl -s "$AUTH_URL/oauth2/jwks" | jq '{keys: [.keys[] | {kty, kid, alg: (.alg // "RS256"), n: (.n[0:24] + "...")}]}'

separador "2. Emision de access token: cliente evidencia-cli, grant client_credentials, scope core.read"
RESPUESTA_TOKEN=$(curl -s -u "evidencia-cli:${EVIDENCIA_CLI_SECRET:-secreto-evidencia-cli-banco-xyz-2026}" \
  -d grant_type=client_credentials -d scope=core.read "$AUTH_URL/oauth2/token")
echo "$RESPUESTA_TOKEN" | jq '{token_type, scope, expires_in, access_token: (.access_token[0:32] + "...")}'
TOKEN_LECTURA=$(echo "$RESPUESTA_TOKEN" | jq -r .access_token)
if [ -z "$TOKEN_LECTURA" ] || [ "$TOKEN_LECTURA" = "null" ]; then
  echo "ERROR: auth-server no emitio un token (¿esta arriba en $AUTH_URL?)." >&2
  exit 1
fi
echo "Claims del token (payload decodificado, sin la firma):"
decodificar_jwt "$TOKEN_LECTURA"

separador "3. core-service SIN token -> 401 (ya no existe ninguna clave compartida que adivinar)"
CODIGO=$(curl -s -o /dev/null -w "%{http_code}" "$CORE/internal/cuentas/101")
esperado "GET /internal/cuentas/101 sin Authorization" "$CODIGO" 401

separador "3.1 core-service con un token ADULTERADO (firma invalida) -> 401"
TOKEN_ADULTERADO="${TOKEN_LECTURA%?}x"
curl -s -D - -o /dev/null -H "Authorization: Bearer $TOKEN_ADULTERADO" "$CORE/internal/cuentas/101" \
  | grep -i '^www-authenticate' || true
CODIGO=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $TOKEN_ADULTERADO" "$CORE/internal/cuentas/101")
esperado "GET /internal/cuentas/101 con firma alterada" "$CODIGO" 401

separador "4. core-service con token valido y scope core.read -> 200"
curl -s -H "Authorization: Bearer $TOKEN_LECTURA" "$CORE/internal/cuentas/101" \
  | jq '{cuentaId, titular, saldo, movimientos: (.movimientos | length)}'
CODIGO=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $TOKEN_LECTURA" "$CORE/internal/cuentas/101")
esperado "GET /internal/cuentas/101 con scope core.read" "$CODIGO" 200

separador "5. Menor privilegio: token VALIDO de bff-mobile (solo core.read) intentando un debito (core.write) -> 403"
TOKEN_MOBILE=$(obtener_token_cliente bff-mobile "$SECRETO_MOBILE" core.read)
curl -s -D - -o /dev/null -X POST -H "Authorization: Bearer $TOKEN_MOBILE" -H "Content-Type: application/json" \
  -d '{"monto":1}' "$CORE/internal/cuentas/101/debito" | grep -i '^www-authenticate' || true
CODIGO=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "Authorization: Bearer $TOKEN_MOBILE" \
  -H "Content-Type: application/json" -d '{"monto":1}' "$CORE/internal/cuentas/101/debito")
esperado "POST /internal/cuentas/101/debito con token de bff-mobile" "$CODIGO" 403

separador "5.1 bff-atm SI tiene core.write (es el unico canal que debita: retiro de efectivo)"
TOKEN_ATM=$(obtener_token_cliente bff-atm "$SECRETO_ATM" "core.read core.write")
decodificar_jwt "$TOKEN_ATM" | jq '{sub, scope}'

separador "6. auth-server se niega a emitir core.write a bff-web (scope no registrado para ese cliente)"
curl -s -u "bff-web:$SECRETO_WEB" -d grant_type=client_credentials -d scope=core.write "$AUTH_URL/oauth2/token" | jq .
CODIGO=$(curl -s -o /dev/null -w "%{http_code}" -u "bff-web:$SECRETO_WEB" \
  -d grant_type=client_credentials -d scope=core.write "$AUTH_URL/oauth2/token")
esperado "POST /oauth2/token bff-web scope=core.write" "$CODIGO" 400

separador "6.1 auth-server rechaza un secreto de cliente incorrecto"
curl -s -u "bff-web:secreto-incorrecto" -d grant_type=client_credentials -d scope=core.read "$AUTH_URL/oauth2/token" | jq .
CODIGO=$(curl -s -o /dev/null -w "%{http_code}" -u "bff-web:secreto-incorrecto" \
  -d grant_type=client_credentials -d scope=core.read "$AUTH_URL/oauth2/token")
esperado "POST /oauth2/token con secreto incorrecto" "$CODIGO" 401

echo
if [ "$FALLAS" -gt 0 ]; then
  echo "=== Fin de las pruebas OAuth 2.0: $FALLAS verificacion(es) fallaron ===" >&2
  exit 1
fi
echo "=== Fin de las pruebas OAuth 2.0: todas las verificaciones OK ==="
