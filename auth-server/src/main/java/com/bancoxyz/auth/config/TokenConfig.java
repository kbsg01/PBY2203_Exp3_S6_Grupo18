package com.bancoxyz.auth.config;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.oauth2.server.authorization.OAuth2TokenType;
import org.springframework.security.oauth2.server.authorization.token.JwtEncodingContext;
import org.springframework.security.oauth2.server.authorization.token.OAuth2TokenCustomizer;

@Configuration
public class TokenConfig {

    private static final Logger log = LoggerFactory.getLogger(TokenConfig.class);

    /**
     * Se ejecuta justo antes de firmar cada access token. No modifica los claims estandar (sub,
     * aud, scope, iss, exp): solo deja una linea de log auditable por cada token emitido (que
     * cliente lo pidio y con que scopes), util como evidencia del flujo OAuth 2.0 y como traza
     * de seguridad. Nunca se loguea el token en si.
     */
    @Bean
    public OAuth2TokenCustomizer<JwtEncodingContext> auditoriaDeTokens() {
        return context -> {
            if (OAuth2TokenType.ACCESS_TOKEN.equals(context.getTokenType())) {
                log.info("Access token emitido: cliente={} grant={} scopes={}",
                        context.getRegisteredClient().getClientId(),
                        context.getAuthorizationGrantType().getValue(),
                        context.getAuthorizedScopes());
            }
        };
    }
}
