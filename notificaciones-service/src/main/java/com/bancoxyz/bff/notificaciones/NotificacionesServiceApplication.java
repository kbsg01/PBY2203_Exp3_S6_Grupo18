package com.bancoxyz.bff.notificaciones;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * Microservicio nuevo de la Semana 7. A diferencia de los 3 BFF y de core-service, este
 * servicio NO expone ningun endpoint de negocio (solo el health check de Eureka/Actuator):
 * su unica funcion es escuchar el topico Kafka {@code bancoxyz.transferencias.resultado} y
 * reaccionar a el, completamente desacoplado del flujo transaccional critico (que vive en
 * core-service). Ver {@link com.bancoxyz.bff.notificaciones.listener.TransferenciaResultadoListener}.
 */
@SpringBootApplication
public class NotificacionesServiceApplication {
    public static void main(String[] args) {
        SpringApplication.run(NotificacionesServiceApplication.class, args);
    }
}
