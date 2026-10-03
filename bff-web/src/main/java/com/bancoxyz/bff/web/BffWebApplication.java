package com.bancoxyz.bff.web;

import com.bancoxyz.bff.web.config.CoreServiceProperties;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.boot.web.client.RestTemplateBuilder;
import org.springframework.cloud.client.loadbalancer.LoadBalanced;
import org.springframework.context.annotation.Bean;
import org.springframework.http.client.ClientHttpRequestInterceptor;
import org.springframework.web.client.RestTemplate;

import java.time.Duration;

/**
 * BFF Web: backend dedicado exclusivamente al canal de navegador (aplicacion de escritorio del
 * Banco XYZ). Ver README.md para la justificacion completa de por que este canal recibe datos
 * completos y sin recortar, a diferencia de bff-mobile y bff-atm.
 */
@SpringBootApplication
@EnableConfigurationProperties(CoreServiceProperties.class)
public class BffWebApplication {

    public static void main(String[] args) {
        SpringApplication.run(BffWebApplication.class, args);
    }

    /**
     * RestTemplate hacia core-service: resuelve "http://core-service" via Eureka (@LoadBalanced) y,
     * desde la Semana 8, agrega el access token OAuth 2.0 de este BFF en cada llamada (ver
     * {@link com.bancoxyz.bff.web.config.OAuth2ClientConfig}).
     */
    @Bean
    @LoadBalanced
    public RestTemplate restTemplate(RestTemplateBuilder builder, ClientHttpRequestInterceptor interceptorClientCredentials) {
        // Timeouts generosos: el canal web tolera respuestas algo mas lentas a cambio de
        // recibir el detalle completo (historial de movimientos sin paginar en el peor caso).
        return builder
                .setConnectTimeout(Duration.ofSeconds(5))
                .setReadTimeout(Duration.ofSeconds(10))
                .additionalInterceptors(interceptorClientCredentials)
                .build();
    }
}
