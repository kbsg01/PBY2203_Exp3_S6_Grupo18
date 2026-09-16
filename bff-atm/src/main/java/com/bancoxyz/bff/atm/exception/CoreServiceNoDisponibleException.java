package com.bancoxyz.bff.atm.exception;

public class CoreServiceNoDisponibleException extends RuntimeException {
    public CoreServiceNoDisponibleException(String mensaje, Throwable causa) {
        super(mensaje, causa);
    }
}
