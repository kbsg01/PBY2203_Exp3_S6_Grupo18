# Banco XYZ — Backend for Frontend (BFF) + Spring Cloud

**Curso:** Desarrollo Backend III (PBY2203) — Duoc UC
**Autor:** Karla Santibáñez Gutiérrez

- **Base del proyecto (Exp2, Semana 4 — actividad formativa, grupal):** Grupo 18: Karla Santibañez Gutierrez - Fernando Fuentes Allende.
- **Exp2, Semana 5 (actividad sumativa, individual):** implementación del patrón BFF con HTTPS (secciones 1 a 10 de este documento).
- **Exp3, Semana 6 (esta entrega, actividad formativa):** "Implementando microservicios y seguridad en la nube con Spring Cloud" — Config Server, Service Discovery (Eureka) y tolerancia a fallos (Circuit Breaker) agregados sobre la misma base de código (ver sección 11).

## 1. Objetivo del proyecto

Implementar el patrón arquitectónico **Backend for Frontend (BFF)** para el sistema del Banco XYZ, creando un backend personalizado para cada tipo de cliente —**web**, **móvil** y **cajero automático**— que optimice la comunicación y adapte los datos a las necesidades reales de cada canal, en lugar de forzar a un único backend genérico a servir a los tres por igual. Esta actividad de la Semana 5 continúa el proyecto de la Semana 4 y agrega, como requisito nuevo, una configuración segura de cada BFF que incluye **HTTPS** con certificados.

Los datos provienen del mismo dataset legacy usado en la actividad Exp1 de este curso: [`bank_legacy_data`](https://github.com/KariVillagran/bank_legacy_data) (carpeta `data/semana_3`), reutilizando `intereses.csv` (maestro de cuentas) y `cuentas_anuales.csv` (historial de movimientos).

## 2. ¿Qué es el patrón BFF y por qué se eligió esta solución?

Un **patrón de diseño/arquitectónico** es una solución probada para un problema recurrente del desarrollo de software. El problema que resuelve **Backend for Frontend** es concreto: cuando varios tipos de cliente (un navegador de escritorio, una app móvil, un cajero automático) consumen el mismo backend, cada uno necesita datos distintos, en formatos distintos, con requisitos de seguridad distintos y con distinta tolerancia a la latencia y al peso de la respuesta. Un único backend "genérico" que intente satisfacer a los tres termina, con el tiempo, acumulando parámetros condicionales, ramas de código específicas por cliente y una superficie de autenticación mezclada — exactamente el escenario descrito en la guía de aprendizaje de esta semana ("Contexto de origen").

BFF resuelve esto invirtiendo el problema: en lugar de un backend que se adapta a todos, se construye **un backend dedicado por cada frontend**, que conoce exactamente las necesidades de su canal y expone solo lo que ese canal necesita. La transformación y optimización de datos ocurre en el BFF, no en el frontend ni en un backend centralizado que no puede permitirse esa especialización.

### 2.1 Análisis de la estrategia de implementación (instrucción específica N.º 1)

La guía de la semana describe tres estrategias no excluyentes para implementar BFF:

1. **Backends independientes por cada tipo de cliente**: un servicio desplegable por separado por canal, con su propio repositorio/ciclo de vida.
2. **Diseño de endpoints personalizados**: un mismo servicio, con rutas distintas por cliente (`/web/...`, `/mobile/...`).
3. **Aprovechar microservicios y delegar funciones al BFF**: el BFF como capa que combina y resume respuestas de microservicios existentes.

Para este proyecto se analizaron las tres a la luz de dos restricciones explícitas de las instrucciones específicas: *"Cada cliente deberá tener su propio Backend"* y *"Gestionar autenticación y autorización específicas para cada canal"*. La estrategia de **endpoints personalizados sobre un único servicio** queda descartada de inmediato: un solo proceso Spring Boot no puede tener "su propio backend" por canal en el sentido que piden las instrucciones, y mezclar tres esquemas de autenticación distintos (JWT de 30 minutos, JWT de 5 minutos, sesión opaca de 2 minutos) dentro de una misma aplicación habría recreado exactamente el backend monolítico y sobrecargado que el patrón BFF busca evitar.

Por eso, este proyecto adopta una **combinación deliberada de las estrategias 1 y 3**:

- **Estrategia 1 (backends independientes)** para satisfacer el requisito explícito: existen **cuatro aplicaciones Spring Boot completamente autónomas** —`core-service`, `bff-web`, `bff-mobile`, `bff-atm`—, cada una con su propio `pom.xml`, su propio `main()`, su propio puerto y su propio ciclo de vida. Ninguna depende de que las demás estén compiladas para arrancar.
- **Estrategia 3 (delegar en un backend generalizado)** para evitar el problema opuesto: si cada BFF leyera los CSV legacy y reimplementara su propia lógica de validación de datos, la lógica de negocio (qué es una cuenta válida, cómo se calcula el interés, etc.) quedaría triplicada y desincronizada. En su lugar, `core-service` consolida los datos legacy una sola vez y los expone mediante una API interna; los tres BFF son clientes de esa API, y cada uno decide **qué subconjunto de esos datos reenviar, en qué formato, y bajo qué reglas de autenticación**.

Esta combinación es, además, coherente con lo que la propia guía advierte: "el BFF puede funcionar sobre microservicios, gestionando datos específicos para cada frontend desde su propio backend dedicado". `core-service` cumple aquí el papel del "backend/microservicio" sobre el que operan los tres BFF.

## 3. Arquitectura general

```
                    ┌──────────────┐        ┌──────────────┐        ┌──────────────┐
                    │  Navegador   │        │   App Móvil  │        │Cajero Automát.│
                    │   (Web)      │        │              │        │    (ATM)      │
                    └──────┬───────┘        └──────┬───────┘        └──────┬───────┘
                           │ HTTPS/JSON            │ HTTPS/JSON            │ HTTPS/JSON
                           │ JWT 30 min            │ JWT 5 min             │ Sesión opaca 2 min
                     ┌─────▼──────┐          ┌─────▼──────┐          ┌─────▼──────┐
                     │  bff-web   │          │ bff-mobile │          │  bff-atm   │
                     │ :8081 (TLS)│          │ :8082 (TLS)│          │ :8083 (TLS)│
                     └─────┬──────┘          └─────┬──────┘          └─────┬──────┘
                           │                        │                       │
                           │ HTTP interno + X-Internal-Api-Key              │
                           │ (solo los BFF la conocen; sin TLS: tráfico     │
                           │  entre procesos internos, no expuesto)         │
                           └────────────────┬───────┴───────────────────────┘
                                            ▼
                                  ┌───────────────────┐
                                  │   core-service     │   ← backend generalizado,
                                  │   :8080 (HTTP)      │     NUNCA expuesto a un frontend
                                  │ (consolida legacy:  │
                                  │  intereses.csv +    │
                                  │  cuentas_anuales.csv)│
                                  └────────────────────┘
```

Ningún frontend llama jamás directamente a `core-service`. La única forma de acceder a sus datos es a través de uno de los tres BFF, cada uno de los cuales conoce la clave interna compartida (`X-Internal-Api-Key`) que `core-service` exige en toda petición. Esto materializa, a nivel de código, el principio central del patrón: **el backend generalizado no sabe ni le importa qué frontend existe**; son los BFF quienes conocen a sus clientes.

Con la incorporación de HTTPS en esta actividad, el diagrama distingue explícitamente dos tramos de comunicación con requisitos de seguridad distintos:

- **Cliente ↔ BFF (`bff-web`, `bff-mobile`, `bff-atm`):** ahora viaja sobre **HTTPS/TLS**, porque es el tramo expuesto — el que efectivamente cruza una red que un atacante podría interceptar (navegador, app móvil, red del cajero).
- **BFF ↔ `core-service`:** se mantiene sobre **HTTP plano**, deliberadamente. `core-service` nunca se expone a ningún frontend; solo lo consumen los tres BFF, en el mismo entorno de ejecución, autenticados con `X-Internal-Api-Key`. Los detalles de esta decisión y su justificación académica se documentan en la sección 5.1 y se listan también en la sección 9 junto con el resto de las simplificaciones del proyecto.

## 4. Personalización de la información por canal (evidencia del criterio "Personaliza la información según las necesidades de cada frontend")

Los tres BFF consultan exactamente la misma fuente de verdad (`core-service`) pero devuelven respuestas radicalmente distintas para la misma cuenta:

| | **BFF Web** (`GET /api/web/cuentas/101`) | **BFF Móvil** (`GET /api/mobile/cuentas/101/resumen`) | **BFF Cajero** (`GET /api/atm/cuentas/101/saldo`) |
| --- | --- | --- | --- |
| Nombre del titular | Sí | No | No |
| Edad del titular | Sí | No | No |
| Saldo | Sí | Sí | Sí (único dato, además del propio endpoint) |
| Tasa de interés e interés proyectado | Sí | No | No |
| Totales agregados (depósitos, retiros, compras) | Sí | No | No |
| Historial de movimientos | Completo, filtrable por tipo/fecha | Solo los últimos 3 | Ninguno |
| Operaciones permitidas | Solo lectura | Solo lectura | Lectura de saldo **y retiro de efectivo** |
| Tamaño aproximado de la respuesta | El mayor de los tres (pensado para tablas y gráficos de escritorio) | Reducido a propósito (ahorra ancho de banda móvil) | El más pequeño posible (pantalla de cajero, mínima exposición de datos personales) |

Esta tabla no es una descripción de intenciones: es literalmente el comportamiento de `CuentaWebResponse`, `CuentaMobileResumenResponse` y `SaldoResponse` (ver sección 6). Cada clase documenta, en su propio javadoc, por qué omite o incluye cada campo.

## 5. Autenticación y autorización específicas por canal

| Canal | Credencial | Mecanismo | Duración de sesión | Razonamiento |
| --- | --- | --- | --- | --- |
| **Web** | N.º de cuenta + nombre del titular | JWT firmado (HS256), claim con nombre | 30 minutos | Un usuario de escritorio puede dejar la sesión abierta mientras revisa varias pantallas; el riesgo de robo del dispositivo es menor que en un teléfono. |
| **Móvil** | N.º de cuenta + PIN de 4 dígitos | JWT firmado (HS256), sin nombre en el claim | 5 minutos | Un teléfono se pierde/roba con más frecuencia; se fuerza a renovar el token seguido. Un PIN es la credencial habitual de una app bancaria móvil. |
| **Cajero** | N.º de tarjeta + PIN (dos factores) | Token de sesión **opaco**, guardado en el servidor, invalidado automáticamente tras un retiro exitoso | 2 minutos, y de un solo uso para operaciones críticas | Es la operación de más riesgo (dinero en efectivo, en un espacio público); un token opaco permite revocación inmediata del lado del servidor, algo que un JWT autocontenido no ofrece sin infraestructura adicional (lista de revocación). |

> **Nota importante sobre las credenciales:** el dataset legacy del Banco XYZ no incluye contraseñas, PIN ni números de tarjeta reales. Para poder demostrar un flujo de autenticación end-to-end verificable, este proyecto genera credenciales **sintéticas y deterministas** a partir del `cuentaId` (ver `PinGenerator` y `TarjetaGenerator`), documentado explícitamente en el código como una simplificación académica. En un sistema real, estas credenciales se almacenarían hasheadas en un servicio de identidad dedicado, nunca derivadas matemáticamente.

### 5.1 Seguridad de transporte (HTTPS)

Como continuación de la actividad de la Semana 4, esta entrega agrega **HTTPS** a la configuración de seguridad de los tres BFF (`bff-web`, `bff-mobile`, `bff-atm`), de modo que el tramo de red efectivamente expuesto a un cliente externo —navegador, app móvil o cajero— viaje cifrado.

**Certificados.** Cada BFF tiene su propio keystore **PKCS12 autofirmado**, generado con `keytool` y empaquetado dentro del propio módulo (`src/main/resources/`), no en un almacén externo:

| Módulo | Archivo de keystore | Alias |
| --- | --- | --- |
| `bff-web` | `bff-web-keystore.p12` | `bffweb` |
| `bff-mobile` | `bff-mobile-keystore.p12` | `bffmobile` |
| `bff-atm` | `bff-atm-keystore.p12` | `bffatm` |

Comando usado para generar cada uno (ejemplo con `bff-web`):

```bash
keytool -genkeypair -alias bffweb -keyalg RSA -keysize 2048 -validity 825 \
  -storetype PKCS12 -keystore bff-web-keystore.p12 \
  -dname "CN=localhost, OU=BancoXYZ, O=DuocUC, L=Santiago, ST=RM, C=CL"
```

Y la configuración correspondiente agregada en el `application.yml` de cada módulo:

```yaml
server:
  ssl:
    enabled: true
    key-store: classpath:bff-web-keystore.p12
    key-store-type: PKCS12
    key-store-password: "keystore-canal-web-banco-xyz-no-usar-en-produccion-2026"
    key-alias: bffweb
```

(`bff-mobile` y `bff-atm` siguen el mismo esquema, cambiando el nombre de archivo, el alias y la contraseña por su canal correspondiente: `...-canal-movil-...` y `...-canal-atm-...`.)

**Por qué `core-service` queda deliberadamente fuera del alcance de TLS.** `core-service` sigue sirviendo en **HTTP plano** por el puerto 8080. Esto no es un descuido: como se explica en la sección 3, `core-service` **nunca se expone a ningún frontend**; sus únicos clientes son los tres BFF, que lo consumen internamente y se autentican con el header `X-Internal-Api-Key`. Cifrar ese tramo interno habría exigido gestionar un cuarto keystore y un cliente HTTP TLS en cada BFF solo para proteger tráfico que, en este proyecto académico, corre en el mismo entorno de ejecución y nunca cruza una red no confiable. Esta decisión se documenta también junto con el resto de las simplificaciones académicas del proyecto (sección 9).

**Cómo probar cada BFF con HTTPS.**

- Con `curl`, usando `-k` (o `--insecure`) porque el certificado es autofirmado y no fue emitido por una CA reconocida por el sistema:

  ```bash
  curl -k https://localhost:8081/api/web/auth/login -X POST -H "Content-Type: application/json" -d '{"cuentaId": 101, "nombre": "John Doe"}'
  curl -k https://localhost:8082/api/mobile/auth/login -X POST -H "Content-Type: application/json" -d '{"cuentaId": 101, "pin": "7373"}'
  curl -k https://localhost:8083/api/atm/sesion -X POST -H "Content-Type: application/json" -d '{"numeroTarjeta": "4915000000000101", "pin": "7373"}'
  ```

- Desde un navegador, al visitar `https://localhost:808x/...` este mostrará una advertencia de certificado no confiable (esperable con un certificado autofirmado); se debe agregar manualmente una excepción de seguridad para el certificado y continuar.

**Advertencia de producción.** Tanto el uso de un certificado autofirmado como el hecho de que las contraseñas de los keystores estén en texto plano dentro de `application.yml` son simplificaciones deliberadas para este entorno académico. En un sistema real de producción, el certificado sería emitido por una **CA (autoridad certificadora) reconocida** —pública (Let's Encrypt, DigiCert, etc.) o interna de la organización— y las contraseñas de los keystores, al igual que los secretos JWT ya usados en el proyecto, vivirían en un **gestor de secretos** (Vault, AWS Secrets Manager, Azure Key Vault, etc.), nunca en un archivo de configuración versionado en el repositorio.

## 6. Organización del código (evidencia del criterio "Organiza su código según la estrategia de implementación elegida")

La estructura de carpetas refleja directamente la estrategia elegida en la sección 2.1: **cuatro proyectos Maven independientes**, agregados solo por comodidad de build bajo un `pom.xml` raíz (`packaging=pom`), pero deployables por separado:

```text
banco-xyz-bff/
├── pom.xml                        (agregador, NO es el padre de Spring Boot de los módulos)
├── core-service/                  (backend generalizado — NUNCA expuesto a un frontend, HTTP plano)
│   └── src/main/java/com/bancoxyz/bff/core/
│       ├── model/                 Cuenta, Movimiento (dominio)
│       ├── repository/            CuentaRepository (repositorio en memoria)
│       ├── service/               CargaDatosService (carga y valida los CSV al iniciar)
│       ├── util/                  FechaFlexibleParser
│       ├── config/                InternalApiKeyFilter (exige X-Internal-Api-Key)
│       ├── controller/            CuentaInternalController (API interna, sin personalizar)
│       ├── dto/                   CuentaInternalDTO, MovimientoDTO, ActualizarSaldoRequest
│       └── exception/             manejo centralizado de errores
├── bff-web/                       (canal navegador — datos completos, HTTPS)
│   └── src/main/java/com/bancoxyz/bff/web/
│       ├── client/                CoreServiceClient + DTOs espejo de core-service
│       ├── security/              JwtService (30 min), JwtAuthFilter
│       ├── controller/            AuthController, CuentaWebController
│       ├── dto/                   CuentaWebResponse (respuesta rica y agregada)
│       └── exception/
│   └── src/main/resources/        application.yml (server.ssl) + bff-web-keystore.p12
├── bff-mobile/                    (canal app móvil — datos esenciales, HTTPS)
│   └── src/main/java/com/bancoxyz/bff/mobile/     (misma organización interna que bff-web)
│       ├── security/              JwtService (5 min), PinGenerator
│       └── dto/                   CuentaMobileResumenResponse (respuesta reducida)
│   └── src/main/resources/        application.yml (server.ssl) + bff-mobile-keystore.p12
├── bff-atm/                       (canal cajero — operaciones críticas, HTTPS)
│   └── src/main/java/com/bancoxyz/bff/atm/        (misma organización interna)
│       ├── security/              SesionAtmService (token opaco), TarjetaGenerator, PinGenerator
│       ├── controller/            SesionController, CuentaAtmController (saldo + retiro)
│       └── dto/                   SaldoResponse (la respuesta más reducida del proyecto)
│   └── src/main/resources/        application.yml (server.ssl) + bff-atm-keystore.p12
├── scripts/probar_apis.sh         Prueba end-to-end de los 4 servicios (HTTPS + curl -k para los BFF, HTTP para core-service)
└── .github/workflows/evidencia-ejecucion.yml   Evidencia de ejecución real (ver sección 8)
```

Cada módulo repite deliberadamente el mismo esqueleto interno (`client/`, `security/`, `controller/`, `dto/`, `exception/`): esto no es duplicación accidental, es la consecuencia directa de la estrategia elegida — si `bff-mobile` tuviera una estructura completamente distinta a `bff-web`, sería una señal de que en realidad no se está tratando a cada canal como un backend independiente y autónomo, sino como variaciones ad-hoc de un mismo código base.

### 6.1 Por qué no se comparte código (un `common`) entre los tres BFF

Cada BFF define su propia copia de `CoreServiceProperties`, sus propios DTOs espejo (`CuentaCoreDTO`, `MovimientoCoreDTO`) y, en el caso de `bff-mobile`/`bff-atm`, su propia copia de `PinGenerator`. Esto es intencional: la estrategia de "backends independientes" busca que cada BFF pueda evolucionar, desplegarse y versionarse sin coordinar cambios con los demás. Introducir una librería compartida recrearía un acoplamiento oculto entre los tres canales — si un cambio en esa librería obligara a recompilar y redesplegar los tres BFF a la vez, ya no serían realmente independientes. El único acoplamiento real y deliberado del proyecto es el contrato HTTP/JSON de `core-service`, documentado y estable. Esta misma independencia se refleja ahora también en la configuración de HTTPS: cada BFF tiene su propio keystore, su propio alias y su propia contraseña, sin un almacén de certificados compartido entre los tres.

## 7. Cómo ejecutar el proyecto

### 7.1 Requisitos

- JDK 21
- Maven 3.9+ (o el wrapper, si se agrega)
- Un puerto libre 8080–8083

### 7.2 Compilar y ejecutar localmente

```bash
# Desde la raíz del proyecto, compila los 6 módulos:
mvn -DskipTests package

# En 6 terminales distintas (el orden importa, ver sección 11.2 para el detalle):
java -jar config-server/target/config-server.jar
java -jar eureka-server/target/eureka-server.jar
java -jar core-service/target/core-service.jar
java -jar bff-web/target/bff-web.jar
java -jar bff-mobile/target/bff-mobile.jar
java -jar bff-atm/target/bff-atm.jar

# En una séptima terminal, una vez los 6 procesos estén arriba:
bash scripts/probar_apis.sh
```

Con HTTPS ya configurado, los tres BFF quedan disponibles en:

- `https://localhost:8081` (`bff-web`)
- `https://localhost:8082` (`bff-mobile`)
- `https://localhost:8083` (`bff-atm`)

mientras que `core-service` se mantiene en `http://localhost:8080` (tráfico interno, ver sección 5.1). El script `scripts/probar_apis.sh` ya refleja esto: llama a los tres BFF por `https://` (con `curl -k`, dado el certificado autofirmado) y a `core-service` por `http://`.

### 7.3 Credenciales de demostración

Calculadas a partir del dataset real (`intereses.csv`, semana 3) tras la validación y el upsert que aplica `CargaDatosService` (idéntico criterio, documentado y verificado con evidencia real, al usado en el proyecto Exp1 de este curso):

| cuentaId | Titular | Tipo | Saldo | PIN (móvil/cajero) | N.º de tarjeta (cajero) |
| --- | --- | --- | --- | --- | --- |
| 101 | John Doe | préstamo | 10.000 | 7373 | 4915000000000101 |
| 105 | Steve Rogers | ahorro | 10.000 | 7665 | 4915000000000105 |
| 108 | Diana Prince | ahorro | 10.000 | 7884 | 4915000000000108 |
| 118 | Jane Smith | ahorro | 12.000 | 8614 | 4915000000000118 |

(Login web: `{"cuentaId": <id>, "nombre": "<Titular>"}`. Login móvil: `{"cuentaId": <id>, "pin": "<PIN>"}`. Sesión de cajero: `{"numeroTarjeta": "<tarjeta>", "pin": "<PIN>"}`.)

## 8. Evidencia de ejecución

La evidencia de ejecución real se genera con **GitHub Actions** (`.github/workflows/evidencia-ejecucion.yml`). El workflow:

1. Compila los 4 módulos con Maven.
2. Levanta `core-service`, `bff-web`, `bff-mobile` y `bff-atm` como procesos reales, en ese orden, esperando activamente a que cada uno responda antes de continuar (los tres BFF ya arrancan con HTTPS habilitado).
3. Ejecuta `scripts/probar_apis.sh` contra los 4 servicios reales corriendo en el runner de GitHub.
4. Publica los logs de arranque de cada servicio y la salida completa de las pruebas como un artefacto descargable (`evidencias-ejecucion-bff`) en la pestaña **Actions** del repositorio, en la sección **Artifacts** del run correspondiente.

El script de pruebas (sección 7.2) ejercita, con datos reales, los cuatro flujos completos: rechazo de acceso directo a `core-service`, login y consulta completa en el canal web (incluyendo la verificación de que un token no puede acceder a la cuenta de otra persona), login y resumen reducido en el canal móvil, y el flujo completo de cajero (apertura de sesión, consulta de saldo, retiro exitoso, invalidación automática de la sesión tras el retiro, y rechazo de un retiro que excede el límite máximo por operación).

### 8.1 Evidencia de ejecución previa (03-09-2026) — corresponde a la versión sin HTTPS

El workflow se ejecutó exitosamente en GitHub Actions, con los 4 módulos compilando sin errores (`BUILD SUCCESS`) y los 4 servicios arrancando correctamente sobre datos legacy reales (`core-service` cargó 49 cuentas y 885 movimientos válidos desde los CSV). El script de pruebas (`evidencia06-pruebas-apis.log`) confirmó, contra las APIs reales corriendo en el runner, todos los comportamientos esperados:

- `core-service` rechaza (HTTP 403) cualquier llamada sin el header `X-Internal-Api-Key`, y responde con el dominio completo cuando la clave es correcta — el backend generalizado nunca queda expuesto directamente a un frontend.
- **BFF Web**: login exitoso, consulta de cuenta completa con agregados (tasa de interés, interés proyectado, totales por tipo de movimiento) e historial filtrable por tipo de movimiento; un token válido de la cuenta 101 recibe HTTP 403 al intentar consultar la cuenta 105 (autorización por titularidad funcionando).
- **BFF Móvil**: login con PIN determinista y respuesta deliberadamente reducida (saldo, tipo de cuenta y solo los últimos 3 movimientos, sin nombre ni edad del titular), evidenciando la personalización por canal frente al payload completo del canal Web.
- **BFF Cajero**: apertura de sesión con tarjeta + PIN, consulta de saldo mínima (sin historial ni datos personales), retiro de $1.000 exitoso, invalidación automática de la sesión inmediatamente después del retiro (HTTP 401 al reutilizarla) y rechazo correcto de un retiro que excede el límite máximo por operación.

Los 6 archivos de log generados por este run (`evidencia01-build.log` a `evidencia06-pruebas-apis.log`) quedan como artefacto descargable del run correspondiente en la pestaña Actions del repositorio.

> **Importante — pendiente antes de la entrega final:** esta corrida del 03-09-2026 corresponde a la versión del proyecto **previa a la incorporación de HTTPS** (los tres BFF respondían aún en `http://`). Con los keystores y la configuración TLS ya agregados al código, **falta ejecutar nuevamente el pipeline** (mediante un push al repositorio remoto, o una ejecución local equivalente de los mismos pasos) para regenerar los 6 logs de `evidencias/evidencia01` a `evidencia06` con los tres BFF respondiendo efectivamente sobre `https://`. Hasta que esa nueva corrida no exista, este README **no afirma** que el comportamiento HTTPS ya fue verificado end-to-end en CI — solo que la configuración fue implementada y puede probarse manualmente como se describe en la sección 5.1 y en la sección 7.2. Regenerar esta evidencia es un paso pendiente que debe completarse antes de la entrega final de la Semana 5.

## 9. Decisiones de diseño y simplificaciones (transparencia académica)

- **Persistencia en memoria, no una base de datos real.** El foco de esta actividad es el patrón BFF, no la capa de persistencia. `core-service` carga los CSV legacy en un repositorio en memoria al iniciar. Podría reemplazarse por PostgreSQL/JPA (como en el proyecto Exp1) sin que ningún BFF se entere: el contrato que consumen es la API HTTP de `core-service`, nunca su almacenamiento interno.
- **Consolidación de dos fuentes legacy en un solo dominio.** `intereses.csv` (maestro de cuentas) y `cuentas_anuales.csv` (historial de movimientos) eran, en el proyecto Exp1, dos procesos batch independientes sin relación directa entre sí. Para esta actividad se unifican bajo un mismo `cuentaId`, tal como exigiría un ejercicio real de modernización que consolida silos de datos legacy dispersos en un modelo de dominio único y consultable.
- **Credenciales sintéticas y deterministas**, ya documentadas en la sección 5, necesarias porque el dataset legacy no incluye contraseñas, PIN ni números de tarjeta.
- **Límite de reintentos/validación de datos al cargar CSV**: se reutiliza el mismo criterio de validación (tipo de cuenta soportado, edad 18–90, saldo no negativo, nombre no vacío/"Unknown") ya verificado con evidencia real en el proyecto Exp1, para no introducir criterios de calidad de datos nuevos y no probados.
- **HTTPS con certificado autofirmado, no emitido por una CA real**, y contraseñas de keystore en `application.yml` en texto plano (mismo patrón "no usar en producción" que ya seguían los secretos JWT del proyecto). Suficiente para demostrar el mecanismo de configuración de TLS en Spring Boot en un entorno académico local; en producción correspondería un certificado de una CA reconocida y las contraseñas en un gestor de secretos (ver sección 5.1).
- **`core-service` queda fuera del alcance de TLS**, deliberadamente: nunca se expone a un frontend, solo lo consumen los tres BFF internamente vía `X-Internal-Api-Key` (ver sección 5.1). Cifrar ese tramo interno no aportaba valor demostrable para el alcance de esta actividad y sí complejidad adicional (un cuarto keystore, clientes HTTP TLS en cada BFF).

## 10. Trazabilidad con la pauta de evaluación sumativa (Semana 5)

| Criterio de la pauta | Puntaje | Dónde se evidencia |
| --- | --- | --- |
| Implementa un BFF para cada canal | 20 pts | Secciones 2.1 y 3: cuatro aplicaciones Spring Boot independientes (`core-service`, `bff-web`, `bff-mobile`, `bff-atm`), cada una con su propio ciclo de vida, funcionando end-to-end (sección 8). |
| Optimiza respuestas y consumo de recursos por canal | 20 pts | Sección 4 (tabla comparativa de payloads por canal) + `CuentaWebResponse`, `CuentaMobileResumenResponse`, `SaldoResponse`, cada uno documentado en su javadoc respecto a qué omite y por qué. |
| Implementa autenticación y autorización por canal | 15 pts | Sección 5 (tabla de credencial/mecanismo/duración por canal: JWT 30 min en Web, JWT 5 min en Móvil, sesión opaca de un solo uso en Cajero) + verificación de autorización por titularidad (sección 8.1). |
| Configura el BFF de manera segura (HTTPS, certificados, tokens de autenticación/autorización) | 20 pts | Sección 5.1 (keystores PKCS12 autofirmados por BFF, configuración `server.ssl` en cada `application.yml`, exclusión razonada de `core-service` del alcance de TLS) junto con la sección 5 (tokens JWT y sesión opaca ya implementados desde la Semana 4). |
| Organiza el código fuente de manera que facilita la extensión del software de manera escalable | 15 pts | Sección 6 (estructura de módulos independientes, esqueleto interno replicado deliberadamente) + sección 6.1 (ausencia intencional de código compartido, para no acoplar el ciclo de vida de los tres BFF, incluyendo la independencia de sus keystores TLS). |
| Entrega los aspectos claves solicitados: código fuente, documentación (README) y evidencia de ejecución | 10 pts | Código fuente en los 4 módulos (sección 6); este README; evidencia de ejecución en `.github/workflows/evidencia-ejecucion.yml` y sección 8, con la advertencia explícita en 8.1 de que la re-ejecución con HTTPS activo queda pendiente antes de la entrega final. |

## 11. Spring Cloud: Config Server, Service Discovery y tolerancia a fallos (Exp3, Semana 6)

Esta sección documenta lo agregado sobre la base de las secciones 1–10 (que siguen describiendo fielmente la entrega de la Semana 5) para cumplir la actividad "Implementando microservicios y seguridad en la nube con Spring Cloud". No se modificó la lógica de negocio de ningún BFF ni de `core-service`: solo se centralizó su configuración, se reemplazaron las URLs fijas por descubrimiento de servicios, y se agregó tolerancia a fallos en las llamadas entre servicios.

### 11.1 Arquitectura actualizada

```
                              ┌──────────────────┐
                              │  config-server    │  :8888  (perfil native, config-repo/)
                              └─────────┬─────────┘
                                        │ spring.config.import (los 4 servicios de abajo)
                              ┌─────────▼─────────┐
                              │   eureka-server    │  :8761  (standalone, dashboard http://localhost:8761)
                              └─────────┬─────────┘
                                        │ registro (los 4 servicios de abajo)
     ┌──────────────┐        ┌─────────▼─────────┐        ┌──────────────┐
     │  bff-web     │◄──────►│                    │◄──────►│  bff-mobile  │
     │ :8081 (TLS)  │        │   Service Registry │        │ :8082 (TLS)  │
     └──────┬───────┘        │                    │        └──────┬───────┘
            │                └─────────┬─────────┘                │
            │                          │                           │
            │           ┌──────────────▼──────────────┐            │
            └──────────►│         bff-atm :8083 (TLS)   │◄──────────┘
                         └───────────────┬──────────────┘
                                         │
                    RestTemplate @LoadBalanced -> http://core-service
                    + Circuit Breaker (Resilience4j) con fallback 503
                                         ▼
                              ┌────────────────────┐
                              │   core-service      │  :8080 (HTTP interno)
                              └────────────────────┘
```

Los 3 BFF ya no apuntan a `http://localhost:8080`: resuelven `core-service` por su nombre lógico (`spring.application.name`) a través de Eureka + Spring Cloud LoadBalancer, y envuelven esa llamada con un Circuit Breaker que evita propagar errores crudos si `core-service` cae.

### 11.2 Cómo levantar los componentes nuevos

Orden de arranque (agrega dos pasos previos a los ya conocidos de la sección 7.2):

```bash
java -jar config-server/target/config-server.jar   # :8888, primero
java -jar eureka-server/target/eureka-server.jar    # :8761, segundo
java -jar core-service/target/core-service.jar      # :8080
java -jar bff-web/target/bff-web.jar                # :8081
java -jar bff-mobile/target/bff-mobile.jar          # :8082
java -jar bff-atm/target/bff-atm.jar                # :8083
```

Config Server sirve un perfil `native` (sin repositorio Git externo): las properties centralizadas viven en `config-server/src/main/resources/config-repo/*.yml`, un archivo por microservicio (`core-service.yml`, `bff-web.yml`, `bff-mobile.yml`, `bff-atm.yml`). Cada uno de los 4 servicios las importa automáticamente al iniciar vía `spring.config.import: optional:configserver:http://localhost:8888` en su propio `application.yml` (el prefijo `optional:` evita que el servicio falle al iniciar si, por alguna razón, config-server no está disponible — solo usaría los valores por defecto ya definidos localmente).

Para verificar manualmente qué properties centraliza cada servicio, con config-server ya arriba:

```bash
curl http://localhost:8888/core-service/default
curl http://localhost:8888/bff-web/default
```

### 11.3 Cómo verificar el registro en Eureka

Con los 6 servicios arriba, abrir `http://localhost:8761` en el navegador: el dashboard debe listar `CORE-SERVICE`, `BFF-WEB`, `BFF-MOBILE` y `BFF-ATM` en estado `UP`. Equivalente por línea de comandos:

```bash
curl -H "Accept: application/json" http://localhost:8761/eureka/apps
```

### 11.4 Comportamiento del Circuit Breaker (Resilience4j)

Los 3 `CoreServiceClient` (`bff-web`, `bff-mobile`, `bff-atm`) envuelven su llamada a `core-service` con `@CircuitBreaker(name = "coreService", fallbackMethod = ...)`. La configuración (idéntica en los 3 BFF, en su `application.yml`) usa una ventana de 10 llamadas, abre el circuito si al menos 5 llamadas registradas fallan en un 50% o más, y permanece abierto 10 segundos antes de pasar a semiabierto:

```yaml
resilience4j:
  circuitbreaker:
    instances:
      coreService:
        sliding-window-size: 10
        minimum-number-of-calls: 5
        failure-rate-threshold: 50
        wait-duration-in-open-state: 10s
```

Mientras el circuito está cerrado o semiabierto, un fallo puntual de `core-service` se traduce en un `CoreServiceNoDisponibleException` → **HTTP 503** con un mensaje claro, en vez de que el error crudo de `RestTemplate` (timeout, conexión rechazada) llegue al cliente. Los errores de negocio (`CuentaNoEncontradaException`, y en `bff-atm` también `SaldoInsuficienteException`) están excluidos del conteo de fallos (`ignore-exceptions`), para que un 404/409 legítimo no abra el circuito innecesariamente.

Para reproducirlo manualmente: con los 6 servicios arriba y tras un login exitoso en `bff-web`, detener el proceso de `core-service` y repetir la consulta `GET /api/web/cuentas/101` varias veces — las primeras respuestas reflejan el fallo de conexión real, y a partir de la quinta el circuito abre y todas las respuestas siguientes son un 503 inmediato y controlado (sin esperar el timeout del cliente HTTP). El script `scripts/probar_tolerancia_fallos.sh` automatiza esta demostración.

### 11.5 Trazabilidad con la pauta de evaluación formativa (Semana 6)

| Criterio de la pauta | Dónde se evidencia |
| --- | --- |
| Configura un servidor centralizado y correctamente integrado con al menos un microservicio | Sección 11.1–11.2: `config-server` (perfil `native`) sirve configuración a los 4 servicios (`core-service`, `bff-web`, `bff-mobile`, `bff-atm`), cada uno con `spring.config.import` apuntando a él. |
| Habilita un Service Discovery y registra correctamente tres microservicios | Sección 11.1 y 11.3: `eureka-server` standalone en `:8761`, con los 4 servicios registrados (supera el mínimo de 3 exigido). |
| Implementa 3 microservicios con tolerancia a fallos y sistema de autenticación | Sección 11.4: `bff-web`, `bff-mobile` y `bff-atm` agregan Circuit Breaker (Resilience4j) sobre su llamada a `core-service`, y cada uno ya cuenta con su propio sistema de autenticación (sección 5: JWT web/móvil, sesión opaca ATM). |
| Implementa un sistema de autenticación y autorización funcional | Sección 5 (ya implementado desde la Semana 5): JWT por canal + verificación de autorización por titularidad, sin cambios funcionales en esta entrega. |
