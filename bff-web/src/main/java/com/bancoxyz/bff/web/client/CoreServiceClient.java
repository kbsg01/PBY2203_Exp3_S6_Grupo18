package com.bancoxyz.bff.web.client;

import com.bancoxyz.bff.web.config.CoreServiceProperties;
import com.bancoxyz.bff.web.exception.CoreServiceNoDisponibleException;
import com.bancoxyz.bff.web.exception.CuentaNoEncontradaException;
import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.RestTemplate;
import org.springframework.stereotype.Component;

/**
 * Unico punto de acceso de bff-web hacia el backend generalizado (core-service). Ningun
 * controlador de este modulo llama a {@code RestTemplate} directamente: todos pasan por aqui,
 * que es quien agrega el encabezado {@code X-Internal-Api-Key} de forma centralizada.
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
    public CuentaCoreDTO obtenerCuenta(long cuentaId) {
        try {
            var respuesta = restTemplate.exchange(
                    propiedades.getBaseUrl() + "/internal/cuentas/{cuentaId}",
                    HttpMethod.GET,
                    new HttpEntity<>(cabecerasInternas()),
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
        throw new CoreServiceNoDisponibleException(
                "core-service no disponible en este momento, intente mas tarde.", t);
    }

    private HttpHeaders cabecerasInternas() {
        HttpHeaders headers = new HttpHeaders();
        headers.set("X-Internal-Api-Key", propiedades.getApiKey());
        return headers;
    }
}
