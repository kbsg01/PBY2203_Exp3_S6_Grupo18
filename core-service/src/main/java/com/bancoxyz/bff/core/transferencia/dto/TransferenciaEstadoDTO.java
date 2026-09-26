package com.bancoxyz.bff.core.transferencia.dto;

/**
 * Snapshot del estado actual de una transferencia, expuesto por {@code GET
 * /internal/transferencias/{id}}. Es, en pequeno, un "modelo de lectura" (read model) tipico de
 * arquitecturas orientadas a eventos: no es la fuente de verdad de la saga (esa es la secuencia
 * de eventos ya publicados), sino una proyeccion en memoria que se actualiza cada vez que la saga
 * avanza un paso, pensada para responder rapido una pregunta puntual ("como va mi transferencia")
 * sin tener que releer el historial completo de eventos.
 */
public record TransferenciaEstadoDTO(
        String transferenciaId,
        long cuentaOrigen,
        long cuentaDestino,
        double monto,
        String estado,
        String detalle
) {
    public static final String EN_PROCESO = "EN_PROCESO";
    public static final String COMPLETADA = "COMPLETADA";
    public static final String RECHAZADA = "RECHAZADA";
    public static final String COMPENSADA = "COMPENSADA";
}
