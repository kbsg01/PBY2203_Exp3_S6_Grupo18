package com.bancoxyz.bff.mobile.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpRequest;
import org.springframework.http.client.ClientHttpRequestExecution;
import org.springframework.http.client.ClientHttpRequestInterceptor;
import org.springframework.http.client.ClientHttpResponse;
import org.springframework.security.oauth2.client.AuthorizedClientServiceOAuth2AuthorizedClientManager;
import org.springframework.security.oauth2.client.OAuth2AuthorizeRequest;
import org.springframework.security.oauth2.client.OAuth2AuthorizedClient;
import org.springframework.security.oauth2.client.OAuth2AuthorizedClientManager;
import org.springframework.security.oauth2.client.OAuth2AuthorizedClientProviderBuilder;
import org.springframework.security.oauth2.client.OAuth2AuthorizedClientService;
import org.springframework.security.oauth2.client.registration.ClientRegistrationRepository;

import java.io.IOException;

/**
 * bff-mobile como <b>cliente OAuth 2.0</b> de auth-server (Semana 8), flujo {@code client_credentials}.
 *
 * <p>Antes de cada llamada a core-service, {@link #interceptorClientCredentials} pide al
 * {@link OAuth2AuthorizedClientManager} un access token para el registro {@code core-service}
 * (ver {@code spring.security.oauth2.client.registration.core-service} en
 * config-repo/bff-mobile.yml) y lo agrega como {@code Authorization: Bearer ...}. El manager cachea
 * el token y solo vuelve a pedir uno nuevo a auth-server cuando esta por expirar (60 s antes),
 * asi que no se hace un round-trip a auth-server por cada peticion de negocio.</p>
 *
 * <p>Se usa {@link AuthorizedClientServiceOAuth2AuthorizedClientManager} (y no el manager
 * "por request" por defecto) porque el token pertenece al BFF como servicio, no a la sesion
 * HTTP del usuario final: funciona igual dentro y fuera de una peticion web.</p>
 */
@Configuration
public class OAuth2ClientConfig {

    /** Id del registro OAuth2 del cliente (spring.security.oauth2.client.registration.core-service). */
    public static final String REGISTRO_CORE_SERVICE = "core-service";

    @Bean
    public OAuth2AuthorizedClientManager authorizedClientManager(
            ClientRegistrationRepository clientRegistrationRepository,
            OAuth2AuthorizedClientService authorizedClientService) {
        var manager = new AuthorizedClientServiceOAuth2AuthorizedClientManager(
                clientRegistrationRepository, authorizedClientService);
        manager.setAuthorizedClientProvider(OAuth2AuthorizedClientProviderBuilder.builder()
                .clientCredentials()
                .build());
        return manager;
    }

    @Bean
    public ClientHttpRequestInterceptor interceptorClientCredentials(OAuth2AuthorizedClientManager manager) {
        return new ClientHttpRequestInterceptor() {
            @Override
            public ClientHttpResponse intercept(HttpRequest request, byte[] body, ClientHttpRequestExecution execution)
                    throws IOException {
                OAuth2AuthorizedClient cliente = manager.authorize(OAuth2AuthorizeRequest
                        .withClientRegistrationId(REGISTRO_CORE_SERVICE)
                        .principal("bff-mobile")
                        .build());
                if (cliente == null) {
                    throw new IllegalStateException("No se pudo obtener un access token de auth-server para bff-mobile.");
                }
                request.getHeaders().setBearerAuth(cliente.getAccessToken().getTokenValue());
                return execution.execute(request, body);
            }
        };
    }
}
