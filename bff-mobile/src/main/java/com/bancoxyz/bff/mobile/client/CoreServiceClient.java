package com.bancoxyz.bff.mobile.client;

import com.bancoxyz.bff.mobile.config.CoreServiceProperties;
import com.bancoxyz.bff.mobile.exception.CoreServiceNoDisponibleException;
import com.bancoxyz.bff.mobile.exception.CuentaNoEncontradaException;
import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import io.github.resilience4j.retry.annotation.Retry;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpMethod;
import org.springframework.security.oauth2.client.ClientAuthorizationException;
import org.springframework.stereotype.Component;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.RestTemplate;

@Component
public class CoreServiceClient {

    private final RestTemplate restTemplate;
    private final CoreServiceProperties propiedades;

    public CoreServiceClient(RestTemplate restTemplate, CoreServiceProperties propiedades) {
        this.restTemplate = restTemplate;
        this.propiedades = propiedades;
    }

    @CircuitBreaker(name = "coreService", fallbackMethod = "obtenerCuentaFallback")
    @Retry(name = "coreServiceLectura")
    public CuentaCoreDTO obtenerCuenta(long cuentaId) {
        try {
            var respuesta = restTemplate.exchange(
                    propiedades.getBaseUrl() + "/internal/cuentas/{cuentaId}",
                    HttpMethod.GET,
                    HttpEntity.EMPTY,
                    CuentaCoreDTO.class,
                    cuentaId);
            return respuesta.getBody();
        } catch (HttpClientErrorException.NotFound e) {
            throw new CuentaNoEncontradaException(cuentaId);
        }
    }

    private CuentaCoreDTO obtenerCuentaFallback(long cuentaId, Throwable t) {
        if (t instanceof CuentaNoEncontradaException) {
            throw (CuentaNoEncontradaException) t;
        }
        throw new CoreServiceNoDisponibleException(mensajeNoDisponible(t), t);
    }

    /**
     * Desde la Semana 8 una llamada a core-service tambien puede fallar ANTES de salir, si
     * auth-server no entrega un access token. Para el cliente final el efecto es el mismo (503),
     * pero el mensaje distingue cual de las dos dependencias fallo.
     */
    private static String mensajeNoDisponible(Throwable t) {
        if (t instanceof ClientAuthorizationException) {
            return "Servicio de autorizacion (auth-server) no disponible en este momento, intente mas tarde.";
        }
        return "core-service no disponible en este momento, intente mas tarde.";
    }
}
