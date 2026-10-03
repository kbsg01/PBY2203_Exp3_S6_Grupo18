# syntax=docker/dockerfile:1
# Service Discovery (Netflix Eureka, standalone).
#
# Imagen construida a partir del jar que genera Maven (mvn -DskipTests package), tal como
# propone la lectura de la semana "Spring Boot with Docker". Ver README, seccion 13.
#   docker build -t bancoxyz/eureka-server:1.0.0 eureka-server/
# (docker-compose.yaml lo hace automaticamente con "docker compose up --build").

# ---------------------------------------------------------------------------------------------
# Etapa 1: separa el jar de Spring Boot en capas (dependencias / loader / codigo propio). Las
# dependencias cambian poco, el codigo propio cambia en cada build: al copiarlas como capas
# distintas, Docker reutiliza la cache de las capas pesadas y solo reconstruye la ultima.
# ---------------------------------------------------------------------------------------------
FROM eclipse-temurin:21-jre AS capas
WORKDIR /build
COPY target/eureka-server.jar app.jar
RUN java -Djarmode=tools -jar app.jar extract --layers --destination extraido

# ---------------------------------------------------------------------------------------------
# Etapa 2: imagen final, solo JRE (sin JDK ni Maven) y sin el jar original duplicado.
# ---------------------------------------------------------------------------------------------
FROM eclipse-temurin:21-jre
LABEL org.opencontainers.image.title="eureka-server" \
      org.opencontainers.image.description="Service Discovery (Netflix Eureka, standalone)." \
      org.opencontainers.image.vendor="Banco XYZ - PBY2203 Duoc UC" \
      org.opencontainers.image.version="1.0.0"

# Nunca correr la JVM como root dentro del contenedor (menor privilegio).
RUN groupadd --system spring && useradd --system --gid spring --no-create-home spring
WORKDIR /app
COPY --from=capas /build/extraido/dependencies/ ./
COPY --from=capas /build/extraido/spring-boot-loader/ ./
COPY --from=capas /build/extraido/snapshot-dependencies/ ./
COPY --from=capas /build/extraido/application/ ./
USER spring:spring

EXPOSE 8761

# La JVM respeta el limite de memoria del contenedor (deploy.resources.limits en
# docker-compose.yaml) en vez de dimensionarse segun la RAM total del host.
ENV JAVA_OPTS="-XX:MaxRAMPercentage=75.0 -XX:+ExitOnOutOfMemoryError"

# curl ya viene en eclipse-temurin:21-jre. start-period cubre el arranque de Spring Boot.
HEALTHCHECK --interval=10s --timeout=3s --start-period=90s --retries=6 \
  CMD curl -fsS http://localhost:8761/actuator/health || exit 1

ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar app.jar"]
