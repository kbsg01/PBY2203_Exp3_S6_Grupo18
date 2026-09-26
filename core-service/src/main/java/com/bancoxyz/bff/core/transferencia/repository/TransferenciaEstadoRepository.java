package com.bancoxyz.bff.core.transferencia.repository;

import com.bancoxyz.bff.core.transferencia.dto.TransferenciaEstadoDTO;
import org.springframework.stereotype.Repository;

import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Almacen en memoria (mismo criterio deliberado que {@code CuentaRepository}: el foco de esta
 * actividad es la arquitectura de eventos, no la capa de persistencia) del ultimo snapshot de
 * estado conocido para cada transferencia en curso o terminada, indexado por transferenciaId.
 */
@Repository
public class TransferenciaEstadoRepository {

    private final Map<String, TransferenciaEstadoDTO> estados = new ConcurrentHashMap<>();

    public void guardar(TransferenciaEstadoDTO estado) {
        estados.put(estado.transferenciaId(), estado);
    }

    public Optional<TransferenciaEstadoDTO> buscar(String transferenciaId) {
        return Optional.ofNullable(estados.get(transferenciaId));
    }
}
