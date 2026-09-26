package com.bancoxyz.bff.web.transferencia.dto;

/**
 * Respuesta inmediata (HTTP 202 Accepted) a la solicitud de transferencia: el patron
 * arquitectonico orientado a eventos es, por definicion, asincrono - a diferencia de un deposito
 * o retiro (Semana 4-6), aqui bff-web NO espera el resultado final antes de responder. El
 * cliente consulta el desenlace real con {@code GET /api/web/transferencias/{transferenciaId}}.
 */
public record TransferenciaWebResponse(String transferenciaId, String estado, String mensaje) {

    public static TransferenciaWebResponse aceptada(String transferenciaId) {
        return new TransferenciaWebResponse(transferenciaId, "EN_PROCESO",
                "Transferencia recibida y en procesamiento. Consulte su estado con GET /api/web/transferencias/" + transferenciaId);
    }
}
