# LogiTrack API

API REST de seguimiento de envíos. Proyecto de portafolio de Pedro (backend junior, Java/Spring Boot).
Es la primera pieza del ecosistema LogiTrack; más adelante vendrán `logitrack-tarifas` (PL/SQL en Oracle),
`logitrack-inventario` y `logitrack-rutas`, cada uno en su propio repo.

El diseño completo (arquitectura, máquina de estados, modelo de datos, flujos y decisiones D1–D12) está en:
@docs/diseno.md

## Cómo trabajar conmigo

- Pedro está aprendiendo: explica el porqué de las decisiones no obvias, en español y de forma breve.
- Propón el plan antes de cambios grandes (varios ficheros o una migración nueva).
- Cambios pequeños y en ramas: una rama por funcionalidad (`feat/crear-envio`), commits en español.
- Si una decisión contradice `docs/diseno.md`, dilo y actualiza el documento en el mismo cambio.

## Comandos

```bash
docker compose up -d db      # PostgreSQL 16 local (puerto 5432)
./mvnw spring-boot:run       # API en http://localhost:8080 (Maven Wrapper: no hace falta instalar Maven)
./mvnw verify                # tests (necesitan la BD levantada)
docker compose up --build    # todo en Docker
```

- Health: `GET /health` · Swagger UI: `/swagger-ui.html`

## Stack

Java 21 · Spring Boot 4.1 · PostgreSQL 16 · Flyway · Spring JDBC (`JdbcClient`) · springdoc · JUnit 5 + AssertJ

## Reglas de arquitectura (no romper)

- **Sin JPA/Hibernate.** Acceso a datos con `JdbcClient` y SQL explícito (D8).
- **El SQL solo vive en clases `*Repository`.** Controladores sin lógica; reglas de negocio en `*Service`.
- **Paquetes por funcionalidad** bajo `com.pedromiras.logitrack`: `auth`, `shipment`, `tracking`, `webhook`, `shared` (D10).
- **Historial inmutable:** `shipment_events` nunca se actualiza ni se borra (D1).
- **La BD valida transiciones** con la FK a `allowed_transitions`. No dupliques la tabla de transiciones en Java;
  captura la violación de la FK `fk_events_transition` y tradúcela a `409 INVALID_TRANSITION` (D2).
- **Registrar un evento es una sola transacción:** `SELECT ... FOR UPDATE` del envío → insertar evento →
  actualizar `shipments.status` → insertar filas en `webhook_deliveries` (D3, D6). Ver sección 6 del diseño.
- **Nunca enviar webhooks dentro de la petición HTTP.** Solo el worker los envía (D3, D4).
- **`/tracking/{code}` no expone datos personales** (ni nombres, ni direcciones, ni email) (D5).
- **Errores** siempre con el formato `{ "error": { "code": "...", "message": "..." } }` desde un `@RestControllerAdvice` en `shared`.

## Migraciones

- En `src/main/resources/db/migration`, formato `V<n>__descripcion.sql`.
- **Nunca edites una migración ya aplicada**: crea una nueva (`V3__...`).
- Los enums de PostgreSQL (`shipment_status`, etc.) necesitan cast explícito en SQL: `:status::shipment_status`.

## Convenciones de código

- Identificadores, clases y endpoints en inglés; comentarios, documentación, nombres de test y commits en español.
- DTOs de entrada/salida como `record`, con Bean Validation (`@NotBlank`, `@Positive`...).
- Tests de integración contra PostgreSQL real con `@SpringBootTest` + `@Transactional` (rollback por test).
- Todo test nuevo de una regla de negocio debe incluir también el caso que falla.

## Datos y seguridad

- Todos los datos son inventados. **Nunca** uses código, nombres ni datos de la empresa donde trabaja Pedro.
- Ningún secreto en el repo: credenciales y claves JWT solo por variables de entorno.

## Despliegue (sin coste)

- API en el plan gratuito de Render (Dockerfile). BD en Neon, endpoint directo, no el `-pooler` (D11).
- Variables: `DATABASE_URL` (formato JDBC), `DATABASE_USERNAME`, `DATABASE_PASSWORD`, `PORT`,
  `JWT_SECRET`, `ADMIN_EMAIL`, `ADMIN_PASSWORD` (D12).
- Pool de conexiones limitado a 5 por los límites de los planes gratuitos.

## Estado

- [x] Diseño, esquema y migraciones V1–V3 (probadas en PostgreSQL 16)
- [x] Esqueleto Spring Boot, Docker, CI
- [x] Verificar que compila (`mvn verify` en verde; springdoc 3.0.0 funciona con Boot 4.1)
- [ ] `POST /shipments` y `GET /shipments`, `GET /shipments/{id}`
- [ ] `POST /shipments/{id}/events` con la transacción completa
- [ ] Manejo global de errores
- [ ] Autenticación JWT y roles
- [ ] `GET /tracking/{code}` + página pública en `web/`
- [ ] Webhooks: suscripciones, worker, firma HMAC, reintentos
- [ ] Despliegue en Render + BD gratuita
