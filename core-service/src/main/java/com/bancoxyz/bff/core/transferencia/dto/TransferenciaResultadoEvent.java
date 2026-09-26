package com.bancoxyz.bff.core.transferencia.dto;

/**
 * Evento final de la saga (topico {@code bancoxyz.transferencias.resultado}): se publica
 * exactamente una vez por transferencia, sea cual sea el desenlace. Lo consume
 * notificaciones-service (con 2 instancias del mismo consumer group, ver README seccion de
 * escalabilidad); bff-web NO lo consume por Kafka, sino que lee el mismo resultado via el
 * endpoint interno REST {@code GET /internal/transferencias/{id}} para responder a un cliente
 * que esta consultando el estado de su transferencia.
 *
 * @param estado  {@code TransferenciaEstadoRepository.Estado} como String: COMPLETADA | RECHAZADA | COMPENSADA
 * @param detalle motivo legible (solo relevante si el estado no es COMPLETADA)
 */
public record TransferenciaResultadoEvent(
        String transferenciaId,
        long cuentaOrigen,
        long cuentaDestino,
        double monto,
        String estado,
        String detalle
) {
}
