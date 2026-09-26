package com.bancoxyz.bff.web.transferencia.dto;

import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;

/**
 * La cuenta ORIGEN no viaja en el body: se toma del {@code {cuentaId}} de la URL, que a su vez
 * ya fue verificado contra el JWT del llamante (ver {@code TransferenciaWebController}) - un
 * cliente autenticado solo puede transferir DESDE su propia cuenta, nunca desde otra.
 */
public record TransferenciaWebRequest(
        @NotNull Long cuentaDestino,
        @NotNull @Positive Double monto
) {
}
