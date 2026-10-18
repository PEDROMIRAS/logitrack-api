# Tareas: `feat/auth`

Plan: [`plan.md`](plan.md) · Spec: [`docs/specs/auth.md`](../docs/specs/auth.md)

Antes de empezar: crear `feat/auth` desde `main` (ya tiene `./mvnw`, V3, esta spec y este plan).
Cada tarea termina con `./mvnw verify` en verde y un commit en español.

## T1: Spring Security base, rutas públicas y 401 con formato común

Al añadir Spring Security todo queda cerrado: esta tarea abre lo público, exige `JWT_SECRET` y hace que el
`401` salga con `{ "error": ... }`.

**Aceptación**
- [ ] `GET /health` y `/swagger-ui.html` responden sin token; una ruta protegida sin token da `401` `UNAUTHORIZED` con el formato común.
- [ ] Sin `JWT_SECRET` la app no arranca; con menos de 32 bytes, error claro (test unitario del método que construye la clave).
- [ ] `MigrationsTest` sigue en verde.

**Verificación:** `./mvnw verify` · **Depende de:** nada

**Ficheros:** `pom.xml`, `auth/SecurityConfig.java`, `shared/ErrorResponse.java`,
`src/test/resources/application.properties`, `auth/SecurityConfigTest.java` (+ controlador de prueba en `src/test`)

**Tamaño:** M

## T2: `POST /auth/login`

**Aceptación**
- [ ] Credenciales correctas → `200` con un token cuyo `sub` es el id del usuario y `role` su rol; ese token abre una ruta protegida.
- [ ] Contraseña mala y email inexistente → `401` `INVALID_CREDENTIALS` con **el mismo cuerpo**; email con mayúsculas → `200`.
- [ ] Body inválido → `400` `VALIDATION_ERROR` con el formato común.

**Verificación:** `./mvnw verify` · **Depende de:** T1

**Ficheros:** `auth/UserRepository.java`, `auth/AuthService.java`, `auth/AuthController.java` (records anidados),
`shared/GlobalExceptionHandler.java`, `auth/AuthControllerTest.java`

**Tamaño:** M

## T3: Roles y validación del token

**Aceptación**
- [ ] OPERATOR en ruta de ADMIN → `403` `FORBIDDEN` con formato común; ADMIN en ruta de OPERATOR → `200`.
- [ ] Token firmado con otra clave → `401`; token caducado → `401`.

**Verificación:** `./mvnw verify` · **Depende de:** T2

**Ficheros:** `auth/SecurityConfig.java`, controlador de prueba en `src/test`, `auth/SecurityConfigTest.java`

**Tamaño:** S

### Checkpoint 1 (tras T1–T3)
- [ ] `./mvnw verify` en verde
- [ ] Login y rutas protegidas funcionan de punta a punta en los tests
- [ ] Revisión contigo antes de seguir

## T4: Primer ADMIN al arrancar (D12)

**Aceptación**
- [ ] Tabla vacía + variables válidas → crea ADMIN (email en minúsculas, BCrypt) y lo registra en el log sin la contraseña.
- [ ] Tabla vacía + `ADMIN_PASSWORD` < 12 → error y no arranca; tabla vacía + falta alguna variable → `WARN` y arranca.
- [ ] Tabla con usuarios → no hace nada.

**Verificación:** `./mvnw verify` · **Depende de:** T2 (`UserRepository`)

**Ficheros:** `auth/AdminBootstrap.java`, `auth/UserRepository.java`, `auth/AdminBootstrapTest.java`

**Tamaño:** S

## T5: Arranque real y documentación

**Aceptación**
- [ ] `docker compose up --build`: se crea el ADMIN, `POST /auth/login` devuelve token, una ruta protegida responde con él y da `401` sin él, y Swagger se abre.
- [ ] `docs/diseno.md`: nueva decisión D13 (JWT HS256 1 h + BCrypt + roles); `CLAUDE.md`: estado de "Autenticación JWT y roles".

**Verificación:** prueba manual con `curl` contra Docker + `./mvnw verify` · **Depende de:** T1–T4

**Ficheros:** `docker-compose.yml`, `docs/diseno.md`, `CLAUDE.md`, `docs/specs/auth.md` (estado → implementada)

**Tamaño:** S

### Checkpoint final
- [ ] Los 5 criterios de aceptación de la spec cumplidos
- [ ] CI en verde · PR abierto
