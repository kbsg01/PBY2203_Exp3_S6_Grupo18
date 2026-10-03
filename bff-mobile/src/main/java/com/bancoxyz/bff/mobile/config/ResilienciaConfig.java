package com.bancoxyz.bff.mobile.config;

import io.github.resilience4j.circuitbreaker.CircuitBreaker;
import io.github.resilience4j.core.registry.EntryAddedEvent;
import io.github.resilience4j.core.registry.EntryRemovedEvent;
import io.github.resilience4j.core.registry.EntryReplacedEvent;
import io.github.resilience4j.core.registry.RegistryEventConsumer;
import io.github.resilience4j.retry.Retry;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * Deja en el log cada reintento (Retry {@code coreServiceLectura}) y cada cambio de estado de los
 * circuit breakers (CLOSED -> OPEN -> HALF_OPEN -> CLOSED), para que la tolerancia a fallos sea
 * observable en la evidencia de ejecucion y no solo una configuracion en application.yml.
 */
@Configuration
public class ResilienciaConfig {

    private static final Logger log = LoggerFactory.getLogger(ResilienciaConfig.class);

    @Bean
    public RegistryEventConsumer<Retry> registroEventosRetry() {
        return new RegistryEventConsumer<>() {
            @Override
            public void onEntryAddedEvent(EntryAddedEvent<Retry> evento) {
                evento.getAddedEntry().getEventPublisher()
                        .onRetry(e -> log.warn("Retry '{}': intento {} fallido ({}), reintentando en {} ms",
                                e.getName(), e.getNumberOfRetryAttempts(),
                                e.getLastThrowable() == null ? "?" : e.getLastThrowable().getClass().getSimpleName(),
                                e.getWaitInterval().toMillis()))
                        .onError(e -> log.warn("Retry '{}': agotados {} intentos; se entrega el fallo al circuit breaker",
                                e.getName(), e.getNumberOfRetryAttempts()));
            }

            @Override
            public void onEntryRemovedEvent(EntryRemovedEvent<Retry> evento) {
            }

            @Override
            public void onEntryReplacedEvent(EntryReplacedEvent<Retry> evento) {
            }
        };
    }

    @Bean
    public RegistryEventConsumer<CircuitBreaker> registroEventosCircuitBreaker() {
        return new RegistryEventConsumer<>() {
            @Override
            public void onEntryAddedEvent(EntryAddedEvent<CircuitBreaker> evento) {
                evento.getAddedEntry().getEventPublisher()
                        .onStateTransition(e -> log.warn("CircuitBreaker '{}': {}",
                                e.getCircuitBreakerName(), e.getStateTransition()));
            }

            @Override
            public void onEntryRemovedEvent(EntryRemovedEvent<CircuitBreaker> evento) {
            }

            @Override
            public void onEntryReplacedEvent(EntryReplacedEvent<CircuitBreaker> evento) {
            }
        };
    }
}
