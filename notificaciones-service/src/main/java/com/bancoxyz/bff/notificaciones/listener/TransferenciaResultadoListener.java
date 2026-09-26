package com.bancoxyz.bff.notificaciones.listener;

import com.bancoxyz.bff.notificaciones.dto.TransferenciaResultadoEvent;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.kafka.support.KafkaHeaders;
import org.springframework.messaging.handler.annotation.Header;
import org.springframework.messaging.handler.annotation.Payload;
import org.springframework.stereotype.Component;

/**
 * Consumidor Kafka desacoplado del camino transaccional critico: simula el envio de una
 * notificacion al cliente (correo/push) cuando la saga de una transferencia termina, sea cual
 * sea el resultado. No puede afectar el resultado de la transferencia (esta ya quedo resuelta en
 * core-service antes de que este evento se publique) - si este servicio estuviera caido, la
 * saga igual se completa correctamente; solo se pierde la notificacion, nunca la consistencia
 * del saldo. Esa es, precisamente, la ventaja de modelarlo como un consumidor de eventos
 * independiente en vez de una llamada sincrona mas dentro de la saga.
 *
 * <p>El log de cada mensaje incluye la particion y el offset de Kafka, no por curiosidad: es la
 * evidencia que permite comprobar, comparando el log de esta instancia con el de la otra (ver
 * scripts/probar_transferencias.sh), que las 4 particiones del topico se repartieron entre las 2
 * instancias del mismo consumer group en vez de que cada una procesara todos los mensajes -la
 * demostracion concreta de "escalabilidad" que pide la pauta de la Semana 7.</p>
 */
@Component
public class TransferenciaResultadoListener {

    private static final Logger log = LoggerFactory.getLogger(TransferenciaResultadoListener.class);

    @org.springframework.beans.factory.annotation.Value("${server.port}")
    private String puertoInstancia;

    @KafkaListener(
            topics = "${kafka.topics.transferencias-resultado}",
            groupId = "${spring.kafka.consumer.group-id}",
            containerFactory = "kafkaListenerContainerFactory")
    public void onResultado(
            @Payload TransferenciaResultadoEvent evento,
            @Header(KafkaHeaders.RECEIVED_PARTITION) int particion,
            @Header(KafkaHeaders.OFFSET) long offset,
            ConsumerRecord<String, TransferenciaResultadoEvent> record) {

        String mensaje = switch (evento.estado()) {
            case "COMPLETADA" -> "Su transferencia de $" + evento.monto() + " a la cuenta " + evento.cuentaDestino()
                    + " se realizo con exito.";
            case "RECHAZADA" -> "Su transferencia de $" + evento.monto() + " no pudo procesarse: " + evento.detalle();
            case "COMPENSADA" -> "Su transferencia de $" + evento.monto() + " fue revertida: " + evento.detalle();
            default -> "Actualizacion de su transferencia " + evento.transferenciaId() + ": " + evento.estado();
        };

        log.info("[instancia :{}] Notificacion procesada (particion={}, offset={}) - transferenciaId={} " +
                        "cuentaOrigen={} estado={} -> \"{}\"",
                puertoInstancia, particion, offset, evento.transferenciaId(), evento.cuentaOrigen(),
                evento.estado(), mensaje);
    }
}
