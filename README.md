# LogiTrack API

API REST de seguimiento de envíos: los operadores registran envíos y sus cambios de estado, cualquiera puede rastrear un paquete con su código y los sistemas externos reciben webhooks cuando un envío cambia de estado.

Proyecto de portafolio · [pedromiras.github.io](https://pedromiras.github.io)

> **Estado:** esqueleto del proyecto y esquema de base de datos. Los endpoints se implementan en las siguientes iteraciones.

## Stack

- Java 21 · Spring Boot 4.1
- PostgreSQL 16 · Flyway · Spring JDBC
- Swagger UI (springdoc)
- Docker · GitHub Actions

## Arquitectura

Monolito modular desplegado como un único servicio. El diseño completo, con los diagramas, la máquina de estados y las decisiones razonadas, está en [`docs/diseno.md`](docs/diseno.md).

Lo más destacable:

- **La base de datos protege la máquina de estados.** Una clave foránea compuesta contra `allowed_transitions` rechaza cualquier transición inválida, aunque el código tenga un bug.
- **Historial inmutable.** Cada cambio de estado es un evento que nunca se modifica.
- **Webhooks fiables sin cola de pago.** Patrón *outbox*: el webhook se guarda en la misma transacción que el evento y un worker lo entrega con reintentos.

```
src/main/java/com/pedromiras/logitrack/
├── auth/       login, JWT, roles
├── shipment/   envíos, eventos, máquina de estados
├── tracking/   seguimiento público
├── webhook/    suscripciones, outbox, worker
└── shared/     errores, configuración
```

## Ejecutar en local

Requisitos: Docker. Para desarrollar sin Docker para la API, también Java 21 y Maven.

```bash
# Todo con Docker
docker compose up --build

# O solo la base de datos y la API desde el IDE / Maven
docker compose up -d db
mvn spring-boot:run
```

- Health check: http://localhost:8080/health
- Swagger UI: http://localhost:8080/swagger-ui.html

Flyway aplica las migraciones de `src/main/resources/db/migration` al arrancar.

## Tests

```bash
docker compose up -d db
mvn verify
```

En GitHub Actions los tests corren contra un PostgreSQL de servicio en cada push.

## Despliegue

Pensado para funcionar sin coste:

- API en el plan gratuito de Render (Docker).
- PostgreSQL gratuito en Supabase o Neon.

Variables de entorno: `DATABASE_URL` (formato JDBC), `DATABASE_USERNAME`, `DATABASE_PASSWORD`.

> El plan gratuito de Render suspende el servicio tras un rato sin tráfico: la primera petición puede tardar en responder.

## Datos

Todos los datos de ejemplo son inventados.
