package com.bancoxyz.bff.web.client;

import com.bancoxyz.bff.web.config.CoreServiceProperties;
import com.bancoxyz.bff.web.exception.CoreServiceNoDisponibleException;
import com.bancoxyz.bff.web.exception.CuentaNoEncontradaException;
import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import io.github.resilience4j.retry.annotation.Retry;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpMethod;
import org.springframework.security.oauth2.client.ClientAuthorizationException;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.RestTemplate;
import org.springframework.stereotype.Component;

/**
 * Unico punto de acceso de bff-web hacia el backend generalizado (core-service). Ningun
 * controlador de este modulo llama a {@code RestTemplate} directamente: todos pasan por aqui,
 * que es quien aplica Retry + Circuit Breaker de forma centralizada. El access token OAuth 2.0 lo
 * agrega el propio RestTemplate (ver {@code OAuth2ClientConfig}).
 */
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
