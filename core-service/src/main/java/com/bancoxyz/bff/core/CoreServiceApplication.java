package com.bancoxyz.bff.core;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * Punto de entrada del "backend generalizado" del Banco XYZ.
 *
 * <p>Este servicio consolida, en un unico modelo de dominio consultable ({@link
 * com.bancoxyz.bff.core.model.Cuenta} + {@link com.bancoxyz.bff.core.model.Movimiento}), dos
 * fuentes de datos legacy que hasta ahora vivian aisladas en procesos batch independientes
 * (ver el proyecto Exp1 de este mismo curso): {@code intereses.csv} (maestro de cuentas: titular,
 * saldo, edad, tipo de cuenta) y {@code cuentas_anuales.csv} (historial de movimientos por
 * cuenta). Es exactamente el tipo de "backend generalizado" descrito en la guia de la semana 4:
 * un unico servicio que, sin el patron BFF, tendria que exponer directamente sus datos completos
 * a los tres canales (web, movil, cajero), obligando a cada frontend a filtrar y transformar la
 * informacion por su cuenta.</p>
 *
 * <p><b>Importante:</b> este servicio NUNCA es consumido directamente por un frontend. Solo los
 * tres BFF (bff-web, bff-mobile, bff-atm) lo consumen, autenticandose desde la Semana 8 con un
 * access token OAuth 2.0 emitido por auth-server (ver
 * {@link com.bancoxyz.bff.core.config.SecurityConfig}). En una topologia de red real, ademas de
 * esa validacion, este servicio viviria en una subred privada sin exposicion publica (en
 * docker-compose.yaml solo se publica en 127.0.0.1).</p>
 */
@SpringBootApplication
public class CoreServiceApplication {

    public static void main(String[] args) {
        SpringApplication.run(CoreServiceApplication.class, args);
    }
}
