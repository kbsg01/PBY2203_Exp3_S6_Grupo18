package com.bancoxyz.bff.atm.client;

import com.bancoxyz.bff.atm.config.CoreServiceProperties;
import com.bancoxyz.bff.atm.exception.CoreServiceNoDisponibleException;
import com.bancoxyz.bff.atm.exception.CuentaNoEncontradaException;
import com.bancoxyz.bff.atm.exception.SaldoInsuficienteException;
import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import io.github.resilience4j.retry.annotation.Retry;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpMethod;
import org.springframework.security.oauth2.client.ClientAuthorizationException;
import org.springframework.stereotype.Component;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.RestTemplate;

import java.util.Map;

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
     * Confirma un retiro debitando el saldo en el backend generalizado (fuente unica de verdad
     * del dinero disponible). La validacion real de "saldo suficiente" ocurre en core-service,
     * no aqui: este BFF solo aplica sus propias reglas de canal (limite maximo por operacion,
     * ver {@code LimiteRetiroExcedidoException}) antes de reenviar la solicitud.
     *
     * <p>Sin {@code @Retry} a proposito (a diferencia de {@link #obtenerCuenta}): un debito NO es
     * idempotente. Si la peticion llego a core-service pero la respuesta se perdio por un timeout,
     * reintentarla podria debitar el retiro dos veces.</p>
     */
    @CircuitBreaker(name = "coreService", fallbackMethod = "debitarSaldoFallback")
    public CuentaCoreDTO debitarSaldo(long cuentaId, double monto) {
        try {
            var respuesta = restTemplate.exchange(
                    propiedades.getBaseUrl() + "/internal/cuentas/{cuentaId}/debito",
                    HttpMethod.POST,
                    new HttpEntity<>(Map.of("monto", monto)),
                    CuentaCoreDTO.class,
                    cuentaId);
            return respuesta.getBody();
        } catch (HttpClientErrorException.NotFound e) {
            throw new CuentaNoEncontradaException(cuentaId);
        } catch (HttpClientErrorException.Conflict e) {
            throw new SaldoInsuficienteException("Saldo insuficiente para realizar el retiro solicitado.");
        }
    }

    private CuentaCoreDTO debitarSaldoFallback(long cuentaId, double monto, Throwable t) {
        if (t instanceof CuentaNoEncontradaException || t instanceof SaldoInsuficienteException) {
            throw (RuntimeException) t;
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
