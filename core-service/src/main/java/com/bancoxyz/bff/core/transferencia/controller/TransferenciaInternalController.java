package com.bancoxyz.bff.core.transferencia.controller;

import com.bancoxyz.bff.core.transferencia.dto.TransferenciaEstadoDTO;
import com.bancoxyz.bff.core.transferencia.exception.TransferenciaNoEncontradaException;
import com.bancoxyz.bff.core.transferencia.repository.TransferenciaEstadoRepository;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * API interna (misma proteccion que {@code CuentaInternalController}: filtrada por
 * {@code X-Internal-Api-Key}) para que un BFF consulte el estado actual de una transferencia.
 *
 * <p>Nota deliberada: esta consulta es SINCRONICA (REST tradicional, reutilizando Eureka +
 * Spring Cloud LoadBalancer + Circuit Breaker ya existentes desde la Semana 6), no un segundo
 * mecanismo Kafka. La escritura (iniciar una transferencia) es asincrona por evento; la lectura
 * de su estado sigue siendo, deliberadamente, una simple pregunta pregunta-respuesta.</p>
 */
@RestController
@RequestMapping("/internal/transferencias")
public class TransferenciaInternalController {

    private final TransferenciaEstadoRepository estadoRepository;

    public TransferenciaInternalController(TransferenciaEstadoRepository estadoRepository) {
        this.estadoRepository = estadoRepository;
    }

    @GetMapping("/{transferenciaId}")
    public TransferenciaEstadoDTO obtener(@PathVariable String transferenciaId) {
        return estadoRepository.buscar(transferenciaId)
                .orElseThrow(() -> new TransferenciaNoEncontradaException(transferenciaId));
    }
}
