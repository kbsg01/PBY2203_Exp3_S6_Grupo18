package com.bancoxyz.bff.core.config;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.oauth2.server.resource.web.BearerTokenAuthenticationEntryPoint;
import org.springframework.security.oauth2.server.resource.web.access.BearerTokenAccessDeniedHandler;
import org.springframework.security.web.AuthenticationEntryPoint;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.access.AccessDeniedHandler;

/**
 * core-service como <b>OAuth 2.0 Resource Server</b> (Semana 8).
 *
 * <p>Reemplaza a la clave compartida {@code X-Internal-Api-Key} de las semanas 4-7: en vez de
 * que cada BFF conozca un mismo secreto estatico, cada uno presenta un access token JWT emitido
 * por auth-server. Este servicio solo valida la firma (contra el JWKS publicado por auth-server),
 * el emisor ({@code iss}), la vigencia ({@code exp}/{@code nbf}) y el {@code scope}; nunca ve ni
 * almacena credenciales de nadie (delegacion de seguridad).</p>
 *
 * <p>Autorizacion por scope (menor privilegio):</p>
 * <ul>
 *   <li>{@code GET /internal/**} exige {@code SCOPE_core.read} (los 3 BFF lo tienen).</li>
 *   <li>{@code POST /internal/**} (hoy: el debito de un retiro) exige {@code SCOPE_core.write},
 *       que solo tiene bff-atm. Un token valido de bff-web o bff-mobile recibe 403.</li>
 *   <li>{@code /actuator/health} es publico: lo consultan el HEALTHCHECK de Docker y
 *       docker-compose, y no expone datos de negocio.</li>
 *   <li>Cualquier otra ruta se deniega por defecto.</li>
 * </ul>
 *
 * <p>Sin sesiones ni cookies (STATELESS), por lo que CSRF no aplica a esta API.</p>
 */
@Configuration
@EnableWebSecurity
public class SecurityConfig {

    private static final Logger log = LoggerFactory.getLogger(SecurityConfig.class);

    @Bean
    public SecurityFilterChain securityFilterChain(HttpSecurity http) throws Exception {
        http
                .authorizeHttpRequests(auth -> auth
                        .requestMatchers("/actuator/health/**").permitAll()
                        .requestMatchers(HttpMethod.GET, "/internal/**").hasAuthority("SCOPE_core.read")
                        .requestMatchers(HttpMethod.POST, "/internal/**").hasAuthority("SCOPE_core.write")
                        .anyRequest().denyAll())
                .oauth2ResourceServer(oauth2 -> oauth2
                        .jwt(jwt -> { })
                        .authenticationEntryPoint(entryPointConLog())
                        .accessDeniedHandler(accessDeniedConLog()))
                .sessionManagement(s -> s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .csrf(csrf -> csrf.disable());
        return http.build();
    }

    /**
     * 401: sin token, token mal firmado, expirado o de otro emisor. Delega la respuesta en el
     * entry point estandar (que agrega el header WWW-Authenticate de RFC 6750) y solo agrega
     * una linea de log, igual que hacia el antiguo InternalApiKeyFilter.
     */
    private AuthenticationEntryPoint entryPointConLog() {
        BearerTokenAuthenticationEntryPoint delegado = new BearerTokenAuthenticationEntryPoint();
        return (request, response, ex) -> {
            log.warn("Acceso rechazado (401) a {} {}: {}", request.getMethod(), request.getRequestURI(), ex.getMessage());
            delegado.commence(request, response, ex);
        };
    }

    /** 403: token valido, pero sin el scope que exige la ruta (ej. bff-mobile intentando un debito). */
    private AccessDeniedHandler accessDeniedConLog() {
        BearerTokenAccessDeniedHandler delegado = new BearerTokenAccessDeniedHandler();
        return (request, response, ex) -> {
            log.warn("Acceso rechazado (403) a {} {}: scope insuficiente para el cliente {}",
                    request.getMethod(), request.getRequestURI(),
                    request.getUserPrincipal() != null ? request.getUserPrincipal().getName() : "desconocido");
            delegado.handle(request, response, ex);
        };
    }
}
