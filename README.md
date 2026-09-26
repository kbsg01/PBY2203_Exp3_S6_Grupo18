# Banco XYZ — Backend for Frontend (BFF) + Spring Cloud

**Curso:** Desarrollo Backend III (PBY2203) — Duoc UC

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

> **Nota:** esta corrida del 03-09-2026 corresponde a la versión del proyecto **previa a la incorporación de HTTPS** (los tres BFF respondían aún en `http://`) y se conserva aquí solo como referencia histórica del comportamiento funcional de los 4 flujos. El pipeline **ya fue re-ejecutado** después de agregar los keystores y la configuración TLS: la corrida vigente, con los tres BFF respondiendo efectivamente sobre `https://`, es la que se documenta en la sección 11.7 (evidencia actual, generada junto con la actividad de Semana 6), donde `evidencia03-bff-web.log`, `evidencia04-bff-mobile.log` y `evidencia05-bff-atm.log` confirman TLS activo con el keystore y alias correctos de cada servicio.

## 9. Decisiones de diseño y simplificaciones (transparencia académica)

- **Persistencia en memoria, no una base de datos real.** El foco de esta actividad es el patrón BFF, no la capa de persistencia. `core-service` carga los CSV legacy en un repositorio en memoria al iniciar. Podría reemplazarse por PostgreSQL/JPA (como en el proyecto Exp1) sin que ningún BFF se entere: el contrato que consumen es la API HTTP de `core-service`, nunca su almacenamiento interno.
- **Consolidación de dos fuentes legacy en un solo dominio.** `intereses.csv` (maestro de cuentas) y `cuentas_anuales.csv` (historial de movimientos) eran, en el proyecto Exp1, dos procesos batch independientes sin relación directa entre sí. Para esta actividad se unifican bajo un mismo `cuentaId`, tal como exigiría un ejercicio real de modernización que consolida silos de datos legacy dispersos en un modelo de dominio único y consultable.
- **Credenciales sintéticas y deterministas**, ya documentadas en la sección 5, necesarias porque el dataset legacy no incluye contraseñas, PIN ni números de tarjeta.
- **Límite de reintentos/validación de datos al cargar CSV**: se reutiliza el mismo criterio de validación (tipo de cuenta soportado, edad 18–90, saldo no negativo, nombre no vacío/"Unknown") ya verificado con evidencia real en el proyecto Exp1, para no introducir criterios de calidad de datos nuevos y no probados.
- **HTTPS con certificado autofirmado, no emitido por una CA real**, y contraseñas de keystore en `application.yml` en texto plano (mismo patrón "no usar en producción" que ya seguían los secretos JWT del proyecto). Suficiente para demostrar el mecanismo de configuración de TLS en Spring Boot en un entorno académico local; en producción correspondería un certificado de una CA reconocida y las contraseñas en un gestor de secretos (ver sección 5.1).
- **`core-service` queda fuera del alcance de TLS**, deliberadamente: nunca se expone a un frontend, solo lo consumen los tres BFF internamente vía `X-Internal-Api-Key` (ver sección 5.1). Cifrar ese tramo interno no aportaba valor demostrable para el alcance de esta actividad y sí complejidad adicional (un cuarto keystore, clientes HTTP TLS en cada BFF).

## 10. Trazabilidad con la pauta de evaluación sumativa (Semana 5)

> Esta sección documenta la entrega de la Semana 5 (Exp2 S5) tal como fue evaluada entonces, sin modificaciones. Para la trazabilidad con la pauta formativa de la Semana 6 (Config Server, Service Discovery, tolerancia a fallos), ver la sección 11.5.

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

### 11.6 Generar la evidencia de ejecución en local (Windows o Linux/macOS)

El workflow de CI (`.github/workflows/evidencia-ejecucion.yml`) y la ejecución local usan exactamente el mismo script, `scripts/generar_evidencia.sh`: compila los 6 módulos, levanta config-server, eureka-server, core-service y los 3 BFF en orden (esperando activamente a que cada uno responda), corre `scripts/probar_apis.sh`, captura el registro en Eureka, corre `scripts/probar_tolerancia_fallos.sh` (que detiene `core-service` a propósito para demostrar el circuit breaker) y al final detiene todos los procesos que él mismo levantó — incluso si algo falla a mitad de camino. Todos los logs quedan en `evidencias/` con el mismo esquema de nombres (`evidencia01-build.log` ... `evidencia08-circuit-breaker.log`).

**Requisitos:** JDK 21 (con `jps`, incluido en cualquier JDK completo), Maven, `curl`, `jq`, y los puertos 8080-8083, 8761 y 8888 libres. En Windows se ejecuta con **Git Bash** (el mismo que ya usan `probar_apis.sh` y `probar_tolerancia_fallos.sh`); en Linux/macOS corre en cualquier bash nativo. El script detecta el sistema operativo automáticamente para detener los procesos de forma confiable en ambos casos (en Windows usa `taskkill`, porque el `kill` de Git Bash no siempre termina un proceso Java nativo aunque no reporte error).

```bash
bash scripts/generar_evidencia.sh                          # compila y corre todo el flujo
bash scripts/generar_evidencia.sh --skip-build              # reusa los jars ya compilados
bash scripts/generar_evidencia.sh --skip-tolerancia-fallos  # no mata core-service al final
```

### 11.7 Evidencia vigente y ajuste de temporización (registro en Eureka)

Los 8 logs de `evidencias/` (`evidencia01-build.log` a `evidencia08-circuit-breaker.log`) ya reflejan el proyecto completo con Config Server, Eureka y Circuit Breaker: los 6 módulos compilan (`BUILD SUCCESS`), los 3 BFF arrancan con TLS activo (mismo keystore/alias por servicio que en la Semana 5) y `evidencia06-pruebas-apis.log` confirma los 4 flujos end-to-end.

En una corrida real de este proyecto se detectó que el `sleep 8` fijo que usaba `generar_evidencia.sh` antes de correr las pruebas no siempre alcanzaba: el registro de un servicio en Eureka (y la propagación de ese registro a la cache local de `@LoadBalanced RestTemplate` de cada BFF) es asíncrono, y puede tardar más que un HTTP health-check exitoso. Esto se manifestó de dos formas en la evidencia ya committeada:

- `evidencia07-eureka-apps.log` (la foto de `/eureka/apps`) mostraba solo 2 de los 4 servicios de negocio, aunque los 4 comparten exactamente la misma configuración de cliente Eureka y terminan registrándose poco después.
- El login de `bff-web` en `evidencia06-pruebas-apis.log` devolvió un token nulo, porque su `@LoadBalanced RestTemplate` todavía no tenía a `core-service` en su cache local (`No servers available for service: core-service`, visible en `evidencia03-bff-web.log`); ese `null` se arrastró silenciosamente a las llamadas siguientes del canal Web.

El fix (rama `fix/evidencia-timing-eureka`) reemplaza el `sleep` fijo por una espera activa (`esperar_registro_eureka` en `scripts/_common.sh`) que consulta `/eureka/apps` hasta confirmar el registro de los 4 servicios antes de correr las pruebas, agrega una verificación explícita (`verificar_token` en `probar_apis.sh`) que corta la ejecución con un mensaje claro si algún login no devuelve un token válido, y corrige la captura de log de `probar_tolerancia_fallos.sh` (`2>&1` antes del `tee`) para que un fallo temprano de ese script quede documentado en `evidencia08-circuit-breaker.log` en vez de perderse. Ninguno de estos cambios modifica la lógica de negocio ni la configuración de Spring Cloud/Resilience4j ya descrita en 11.1–11.4: son ajustes de orquestación y diagnóstico del script de evidencia.

## 12. Arquitectura de eventos: Saga con Kafka y tolerancia a fallos ampliada (Exp3, Semana 7)

Esta sección documenta lo agregado sobre la base de las secciones 1–11 (que siguen describiendo fielmente Config Server, Eureka y Circuit Breaker de la Semana 6) para cumplir la actividad formativa "Configurando tolerancia a fallos y arquitectura de eventos con microservicios en la nube". Los cuatro criterios de esa pauta son: (1) definir una arquitectura de eventos alineada con un patrón de diseño y adecuada al caso de uso, (2) diagramarla de forma completa y visualmente organizada, (3) implementar tolerancia a fallos con Resilience4j demostrando resiliencia, y (4) integrar mensajería asíncrona (Kafka o JMS) de forma funcional con escalabilidad demostrada. Las cuatro decisiones de esta sección responden directamente a esos cuatro puntos (ver la trazabilidad en 12.7).

### 12.1 Caso de uso nuevo: transferencia entre cuentas

Los flujos de la Semana 4-6 (depósito, retiro, consulta) son, cada uno, una única operación local sobre **una** cuenta: no había ninguna razón real para coordinarlos por eventos. Por eso se introduce un caso de uso nuevo, **transferencia entre cuentas**, que sí necesita coordinar una operación que toca **dos** cuentas (origen y destino) y que puede fallar a mitad de camino, exactamente el escenario que los patrones de arquitectura de eventos de esta semana (Saga, Event Sourcing) existen para resolver. Se expone desde `bff-web` (el canal donde tiene más sentido una operación de este tipo): `POST /api/web/cuentas/{cuentaId}/transferencias`.

### 12.2 Por qué Saga por coreografía (y no Event Sourcing, ni Saga por orquestación)

- **Saga vs. Event Sourcing.** Event Sourcing resuelve un problema distinto: reconstruir el estado a partir de un log completo de eventos históricos (útil para auditoría/histórico de movimientos). El problema de una transferencia no es "cómo reconstruyo el saldo", es "cómo coordino dos actualizaciones que pueden fallar por separado sin dejar el sistema en un estado inconsistente" — el problema que Saga fue diseñado para resolver.
- **Coreografía vs. orquestación.** En orquestación, un servicio central envía comandos y espera respuestas de cada paso. Como todo el dominio de cuentas vive hoy en un único `core-service`, un orquestador sería una capa adicional sin un segundo servicio real al cual coordinar. La coreografía, en cambio, modela cada paso como un evento independiente que el siguiente paso escucha — y dejó el diseño **listo para el día en que el dominio de cuentas se divida en microservicios** (evolución natural de este mismo ecosistema, ver Javadoc de `TransferenciaSagaService`), sin tener que rediseñar el flujo.
- **Por qué de todas formas vale la pena, incluso con una sola fuente de verdad hoy.** Cada paso de la saga queda como un evento auditable y reproducible por separado (se puede ver en Kafka exactamente en qué paso quedó una transferencia), y el flujo ya está modelado como una secuencia de pasos **compensables**, no como una transacción ACID que dejaría de ser posible en cuanto los datos se distribuyan.

La saga tiene dos pasos y tres desenlaces posibles:

```
1) onSolicitada       (core-service consume "transferencias.solicitadas")
   -> ¿existe la cuenta origen y tiene saldo suficiente?
      NO  -> publica resultado RECHAZADA (fin)
      SI  -> debita cuentaOrigen -> publica "transferencias.debito-aplicado"

2) onDebitoAplicado    (core-service consume "transferencias.debito-aplicado")
   -> ¿existe la cuenta destino?
      SI  -> acredita cuentaDestino -> publica resultado COMPLETADA (fin)
      NO  -> COMPENSA: re-acredita cuentaOrigen -> publica resultado COMPENSADA (fin)
```

### 12.3 Diagrama de la arquitectura (tópicos, eventos y componentes)

![Arquitectura de eventos: Saga de transferencias con Kafka](docs/arquitectura-eventos-s7.png)

| Tópico Kafka | Evento (payload) | Productor | Consumidor(es) |
| --- | --- | --- | --- |
| `bancoxyz.transferencias.solicitadas` | `TransferenciaSolicitadaEvent(transferenciaId, cuentaOrigen, cuentaDestino, monto)` | `bff-web` (`TransferenciaProducer`) | `core-service` (`TransferenciaSagaService#onSolicitada`) |
| `bancoxyz.transferencias.debito-aplicado` | `DebitoAplicadoEvent(transferenciaId, cuentaOrigen, cuentaDestino, monto)` | `core-service` (paso 1) | `core-service` (`TransferenciaSagaService#onDebitoAplicado`, paso 2 — la propia saga "hablándose a sí misma" vía Kafka) |
| `bancoxyz.transferencias.resultado` | `TransferenciaResultadoEvent(transferenciaId, cuentaOrigen, cuentaDestino, monto, estado, detalle)` con `estado` ∈ {COMPLETADA, RECHAZADA, COMPENSADA} | `core-service` (fin de la saga, cualquiera sea el desenlace) | `notificaciones-service` (**2 instancias**, mismo consumer group — ver 12.5) |

El topic de 4 particiones (`docker-compose.yml`, `KAFKA_NUM_PARTITIONS: "4"`) es el mismo para las 3 clases de eventos. La consulta de estado (`GET /api/web/transferencias/{id}` → `GET /internal/transferencias/{id}`) es deliberadamente **síncrona por REST**, no un cuarto tópico: reutiliza Eureka + LoadBalancer + Circuit Breaker ya existentes desde la Semana 6, y una arquitectura orientada a eventos no obliga a que **toda** comunicación sea asíncrona — solo la que se beneficia de serlo (la escritura, que dispara un flujo de varios pasos).

Cada microservicio mantiene su propia copia local del contrato de cada evento (records Java con los mismos campos) en vez de una librería compartida — la misma decisión arquitectónica ya documentada en el `pom.xml` raíz para los DTO REST de los BFF (sección 6.1): cada módulo solo se acopla al **formato** del mensaje (JSON), nunca a una clase Java de otro módulo. Como consecuencia, todos los productores desactivan el header `__TypeId__` de Kafka (`JsonSerializer.ADD_TYPE_INFO_HEADERS=false`) y todos los consumidores fuerzan la deserialización contra su propia clase local (`JsonDeserializer.VALUE_DEFAULT_TYPE`), en vez de confiar en un header que de todos modos llevaría el nombre de una clase de **otro** módulo.

### 12.4 Tolerancia a fallos con Resilience4j (ampliada)

Sobre los 3 circuit breakers `coreService` ya existentes desde la Semana 6 (sección 11.4), esta entrega agrega:

- **`TransferenciaCoreClient` reutiliza la MISMA instancia `coreService`** para `GET /internal/transferencias/{id}`: es la misma dependencia de infraestructura (core-service vía Eureka), así que comparte, con toda intención, el mismo dominio de falla y el mismo contador que ya usa `CoreServiceClient`.
- **Una instancia NUEVA y separada, `kafkaProducer`**, envuelve `TransferenciaProducer.publicarSolicitud` (el envío a Kafka desde `bff-web`). Es un dominio de falla distinto a propósito: que el broker Kafka esté caído no tiene relación con que `core-service` esté arriba o no, y no deberían compartir el mismo circuito:

```yaml
resilience4j:
  circuitbreaker:
    instances:
      kafkaProducer:
        sliding-window-size: 5
        minimum-number-of-calls: 3
        failure-rate-threshold: 50
        wait-duration-in-open-state: 10s
```

`KafkaTemplate.send(...)` devuelve un `CompletableFuture`, que por sí solo no lanzaría ninguna excepción visible si el envío falla silenciosamente; `TransferenciaProducer` espera ese future con un timeout corto (`.get(3, TimeUnit.SECONDS)`) precisamente para que un broker caído se traduzca en una excepción real que el circuit breaker pueda contar. Con el circuito abierto, el fallback (`publicarSolicitudFallback`) lanza `MensajeriaNoDisponibleException` → **HTTP 503**, igual que ya hace `coreService` para una caída de `core-service` (sección 11.4).

**Para demostrarlo:** con Kafka detenido (`docker compose stop kafka`) y los servicios arriba, repetir `POST /api/web/cuentas/101/transferencias` varias veces — las primeras respuestas reflejan el fallo de conexión real al broker, y a partir de la tercera el circuito `kafkaProducer` abre y todas las respuestas siguientes son un 503 inmediato y controlado.

### 12.5 Mensajería Kafka funcional y escalabilidad demostrada

`notificaciones-service` es un microservicio nuevo, deliberadamente desacoplado del camino transaccional crítico: solo escucha `bancoxyz.transferencias.resultado` y simula el envío de una notificación al cliente. Si estuviera caído, la saga igual se completa correctamente en `core-service` — solo se pierde la notificación, nunca la consistencia del saldo. Esa es la ventaja concreta de modelarlo como un consumidor de eventos independiente en vez de una llamada síncrona más dentro de la saga.

La escalabilidad se demuestra levantando **2 instancias** de `notificaciones-service` (puertos 8084 y 8085) con el **mismo `group-id`** (`spring.kafka.consumer.group-id: notificaciones-service`) contra un tópico de 4 particiones: Kafka reparte las particiones entre las 2 instancias del mismo consumer group, en vez de que cada una reciba todos los mensajes — el mecanismo estándar de escalado horizontal de Kafka. Cada mensaje procesado se loguea con su partición y offset (`TransferenciaResultadoListener`), lo que permite comparar el log de la instancia A con el de la instancia B y comprobar el reparto:

```
[instancia :8084] Notificacion procesada (particion=1, offset=3) - transferenciaId=... estado=COMPLETADA -> "..."
[instancia :8085] Notificacion procesada (particion=0, offset=2) - transferenciaId=... estado=RECHAZADA -> "..."
```

`scripts/probar_transferencias.sh` genera 6 transferencias (una exitosa, una rechazada por fondos insuficientes, una compensada por cuenta destino inexistente, una intentada sin autorización, y 3 adicionales) para que ambas instancias reciban mensajes; `evidencias/evidencia11-notificaciones-escalabilidad.log` (ver 12.6) documenta cuántos procesó cada una.

### 12.6 Cómo levantar y generar la evidencia (incluye Kafka)

Requisito nuevo sobre la sección 11.2: **Docker Desktop** (Windows/macOS) o **Docker Engine** (Linux), corriendo, para el broker Kafka de esta semana (`docker-compose.yml`, imagen oficial `apache/kafka:3.7.0`, modo KRaft de un solo nodo — sin Zookeeper, la opción más simple para un entorno académico sin sacrificar que sea Kafka real).

`scripts/generar_evidencia.sh` sigue siendo el mismo script único para CI y para ejecución local (Windows con Git Bash, Linux o macOS), ahora ampliado: compila los **7 módulos**, levanta Kafka (`docker compose up -d kafka`, esperando activamente a que acepte conexiones en `:9092`), levanta los **8 procesos Java** en orden (config-server, eureka-server, core-service, los 3 BFF y **2 instancias** de `notificaciones-service`, en `:8084` y `:8085`), corre `scripts/probar_apis.sh`, captura el registro en Eureka, corre `scripts/probar_transferencias.sh` (los 3 desenlaces de la saga), verifica el reparto de particiones entre las 2 instancias de `notificaciones-service`, corre `scripts/probar_tolerancia_fallos.sh` y al final detiene todo lo que él mismo levantó — **incluyendo el contenedor de Kafka** (`docker compose down`) — incluso si algo falla a mitad de camino.

```bash
docker compose up -d kafka                                 # o dejar que generar_evidencia.sh lo haga por ti
bash scripts/generar_evidencia.sh                           # compila y corre todo el flujo (Semana 6 + Semana 7)
bash scripts/generar_evidencia.sh --skip-build               # reusa los jars ya compilados
bash scripts/generar_evidencia.sh --skip-tolerancia-fallos   # no mata core-service al final
```

Los logs quedan en `evidencias/` con el mismo esquema de nombres ya usado en la Semana 6, extendido con 3 archivos nuevos: `evidencia09a-notificaciones-A.log` / `evidencia09b-notificaciones-B.log` (arranque y consumo de cada instancia), `evidencia10-pruebas-transferencias.log` (los 3 desenlaces de la saga) y `evidencia11-notificaciones-escalabilidad.log` (el reparto de particiones entre ambas instancias, ver 12.5). El mismo workflow de GitHub Actions (`.github/workflows/evidencia-ejecucion.yml`) genera esta evidencia en CI sin cambios adicionales: los runners de `ubuntu-latest` ya traen Docker Engine y el plugin `docker compose` instalados, así que `scripts/generar_evidencia.sh` levanta Kafka ahí exactamente igual que en local, con el mismo `docker-compose.yml`.

### 12.7 Trazabilidad con la pauta de evaluación formativa (Semana 7)

| Criterio de la pauta | Dónde se evidencia |
| --- | --- |
| Define la arquitectura de eventos a utilizar, alineada con los patrones de diseño seleccionados, y es adecuada para el caso de uso | Sección 12.1–12.2: caso de uso nuevo (transferencia entre cuentas) que sí necesita coordinación multi-paso, patrón Saga por coreografía elegido y justificado frente a Event Sourcing y a Saga por orquestación. |
| Elabora un diagrama representativo de la arquitectura elegida de forma completa con los tópicos/mensajes/eventos de la solución, con una estructura visual organizada | Sección 12.3: diagrama completo (`docs/arquitectura-eventos-s7.png`) más la tabla de los 3 tópicos con su evento, productor y consumidor(es). |
| Implementa tolerancia a fallos con Resilience4j demostrando resiliencia ante fallos | Sección 12.4: circuit breaker `kafkaProducer` nuevo (dominio de falla independiente de `coreService`) sobre el envío a Kafka, con pasos explícitos para reproducir la apertura del circuito y su respuesta 503 controlada. |
| Integra componentes de mensajería asíncrona (Kafka o JMS) de manera funcional, con mensajes/eventos correctamente procesados y escalabilidad demostrada | Sección 12.5: Kafka real (Docker, KRaft) con 3 tópicos funcionando end-to-end (`scripts/probar_transferencias.sh`, `evidencia10-pruebas-transferencias.log`) y escalabilidad demostrada con 2 instancias de `notificaciones-service` en el mismo consumer group repartiéndose las particiones (`evidencia11-notificaciones-escalabilidad.log`). |
