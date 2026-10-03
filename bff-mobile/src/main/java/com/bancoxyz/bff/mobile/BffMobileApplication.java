package com.bancoxyz.bff.mobile;

import com.bancoxyz.bff.mobile.config.CoreServiceProperties;
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
 * BFF Movil: backend dedicado a la app movil del Banco XYZ. Ver README.md para la
 * justificacion de por que este canal recibe respuestas deliberadamente reducidas.
 */
@SpringBootApplication
@EnableConfigurationProperties(CoreServiceProperties.class)
public class BffMobileApplication {

    public static void main(String[] args) {
        SpringApplication.run(BffMobileApplication.class, args);
    }

    /**
     * RestTemplate hacia core-service: resuelve "http://core-service" via Eureka (@LoadBalanced) y,
     * desde la Semana 8, agrega el access token OAuth 2.0 de este BFF en cada llamada (ver
     * {@link com.bancoxyz.bff.mobile.config.OAuth2ClientConfig}).
     */
    @Bean
    @LoadBalanced
    public RestTemplate restTemplate(RestTemplateBuilder builder, ClientHttpRequestInterceptor interceptorClientCredentials) {
        // Timeouts mas agresivos que en bff-web: una app movil en una red celular inestable
        // no deberia dejar al usuario esperando una respuesta que igual va a descartar.
        return builder
                .setConnectTimeout(Duration.ofSeconds(3))
                .setReadTimeout(Duration.ofSeconds(5))
                .additionalInterceptors(interceptorClientCredentials)
                .build();
    }
}
