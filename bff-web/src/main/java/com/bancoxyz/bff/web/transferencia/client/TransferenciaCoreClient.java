package com.bancoxyz.bff.web.transferencia.client;

import com.bancoxyz.bff.web.config.CoreServiceProperties;
import com.bancoxyz.bff.web.exception.CoreServiceNoDisponibleException;
import com.bancoxyz.bff.web.transferencia.dto.TransferenciaEstadoCoreDTO;
import com.bancoxyz.bff.web.transferencia.exception.TransferenciaNoEncontradaException;
import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import io.github.resilience4j.retry.annotation.Retry;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpMethod;
import org.springframework.security.oauth2.client.ClientAuthorizationException;
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
    @Retry(name = "coreServiceLectura")
    public TransferenciaEstadoCoreDTO obtenerEstado(String transferenciaId) {
        try {
            var respuesta = restTemplate.exchange(
                    propiedades.getBaseUrl() + "/internal/transferencias/{id}",
                    HttpMethod.GET,
                    HttpEntity.EMPTY,
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
