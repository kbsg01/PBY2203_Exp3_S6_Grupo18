package com.bancoxyz.bff.web.transferencia.client;

import com.bancoxyz.bff.web.transferencia.dto.TransferenciaSolicitadaEvent;
import com.bancoxyz.bff.web.transferencia.exception.MensajeriaNoDisponibleException;
import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.stereotype.Component;

import java.util.concurrent.TimeUnit;

/**
 * Unico punto de publicacion de eventos de bff-web hacia Kafka. Igual que
 * {@code CoreServiceClient} centraliza las llamadas REST a core-service, esta clase centraliza
 * el unico envio Kafka que hace este modulo.
 *
 * <p>{@code KafkaTemplate.send(...)} devuelve un {@code CompletableFuture}: por si solo, un envio
 * fallido (broker caido) no lanzaria ninguna excepcion visible para el controlador si no se
 * espera ese future. Aqui se espera con un timeout corto y se envuelve con
 * {@code @CircuitBreaker} exactamente con el mismo patron ya usado en {@code CoreServiceClient}
 * para la llamada a core-service, pero sobre la instancia {@code kafkaProducer} (dominio de
 * falla independiente, ver application.yml).</p>
 */
@Component
public class TransferenciaProducer {

    private final KafkaTemplate<String, Object> kafkaTemplate;
    private final String topicoSolicitadas;

    public TransferenciaProducer(
            KafkaTemplate<String, Object> kafkaTemplate,
            @Value("${kafka.topics.transferencias-solicitadas}") String topicoSolicitadas) {
        this.kafkaTemplate = kafkaTemplate;
        this.topicoSolicitadas = topicoSolicitadas;
    }

    @CircuitBreaker(name = "kafkaProducer", fallbackMethod = "publicarSolicitudFallback")
    public void publicarSolicitud(TransferenciaSolicitadaEvent evento) {
        try {
            kafkaTemplate.send(topicoSolicitadas, evento.transferenciaId(), evento).get(3, TimeUnit.SECONDS);
        } catch (Exception e) {
            throw new MensajeriaNoDisponibleException("No se pudo publicar el evento de transferencia.", e);
        }
    }

    private void publicarSolicitudFallback(TransferenciaSolicitadaEvent evento, Throwable t) {
        throw new MensajeriaNoDisponibleException(
                "El sistema de mensajeria no esta disponible en este momento; intente mas tarde.", t);
    }
}
