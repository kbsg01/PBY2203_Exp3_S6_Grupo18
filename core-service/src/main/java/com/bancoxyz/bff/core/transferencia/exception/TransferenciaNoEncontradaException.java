package com.bancoxyz.bff.core.transferencia.exception;

public class TransferenciaNoEncontradaException extends RuntimeException {
    public TransferenciaNoEncontradaException(String transferenciaId) {
        super("No existe una transferencia con id=" + transferenciaId);
    }
}
