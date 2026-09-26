package com.bancoxyz.bff.web.transferencia.dto;

/**
 * Evento que bff-web publica en {@code bancoxyz.transferencias.solicitadas} para iniciar la
 * saga de transferencias (ver core-service, paquete {@code transferencia}, para el resto del
 * flujo). Copia local del contrato del evento, no una clase compartida (ver Javadoc equivalente
 * en core-service).
 */
public record TransferenciaSolicitadaEvent(
        String transferenciaId,
        long cuentaOrigen,
        long cuentaDestino,
        double monto
) {
}
