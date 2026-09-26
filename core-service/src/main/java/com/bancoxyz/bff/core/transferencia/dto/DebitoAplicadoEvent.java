package com.bancoxyz.bff.core.transferencia.dto;

/**
 * Segundo paso de la saga: se publica en {@code bancoxyz.transferencias.debito-aplicado} una vez
 * que el debito en la cuenta origen se aplico con exito, y dispara el tercer paso (el intento de
 * credito en la cuenta destino). A diferencia de {@link TransferenciaSolicitadaEvent}, este
 * evento se produce Y se consume dentro del mismo microservicio (core-service): es la propia
 * saga "hablandose a si misma" via Kafka en vez de una llamada de metodo directa, precisamente
 * para que cada paso quede como un evento independiente, auditable y reproducible.
 */
public record DebitoAplicadoEvent(
        String transferenciaId,
        long cuentaOrigen,
        long cuentaDestino,
        double monto
) {
}
