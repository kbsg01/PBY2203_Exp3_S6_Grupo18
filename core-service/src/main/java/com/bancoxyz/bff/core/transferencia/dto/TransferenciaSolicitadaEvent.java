package com.bancoxyz.bff.core.transferencia.dto;

/**
 * Evento que inicia la saga (coreografia): lo publica bff-web en el topico
 * {@code bancoxyz.transferencias.solicitadas} y lo consume {@link
 * com.bancoxyz.bff.core.transferencia.service.TransferenciaSagaService#onSolicitada}.
 *
 * <p>Es una copia local del contrato del evento, no una clase compartida con bff-web: cada
 * microservicio de este proyecto es independiente (ver pom.xml raiz) y solo se acopla al
 * FORMATO del mensaje (JSON), nunca a una clase Java de otro modulo.</p>
 */
public record TransferenciaSolicitadaEvent(
        String transferenciaId,
        long cuentaOrigen,
        long cuentaDestino,
        double monto
) {
}
