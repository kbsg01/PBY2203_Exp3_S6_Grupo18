package com.bancoxyz.bff.web.transferencia.controller;

import com.bancoxyz.bff.web.exception.AccesoNoAutorizadoException;
import com.bancoxyz.bff.web.security.JwtAuthFilter;
import com.bancoxyz.bff.web.transferencia.client.TransferenciaCoreClient;
import com.bancoxyz.bff.web.transferencia.client.TransferenciaProducer;
import com.bancoxyz.bff.web.transferencia.dto.TransferenciaEstadoCoreDTO;
import com.bancoxyz.bff.web.transferencia.dto.TransferenciaSolicitadaEvent;
import com.bancoxyz.bff.web.transferencia.dto.TransferenciaWebRequest;
import com.bancoxyz.bff.web.transferencia.dto.TransferenciaWebResponse;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Optional;
import java.util.UUID;

/**
 * Nuevo caso de uso de la Semana 7: transferencia entre cuentas, modelado como saga por
 * coreografia (ver core-service, paquete {@code transferencia}). A diferencia de
 * {@link com.bancoxyz.bff.web.controller.CuentaWebController} (siempre sincronico, respuesta
 * inmediata), aqui la escritura es asincrona (202 Accepted + consulta de estado posterior) y la
 * lectura sigue siendo sincronica - la combinacion tipica de una arquitectura orientada a
 * eventos que igual necesita responder "como voy" bajo demanda.
 */
@RestController
@RequestMapping("/api/web")
public class TransferenciaWebController {

    private final TransferenciaProducer transferenciaProducer;
    private final TransferenciaCoreClient transferenciaCoreClient;

    public TransferenciaWebController(TransferenciaProducer transferenciaProducer, TransferenciaCoreClient transferenciaCoreClient) {
        this.transferenciaProducer = transferenciaProducer;
        this.transferenciaCoreClient = transferenciaCoreClient;
    }

    @PostMapping("/cuentas/{cuentaId}/transferencias")
    public ResponseEntity<TransferenciaWebResponse> solicitarTransferencia(
            @PathVariable long cuentaId,
            @Valid @RequestBody TransferenciaWebRequest request,
            HttpServletRequest httpRequest) {
        verificarPropietario(cuentaId, httpRequest);

        String transferenciaId = UUID.randomUUID().toString();
        transferenciaProducer.publicarSolicitud(new TransferenciaSolicitadaEvent(
                transferenciaId, cuentaId, request.cuentaDestino(), request.monto()));

        return ResponseEntity.status(HttpStatus.ACCEPTED).body(TransferenciaWebResponse.aceptada(transferenciaId));
    }

    @GetMapping("/transferencias/{transferenciaId}")
    public TransferenciaEstadoCoreDTO consultarEstado(@PathVariable String transferenciaId, HttpServletRequest httpRequest) {
        long cuentaAutenticada = cuentaDelToken(httpRequest);
        TransferenciaEstadoCoreDTO estado = transferenciaCoreClient.obtenerEstado(transferenciaId);
        if (estado.cuentaOrigen() != cuentaAutenticada) {
            throw new AccesoNoAutorizadoException("Su sesion no tiene acceso a esta transferencia.");
        }
        return estado;
    }

    private void verificarPropietario(long cuentaId, HttpServletRequest request) {
        if (cuentaDelToken(request) != cuentaId) {
            throw new AccesoNoAutorizadoException("Su sesion no tiene acceso a la cuenta " + cuentaId + ".");
        }
    }

    private long cuentaDelToken(HttpServletRequest request) {
        return (long) Optional.ofNullable(request.getAttribute(JwtAuthFilter.ATRIBUTO_CUENTA_ID))
                .orElseThrow(() -> new AccesoNoAutorizadoException("No hay una sesion valida."));
    }
}
