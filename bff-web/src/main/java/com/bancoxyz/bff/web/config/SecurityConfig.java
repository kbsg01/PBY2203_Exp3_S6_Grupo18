package com.bancoxyz.bff.web.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.web.SecurityFilterChain;

/**
 * Cadena de Spring Security de bff-web.
 *
 * <p>Spring Security entra al classpath por {@code spring-boot-starter-oauth2-client} (necesario
 * para obtener tokens de auth-server, ver {@link OAuth2ClientConfig}). Sin esta clase, Spring Boot
 * activaria su configuracion por defecto (login por formulario + Basic sobre todas las rutas),
 * lo que romperia la autenticacion propia del canal, que sigue siendo responsabilidad de los
 * filtros del paquete {@code security} desde la Semana 5. Por eso aqui:</p>
 * <ul>
 *   <li>No se exige autenticacion de Spring Security ({@code permitAll}): cada ruta de negocio
 *       ya esta protegida por el filtro del canal.</li>
 *   <li>Sin sesiones HTTP ni cookies (STATELESS), por lo que CSRF no aplica.</li>
 *   <li>Se mantienen los headers de seguridad de Spring Security y se endurece HSTS
 *       (1 año, incluye subdominios) y CSP para una API que solo devuelve JSON.</li>
 * </ul>
 */
@Configuration
@EnableWebSecurity
public class SecurityConfig {

    @Bean
    public SecurityFilterChain securityFilterChain(HttpSecurity http) throws Exception {
        http
                .authorizeHttpRequests(auth -> auth.anyRequest().permitAll())
                .sessionManagement(s -> s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .csrf(csrf -> csrf.disable())
                .httpBasic(basic -> basic.disable())
                .formLogin(form -> form.disable())
                .logout(logout -> logout.disable())
                .requestCache(cache -> cache.disable())
                .headers(headers -> headers
                        .httpStrictTransportSecurity(hsts -> hsts
                                .includeSubDomains(true)
                                .maxAgeInSeconds(31_536_000))
                        .contentSecurityPolicy(csp -> csp
                                .policyDirectives("default-src 'none'; frame-ancestors 'none'")));
        return http.build();
    }
}
