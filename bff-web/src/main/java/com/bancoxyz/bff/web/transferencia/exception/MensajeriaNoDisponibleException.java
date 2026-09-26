package com.bancoxyz.bff.web.transferencia.exception;

/** Analoga a {@code CoreServiceNoDisponibleException}, pero para fallas del broker Kafka (dominio de falla distinto). */
public class MensajeriaNoDisponibleException extends RuntimeException {
    public MensajeriaNoDisponibleException(String mensaje, Throwable causa) {
        super(mensaje, causa);
    }
}
