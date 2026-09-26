package com.bancoxyz.bff.web.transferencia.dto;

/**
 * Espejo del {@code TransferenciaEstadoDTO} interno de core-service, recibido via
 * {@code GET /internal/transferencias/{id}} (ver {@code TransferenciaCoreClient}).
 */
public record TransferenciaEstadoCoreDTO(
        String transferenciaId,
        long cuentaOrigen,
        long cuentaDestino,
        double monto,
        String estado,
        String detalle
) {
}
