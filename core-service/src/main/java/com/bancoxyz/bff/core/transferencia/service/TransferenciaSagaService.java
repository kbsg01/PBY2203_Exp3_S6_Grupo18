package com.bancoxyz.bff.core.transferencia.service;

import com.bancoxyz.bff.core.model.Cuenta;
import com.bancoxyz.bff.core.repository.CuentaRepository;
import com.bancoxyz.bff.core.transferencia.dto.DebitoAplicadoEvent;
import com.bancoxyz.bff.core.transferencia.dto.TransferenciaEstadoDTO;
import com.bancoxyz.bff.core.transferencia.dto.TransferenciaResultadoEvent;
import com.bancoxyz.bff.core.transferencia.dto.TransferenciaSolicitadaEvent;
import com.bancoxyz.bff.core.transferencia.repository.TransferenciaEstadoRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.stereotype.Service;

import java.util.Optional;

/**
 * Implementa la SAGA (patron de coreografia) del caso de uso "transferencia entre cuentas",
 * introducido en la Semana 7. A diferencia de un deposito o un retiro (Semana 4-6, una unica
 * operacion local sobre una cuenta), una transferencia toca DOS cuentas y se modela como una
 * secuencia de pasos independientes que se comunican exclusivamente a traves de eventos Kafka,
 * nunca con una llamada de metodo directa entre pasos:
 *
 * <pre>
 *   1) onSolicitada:      debita cuentaOrigen -> publica DebitoAplicadoEvent
 *                         (o, si falla la validacion, termina aqui mismo publicando RECHAZADA)
 *   2) onDebitoAplicado:  acredita cuentaDestino -> publica TransferenciaResultadoEvent(COMPLETADA)
 *                         (o, si la cuenta destino no existe, COMPENSA el debito del paso 1 y
 *                         publica TransferenciaResultadoEvent(COMPENSADA))
 * </pre>
 *
 * <p><b>Por que Saga y no una transaccion local unica.</b> Aunque hoy ambas cuentas viven en el
 * mismo core-service (una unica fuente de verdad, ver {@link CuentaRepository}), modelar los dos
 * pasos como eventos independientes, en vez de un unico metodo con dos actualizaciones dentro de
 * la misma transaccion, tiene dos ventajas concretas que S4-S6 no necesitaban: (1) cada paso
 * queda como un evento auditable y reproducible por separado (se puede ver en Kafka exactamente
 * en que paso quedo una transferencia, incluso si el proceso se reinicia a mitad de camino), y
 * (2) el diseno queda listo para el dia en que las cuentas de distintos tipos se separen en
 * microservicios distintos (evolucion natural de este mismo ecosistema) sin tener que rediseniar
 * el flujo: ya esta pensado como una secuencia de pasos compensables, no como una transaccion
 * ACID que dejaria de ser posible en cuanto los datos se distribuyan.</p>
 */
@Service
public class TransferenciaSagaService {

    private static final Logger log = LoggerFactory.getLogger(TransferenciaSagaService.class);

    private final CuentaRepository cuentaRepository;
    private final TransferenciaEstadoRepository estadoRepository;
    private final KafkaTemplate<String, Object> kafkaTemplate;
    private final String topicoDebitoAplicado;
    private final String topicoResultado;

    public TransferenciaSagaService(
            CuentaRepository cuentaRepository,
            TransferenciaEstadoRepository estadoRepository,
            KafkaTemplate<String, Object> kafkaTemplate,
            @Value("${kafka.topics.transferencias-debito-aplicado}") String topicoDebitoAplicado,
            @Value("${kafka.topics.transferencias-resultado}") String topicoResultado) {
        this.cuentaRepository = cuentaRepository;
        this.estadoRepository = estadoRepository;
        this.kafkaTemplate = kafkaTemplate;
        this.topicoDebitoAplicado = topicoDebitoAplicado;
        this.topicoResultado = topicoResultado;
    }

    /**
     * Paso 1 de la saga. Se sincroniza sobre la cuenta origen (mismo mecanismo que ya usaba
     * {@code CuentaInternalController#debitarSaldo} para el retiro por cajero, ver Semana 4-6):
     * dos transferencias concurrentes desde la misma cuenta no deben poder leer el mismo saldo
     * "viejo" y debitar ambas como si el dinero alcanzara para las dos.
     */
    @KafkaListener(
            topics = "${kafka.topics.transferencias-solicitadas}",
            groupId = "${spring.kafka.consumer.group-id}",
            containerFactory = "solicitudListenerContainerFactory")
    public void onSolicitada(TransferenciaSolicitadaEvent evento) {
        log.info("Saga transferencia {}: solicitud recibida (origen={}, destino={}, monto={})",
                evento.transferenciaId(), evento.cuentaOrigen(), evento.cuentaDestino(), evento.monto());

        estadoRepository.guardar(new TransferenciaEstadoDTO(evento.transferenciaId(), evento.cuentaOrigen(),
                evento.cuentaDestino(), evento.monto(), TransferenciaEstadoDTO.EN_PROCESO, null));

        Optional<Cuenta> cuentaOrigenOpt = cuentaRepository.buscarPorId(evento.cuentaOrigen());
        if (cuentaOrigenOpt.isEmpty()) {
            rechazar(evento, "La cuenta origen " + evento.cuentaOrigen() + " no existe.");
            return;
        }

        Cuenta cuentaOrigen = cuentaOrigenOpt.get();
        synchronized (cuentaOrigen) {
            if (cuentaOrigen.getSaldo() < evento.monto()) {
                rechazar(evento, "Saldo insuficiente en la cuenta origen (saldo=" + cuentaOrigen.getSaldo()
                        + ", solicitado=" + evento.monto() + ").");
                return;
            }
            cuentaOrigen.setSaldo(cuentaOrigen.getSaldo() - evento.monto());
        }
        log.info("Saga transferencia {}: debito aplicado en cuenta {} (nuevo saldo={})",
                evento.transferenciaId(), evento.cuentaOrigen(), cuentaOrigen.getSaldo());

        kafkaTemplate.send(topicoDebitoAplicado, evento.transferenciaId(),
                new DebitoAplicadoEvent(evento.transferenciaId(), evento.cuentaOrigen(), evento.cuentaDestino(), evento.monto()));
    }

    /**
     * Paso 2 de la saga. Si la cuenta destino no existe, se ejecuta la COMPENSACION: revierte el
     * debito aplicado en el paso 1 (re-acredita cuentaOrigen), dejando el sistema en el mismo
     * estado que si la transferencia nunca se hubiese solicitado -la garantia central que ofrece
     * el patron Saga ante un fallo a mitad de una transaccion distribuida en pasos.
     */
    @KafkaListener(
            topics = "${kafka.topics.transferencias-debito-aplicado}",
            groupId = "${spring.kafka.consumer.group-id}",
            containerFactory = "debitoAplicadoListenerContainerFactory")
    public void onDebitoAplicado(DebitoAplicadoEvent evento) {
        Optional<Cuenta> cuentaDestinoOpt = cuentaRepository.buscarPorId(evento.cuentaDestino());

        if (cuentaDestinoOpt.isEmpty()) {
            compensar(evento);
            return;
        }

        Cuenta cuentaDestino = cuentaDestinoOpt.get();
        synchronized (cuentaDestino) {
            cuentaDestino.setSaldo(cuentaDestino.getSaldo() + evento.monto());
        }
        log.info("Saga transferencia {}: credito aplicado en cuenta {} (nuevo saldo={}) - TRANSFERENCIA COMPLETADA",
                evento.transferenciaId(), evento.cuentaDestino(), cuentaDestino.getSaldo());

        TransferenciaEstadoDTO estadoFinal = new TransferenciaEstadoDTO(evento.transferenciaId(), evento.cuentaOrigen(),
                evento.cuentaDestino(), evento.monto(), TransferenciaEstadoDTO.COMPLETADA, null);
        estadoRepository.guardar(estadoFinal);
        publicarResultado(estadoFinal);
    }

    /** Rechazo temprano (paso 1): nunca se llego a debitar nada, asi que no hace falta compensar. */
    private void rechazar(TransferenciaSolicitadaEvent evento, String motivo) {
        log.warn("Saga transferencia {}: RECHAZADA - {}", evento.transferenciaId(), motivo);
        TransferenciaEstadoDTO estadoFinal = new TransferenciaEstadoDTO(evento.transferenciaId(), evento.cuentaOrigen(),
                evento.cuentaDestino(), evento.monto(), TransferenciaEstadoDTO.RECHAZADA, motivo);
        estadoRepository.guardar(estadoFinal);
        publicarResultado(estadoFinal);
    }

    /** Compensacion (paso 2 fallido): el debito del paso 1 SI se aplico, hay que revertirlo. */
    private void compensar(DebitoAplicadoEvent evento) {
        String motivo = "La cuenta destino " + evento.cuentaDestino() + " no existe; se revirtio el debito aplicado en la cuenta origen.";
        log.warn("Saga transferencia {}: COMPENSANDO - {}", evento.transferenciaId(), motivo);

        cuentaRepository.buscarPorId(evento.cuentaOrigen()).ifPresent(cuentaOrigen -> {
            synchronized (cuentaOrigen) {
                cuentaOrigen.setSaldo(cuentaOrigen.getSaldo() + evento.monto());
            }
            log.info("Saga transferencia {}: debito compensado en cuenta {} (saldo restaurado a {})",
                    evento.transferenciaId(), evento.cuentaOrigen(), cuentaOrigen.getSaldo());
        });

        TransferenciaEstadoDTO estadoFinal = new TransferenciaEstadoDTO(evento.transferenciaId(), evento.cuentaOrigen(),
                evento.cuentaDestino(), evento.monto(), TransferenciaEstadoDTO.COMPENSADA, motivo);
        estadoRepository.guardar(estadoFinal);
        publicarResultado(estadoFinal);
    }

    private void publicarResultado(TransferenciaEstadoDTO estado) {
        kafkaTemplate.send(topicoResultado, estado.transferenciaId(), new TransferenciaResultadoEvent(
                estado.transferenciaId(), estado.cuentaOrigen(), estado.cuentaDestino(), estado.monto(),
                estado.estado(), estado.detalle()));
    }
}
