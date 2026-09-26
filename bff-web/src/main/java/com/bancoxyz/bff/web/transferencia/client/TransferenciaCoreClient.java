package com.bancoxyz.bff.web.transferencia.client;

import com.bancoxyz.bff.web.config.CoreServiceProperties;
import com.bancoxyz.bff.web.exception.CoreServiceNoDisponibleException;
import com.bancoxyz.bff.web.transferencia.dto.TransferenciaEstadoCoreDTO;
import com.bancoxyz.bff.web.transferencia.exception.TransferenciaNoEncontradaException;
import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.stereotype.Component;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.RestTemplate;

/**
 * Consulta sincronica (REST) del estado de una transferencia. Reutiliza la MISMA instancia de
 * circuit breaker "coreService" que {@code CoreServiceClient}: es la misma dependencia de
 * infraestructura (core-service via Eureka), asi que comparten, con toda intencion, el mismo
 * dominio de falla y el mismo contador.
 */
@Component
public class TransferenciaCoreClient {

    private final RestTemplate restTemplate;
    private final CoreServiceProperties propiedades;

    public TransferenciaCoreClient(RestTemplate restTemplate, CoreServiceProperties propiedades) {
        this.restTemplate = restTemplate;
        this.propiedades = propiedades;
    }

    @CircuitBreaker(name = "coreService", fallbackMethod = "obtenerEstadoFallback")
    public TransferenciaEstadoCoreDTO obtenerEstado(String transferenciaId) {
        try {
            var respuesta = restTemplate.exchange(
                    propiedades.getBaseUrl() + "/internal/transferencias/{id}",
                    HttpMethod.GET,
                    new HttpEntity<>(cabecerasInternas()),
                    TransferenciaEstadoCoreDTO.class,
                    transferenciaId);
            return respuesta.getBody();
        } catch (HttpClientErrorException.NotFound e) {
            throw new TransferenciaNoEncontradaException(transferenciaId);
        }
    }

    private TransferenciaEstadoCoreDTO obtenerEstadoFallback(String transferenciaId, Throwable t) {
        if (t instanceof TransferenciaNoEncontradaException) {
            throw (TransferenciaNoEncontradaException) t;
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
