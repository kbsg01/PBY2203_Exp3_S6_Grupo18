package com.bancoxyz.bff.mobile.config;

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
 * Deja en el log cada reintento de Resilience4j (instancia {@code coreServiceLectura}), para
 * que la politica de Retry sea observable en la evidencia de ejecucion y no solo una
 * configuracion en application.yml.
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
}
