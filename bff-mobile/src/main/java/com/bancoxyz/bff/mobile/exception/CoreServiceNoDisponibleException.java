package com.bancoxyz.bff.mobile.exception;

public class CoreServiceNoDisponibleException extends RuntimeException {
    public CoreServiceNoDisponibleException(String mensaje, Throwable causa) {
        super(mensaje, causa);
    }
}
