#!/usr/bin/env bash
# Ejercita el caso de uso nuevo de la Semana 7 (transferencia entre cuentas, modelado como Saga
# por coreografia con Kafka) con sus 3 desenlaces posibles: completada, rechazada y compensada.
# Pensado para correr DESPUES de scripts/probar_apis.sh (reutiliza el login de la cuenta 101,
# "John Doe", ya documentado en el README) y con Kafka + los 6 microservicios ya arriba.
#
# Requiere: curl, jq. Asume Kafka en localhost:9092 y los 6 servicios de la Semana 6 mas
# notificaciones-service arriba en sus puertos por defecto.
set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/_common.sh

CORE=http://localhost:8080
WEB=https://localhost:8081

separador() { echo; echo "=== $1 ==="; }

# Lectura directa del saldo en core-service (fuente de verdad) para verificar cada desenlace de
# la saga. Desde la Semana 8 exige un access token OAuth 2.0: se usa el cliente de solo lectura
# "evidencia-cli" (un token nuevo por consulta: dura 5 minutos y este script es corto).
saldo_de() {
  curl -s -H "Authorization: Bearer $(token_evidencia)" "$CORE/internal/cuentas/$1" | jq -r .saldo
}

separador "0. Login canal WEB (cuenta 101, 'John Doe') - se reutiliza para las 3 transferencias"
TOKEN=$(curl -s -k -X POST "$WEB/api/web/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"cuentaId":101,"nombre":"John Doe"}' | jq -r .token)
if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
  echo "No se pudo obtener un token web (¿bff-web o core-service no estan arriba?)." >&2
  exit 1
fi

# ============================================================================================
# Escenario 1: transferencia exitosa (101 -> 105, $500)
# ============================================================================================
separador "1. Transferencia EXITOSA: cuenta 101 -> cuenta 105, \$500"
SALDO_101_ANTES=$(saldo_de 101)
SALDO_105_ANTES=$(saldo_de 105)
echo "Saldo antes: cuenta 101 = $SALDO_101_ANTES | cuenta 105 = $SALDO_105_ANTES"

RESPUESTA=$(curl -s -k -w "\n%{http_code}" -X POST "$WEB/api/web/cuentas/101/transferencias" \
  -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" \
  -d '{"cuentaDestino":105,"monto":500}')
HTTP_CODE=$(echo "$RESPUESTA" | tail -n1)
BODY=$(echo "$RESPUESTA" | sed '$d')
echo "$BODY" | jq .
echo "POST /transferencias -> HTTP $HTTP_CODE (se espera 202)"
ID_1=$(echo "$BODY" | jq -r .transferenciaId)

echo "Esperando el resultado final de la saga..."
ESTADO_1=$(esperar_estado_transferencia "$TOKEN" "$ID_1")
echo "$ESTADO_1" | jq .
echo "Estado final -> $(echo "$ESTADO_1" | jq -r .estado) (se espera COMPLETADA)"

SALDO_101_DESPUES=$(saldo_de 101)
SALDO_105_DESPUES=$(saldo_de 105)
echo "Saldo despues: cuenta 101 = $SALDO_101_DESPUES (baja \$500) | cuenta 105 = $SALDO_105_DESPUES (sube \$500)"

# ============================================================================================
# Escenario 2: transferencia RECHAZADA por fondos insuficientes (monto absurdamente alto)
# ============================================================================================
separador "2. Transferencia RECHAZADA: fondos insuficientes en la cuenta origen"
SALDO_101_ANTES_2=$(saldo_de 101)

RESPUESTA=$(curl -s -k -X POST "$WEB/api/web/cuentas/101/transferencias" \
  -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" \
  -d '{"cuentaDestino":105,"monto":999999999}')
ID_2=$(echo "$RESPUESTA" | jq -r .transferenciaId)

ESTADO_2=$(esperar_estado_transferencia "$TOKEN" "$ID_2")
echo "$ESTADO_2" | jq .
echo "Estado final -> $(echo "$ESTADO_2" | jq -r .estado) (se espera RECHAZADA)"

SALDO_101_DESPUES_2=$(saldo_de 101)
echo "Saldo cuenta 101: antes=$SALDO_101_ANTES_2 despues=$SALDO_101_DESPUES_2 (deben ser iguales: nunca se llego a debitar)"

# ============================================================================================
# Escenario 3: transferencia COMPENSADA (cuenta destino inexistente)
# ============================================================================================
separador "3. Transferencia COMPENSADA: la cuenta destino no existe (se revierte el debito)"
SALDO_101_ANTES_3=$(saldo_de 101)

RESPUESTA=$(curl -s -k -X POST "$WEB/api/web/cuentas/101/transferencias" \
  -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" \
  -d '{"cuentaDestino":999999,"monto":250}')
ID_3=$(echo "$RESPUESTA" | jq -r .transferenciaId)

ESTADO_3=$(esperar_estado_transferencia "$TOKEN" "$ID_3")
echo "$ESTADO_3" | jq .
echo "Estado final -> $(echo "$ESTADO_3" | jq -r .estado) (se espera COMPENSADA)"

SALDO_101_DESPUES_3=$(saldo_de 101)
echo "Saldo cuenta 101: antes=$SALDO_101_ANTES_3 despues=$SALDO_101_DESPUES_3 (deben ser iguales: se debito \$250 y" \
     "la compensacion lo volvio a acreditar)"

# ============================================================================================
# Escenario 4: un token NO puede consultar/iniciar transferencias de otra cuenta (autorizacion)
# ============================================================================================
separador "4. Autorizacion: el token de la cuenta 101 no puede transferir DESDE la cuenta 105"
curl -s -k -o /dev/null -w "POST /api/web/cuentas/105/transferencias con token de la cuenta 101 -> HTTP %{http_code} (se espera 403)\n" \
  -X POST "$WEB/api/web/cuentas/105/transferencias" \
  -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" \
  -d '{"cuentaDestino":101,"monto":10}'

# ============================================================================================
# Un par de transferencias adicionales, solo para generar mas eventos y que la evidencia de
# escalabilidad de notificaciones-service (ver generar_evidencia.sh) tenga varios mensajes
# repartidos entre las 4 particiones, no solo 3.
# ============================================================================================
separador "5. Transferencias adicionales (para la evidencia de escalabilidad de notificaciones-service)"
for monto in 50 75 120; do
  curl -s -k -X POST "$WEB/api/web/cuentas/101/transferencias" \
    -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" \
    -d "{\"cuentaDestino\":105,\"monto\":$monto}" | jq -c .
done
echo "Esperando unos segundos a que notificaciones-service procese los eventos generados..."
sleep 5

echo
echo "=== Fin de las pruebas de transferencias ==="
