package com.bancoxyz.bff.core.transferencia.config;

import com.bancoxyz.bff.core.transferencia.dto.DebitoAplicadoEvent;
import com.bancoxyz.bff.core.transferencia.dto.TransferenciaSolicitadaEvent;
import org.apache.kafka.clients.consumer.ConsumerConfig;
import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.common.serialization.StringDeserializer;
import org.apache.kafka.common.serialization.StringSerializer;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.kafka.annotation.EnableKafka;
import org.springframework.kafka.config.ConcurrentKafkaListenerContainerFactory;
import org.springframework.kafka.core.*;
import org.springframework.kafka.support.serializer.ErrorHandlingDeserializer;
import org.springframework.kafka.support.serializer.JsonDeserializer;
import org.springframework.kafka.support.serializer.JsonSerializer;

import java.util.HashMap;
import java.util.Map;

/**
 * core-service es, a la vez, PRODUCTOR (publica DebitoAplicadoEvent y TransferenciaResultadoEvent)
 * y CONSUMIDOR (de TransferenciaSolicitadaEvent y de su propio DebitoAplicadoEvent) de eventos de
 * la saga de transferencias.
 *
 * <p>Se configuran DOS fabricas de listener (una por tipo de evento consumido) en vez de una
 * generica, y en el productor se desactiva el header {@code __TypeId__}
 * ({@link JsonSerializer#ADD_TYPE_INFO_HEADERS}): asi cada consumidor sabe de antemano, por su
 * propio topico, que tipo de evento le corresponde deserializar (ver
 * {@link TransferenciaSagaService}), sin depender de un header que de todos modos llevaria el
 * nombre de clase de OTRO microservicio en el caso de {@code TransferenciaSolicitadaEvent}
 * (publicado por bff-web, que tiene su propia copia local de esa clase).</p>
 */
@Configuration
@EnableKafka
public class KafkaConfig {

    @Value("${spring.kafka.bootstrap-servers}")
    private String bootstrapServers;

    @Value("${spring.kafka.consumer.group-id}")
    private String groupId;

    // ---- Productor (comun para todos los eventos que publica core-service) ----

    @Bean
    public ProducerFactory<String, Object> producerFactory() {
        Map<String, Object> props = new HashMap<>();
        props.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrapServers);
        props.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class);
        props.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, JsonSerializer.class);
        props.put(ProducerConfig.ACKS_CONFIG, "all");
        props.put(JsonSerializer.ADD_TYPE_INFO_HEADERS, false);
        return new DefaultKafkaProducerFactory<>(props);
    }

    @Bean
    public KafkaTemplate<String, Object> kafkaTemplate() {
        return new KafkaTemplate<>(producerFactory());
    }

    // ---- Consumidor de "transferencias.solicitadas" (dispara el paso 1: debito) ----

    @Bean
    public ConsumerFactory<String, TransferenciaSolicitadaEvent> solicitudConsumerFactory() {
        return new DefaultKafkaConsumerFactory<>(propsConsumidor(TransferenciaSolicitadaEvent.class));
    }

    @Bean
    public ConcurrentKafkaListenerContainerFactory<String, TransferenciaSolicitadaEvent> solicitudListenerContainerFactory() {
        ConcurrentKafkaListenerContainerFactory<String, TransferenciaSolicitadaEvent> factory =
                new ConcurrentKafkaListenerContainerFactory<>();
        factory.setConsumerFactory(solicitudConsumerFactory());
        return factory;
    }

    // ---- Consumidor de "transferencias.debito-aplicado" (dispara el paso 2: credito) ----

    @Bean
    public ConsumerFactory<String, DebitoAplicadoEvent> debitoAplicadoConsumerFactory() {
        return new DefaultKafkaConsumerFactory<>(propsConsumidor(DebitoAplicadoEvent.class));
    }

    @Bean
    public ConcurrentKafkaListenerContainerFactory<String, DebitoAplicadoEvent> debitoAplicadoListenerContainerFactory() {
        ConcurrentKafkaListenerContainerFactory<String, DebitoAplicadoEvent> factory =
                new ConcurrentKafkaListenerContainerFactory<>();
        factory.setConsumerFactory(debitoAplicadoConsumerFactory());
        return factory;
    }

    private Map<String, Object> propsConsumidor(Class<?> tipoEsperado) {
        Map<String, Object> props = new HashMap<>();
        props.put(ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrapServers);
        props.put(ConsumerConfig.GROUP_ID_CONFIG, groupId);
        props.put(ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "earliest");
        props.put(ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG, ErrorHandlingDeserializer.class);
        props.put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, ErrorHandlingDeserializer.class);
        props.put(ErrorHandlingDeserializer.KEY_DESERIALIZER_CLASS, StringDeserializer.class);
        props.put(ErrorHandlingDeserializer.VALUE_DESERIALIZER_CLASS, JsonDeserializer.class);
        props.put(JsonDeserializer.TRUSTED_PACKAGES, "com.bancoxyz.bff.core.transferencia.dto");
        props.put(JsonDeserializer.USE_TYPE_INFO_HEADERS, false);
        props.put(JsonDeserializer.VALUE_DEFAULT_TYPE, tipoEsperado.getName());
        return props;
    }
}
