package com.bancoxyz.auth;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.autoconfigure.security.servlet.UserDetailsServiceAutoConfiguration;

/**
 * Servidor de autorizacion OAuth 2.0 del Banco XYZ (Semana 8).
 *
 * <p>Centraliza la emision de access tokens para la comunicacion servicio-a-servicio: cada BFF
 * se registra como un cliente confidencial distinto (ver {@code application.yml}) y obtiene, con
 * el flujo {@code client_credentials}, un JWT firmado con RS256 cuyo claim {@code scope} define
 * que puede hacer contra core-service. core-service ya no conoce ninguna clave compartida: solo
 * confia en la firma publicada en {@code /oauth2/jwks} (delegacion de seguridad).</p>
 *
 * <p>Se excluye {@link UserDetailsServiceAutoConfiguration} porque este servidor no autentica
 * personas (no hay login de usuarios finales aqui; eso sigue siendo responsabilidad de cada BFF
 * por canal), y sin la exclusion Spring Boot crearia un usuario en memoria con una contrasena
 * generada que nadie usa.</p>
 */
@SpringBootApplication(exclude = UserDetailsServiceAutoConfiguration.class)
public class AuthServerApplication {

    public static void main(String[] args) {
        SpringApplication.run(AuthServerApplication.class, args);
    }
}
