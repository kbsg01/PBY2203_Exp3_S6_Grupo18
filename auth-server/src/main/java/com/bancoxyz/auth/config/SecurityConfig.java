package com.bancoxyz.auth.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.annotation.Order;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.oauth2.server.authorization.config.annotation.web.configuration.OAuth2AuthorizationServerConfiguration;
import org.springframework.security.web.SecurityFilterChain;

/**
 * Dos cadenas de seguridad, en orden:
 *
 * <ol>
 *   <li>Endpoints del protocolo OAuth 2.0 ({@code /oauth2/token}, {@code /oauth2/jwks},
 *       {@code /oauth2/introspect}, {@code /oauth2/revoke},
 *       {@code /.well-known/oauth-authorization-server}): configuracion por defecto de Spring
 *       Authorization Server. Los clientes registrados se definen por properties en
 *       {@code application.yml} (soporte nativo de Spring Boot 3.1+).</li>
 *   <li>Todo lo demas: solo {@code /actuator/health} es publico (lo usan el HEALTHCHECK de Docker y
 *       docker-compose); cualquier otra ruta se rechaza. No hay formulario de login porque este
 *       servidor no autentica personas.</li>
 * </ol>
 *
 * <p>Ambas cadenas reemplazan las que Spring Boot autoconfiguraria por defecto (que incluirian un
 * formulario de login y protegerian tambien /actuator/health, rompiendo el healthcheck).</p>
 */
@Configuration
@EnableWebSecurity
public class SecurityConfig {

    @Bean
    @Order(1)
    public SecurityFilterChain authorizationServerSecurityFilterChain(HttpSecurity http) throws Exception {
        OAuth2AuthorizationServerConfiguration.applyDefaultSecurity(http);
        return http.build();
    }

    @Bean
    @Order(2)
    public SecurityFilterChain defaultSecurityFilterChain(HttpSecurity http) throws Exception {
        http
                .authorizeHttpRequests(auth -> auth
                        .requestMatchers("/actuator/health/**").permitAll()
                        .anyRequest().denyAll())
                .sessionManagement(s -> s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .csrf(csrf -> csrf.disable());
        return http.build();
    }
}
