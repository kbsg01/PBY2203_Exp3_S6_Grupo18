package com.bancoxyz.bff.web.transferencia.exception;

public class TransferenciaNoEncontradaException extends RuntimeException {
    public TransferenciaNoEncontradaException(String transferenciaId) {
        super("No existe una transferencia con id=" + transferenciaId);
    }
}
