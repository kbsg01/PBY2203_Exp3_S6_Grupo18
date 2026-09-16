package com.bancoxyz.bff.web.exception;

public class CoreServiceNoDisponibleException extends RuntimeException {
    public CoreServiceNoDisponibleException(String mensaje, Throwable causa) {
        super(mensaje, causa);
    }
}
