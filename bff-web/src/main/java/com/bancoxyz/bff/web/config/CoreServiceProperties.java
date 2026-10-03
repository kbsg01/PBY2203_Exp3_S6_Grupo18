package com.bancoxyz.bff.web.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "core-service")
public class CoreServiceProperties {

    /** URL base del backend generalizado (core-service), resuelta por nombre logico via Eureka. */
    private String baseUrl = "http://core-service";

    public String getBaseUrl() {
        return baseUrl;
    }

    public void setBaseUrl(String baseUrl) {
        this.baseUrl = baseUrl;
    }
}
