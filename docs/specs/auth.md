# Spec: autenticación (`feat/auth`)

Estado: **aprobada** (sin `expiresAt`; `ADMIN_PASSWORD` ≥ 12 caracteres) · Rama: `feat/auth` · Diseño: D12 y sección 7 de [`diseno.md`](../diseno.md)

## Objetivo

Que la API sepa **quién** hace cada petición y **qué rol** tiene, para que los siguientes endpoints
puedan rellenar `created_by` / `recorded_by` con un usuario real y restringir rutas por rol.

- Un operador hace `POST /auth/login` con email y contraseña y recibe un JWT.
- Con ese JWT en `Authorization: Bearer <token>` accede a las rutas protegidas.
- Al desplegar por primera vez, la app crea el primer ADMIN desde variables de entorno (D12).

**Fuera de alcance:** registro de usuarios, alta de OPERATORs por API, logout, refresh tokens,
rate limit del login, cambio de contraseña.

## Decisiones

| Tema | Decisión | Por qué |
|------|----------|---------|
| Token | JWT firmado con **HS256** (clave simétrica `JWT_SECRET`) | Un solo servicio firma y valida; no hace falta par de claves |
| Librería | `spring-boot-starter-security-oauth2-resource-server` (nombre de Boot 4; el antiguo `spring-boot-starter-oauth2-resource-server` está *deprecated*) | Trae Nimbus para firmar y validar; sin librerías JWT de terceros |
| Claims | `sub` = id del usuario (UUID), `role` = `ADMIN` / `OPERATOR`, `iat`, `exp` | `sub` es lo que necesitan `created_by` / `recorded_by` |
| Caducidad | **1 hora**, sin refresh token | Demo: volver a hacer login es aceptable |
| Contraseñas | **BCrypt** (`PasswordEncoder` estándar de Spring Security) | Estándar, con sal y coste ajustable |
| Roles | `ADMIN` incluye todo lo de `OPERATOR` (jerarquía de roles) | Un admin no necesita dos cuentas |
| Email | Se guarda y se busca **en minúsculas** | Evita cuentas duplicadas `Ana@x.com` / `ana@x.com` (auditoría, punto 6) |
| `JWT_SECRET` | Obligatorio, **mínimo 32 bytes**. Sin él la app **no arranca** | Un valor por defecto en el repo sería un secreto conocido si alguien olvida la variable en producción |

## API

`POST /auth/login` · público

```json
// petición
{ "email": "admin@logitrack.dev", "password": "..." }
// 200
{ "token": "eyJhbGciOiJIUzI1NiJ9..." }
```

| Caso | Respuesta |
|------|-----------|
| Credenciales correctas | `200` con `token` |
| Email inexistente **o** contraseña incorrecta | `401` `INVALID_CREDENTIALS`, **mismo mensaje en los dos casos** |
| Body inválido (email vacío o mal formado, password vacía) | `400` `VALIDATION_ERROR` |
| Ruta protegida sin token, token mal firmado o caducado | `401` `UNAUTHORIZED` |
| Token válido pero rol insuficiente | `403` `FORBIDDEN` |

Todos los errores con el formato común `{ "error": { "code": "...", "message": "..." } }`, incluidos
`401` y `403`, que los genera Spring Security fuera de los controladores.

**Rutas públicas:** `POST /auth/login`, `GET /health`, `GET /tracking/**`, Swagger UI (`/swagger-ui.html`,
`/swagger-ui/**`, `/v3/api-docs/**`). **Todo lo demás exige token.** Las reglas por rol de cada ruta
(`OPERATOR` en `/shipments`, `ADMIN` en `/webhooks`) se añaden con cada funcionalidad.

## Primer ADMIN (D12)

Al arrancar:

| Tabla `users` | `ADMIN_EMAIL` y `ADMIN_PASSWORD` | Resultado |
|---------------|----------------------------------|-----------|
| Vacía | Definidas, password ≥ 12 caracteres | Crea el ADMIN (email en minúsculas, password con BCrypt) y lo registra en el log, **sin la contraseña** |
| Vacía | Definidas, password < 12 caracteres | **La app no arranca** (mensaje claro) |
| Vacía | Alguna falta | Arranca, `WARN` en el log: nadie podrá hacer login |
| Con usuarios | Cualquiera | No hace nada (las variables se ignoran) |

## Comandos

```bash
docker compose up -d db
./mvnw verify                                   # tests (usan un JWT_SECRET solo de test)

# arrancar en local (PowerShell)
$env:JWT_SECRET = "<32+ caracteres aleatorios>"
$env:ADMIN_EMAIL = "admin@logitrack.dev"
$env:ADMIN_PASSWORD = "<12+ caracteres>"
./mvnw spring-boot:run
```

## Estructura

Todo en `com.pedromiras.logitrack` (D10):

```
auth/
  AuthController        POST /auth/login (sin lógica)
  AuthService           comprobar credenciales, emitir token
  UserRepository        SQL de users (único sitio con SQL de users)
  AdminBootstrap        primer ADMIN al arrancar (D12)
  SecurityConfig        rutas públicas, JWT, jerarquía de roles, 401/403 con formato común
  LoginRequest / LoginResponse   records con Bean Validation
shared/
  ErrorResponse         record del formato { "error": { code, message } }
  GlobalExceptionHandler  @RestControllerAdvice: 400 de validación, 401 de credenciales
```

`docker-compose.yml`: el servicio `api` recibe `JWT_SECRET`, `ADMIN_EMAIL` y `ADMIN_PASSWORD` con valores
**de desarrollo**, igual que ya hace con la contraseña de la BD local.

## Estilo

Como el resto del proyecto: records para DTOs, SQL explícito con `JdbcClient` en el repositorio,
identificadores en inglés y comentarios y nombres de test en español.

```java
public record LoginRequest(@NotBlank @Email String email, @NotBlank String password) {}
```

## Tests

Integración con `@SpringBootTest` contra PostgreSQL real, `@Transactional` (rollback por test).
Cada regla con su caso que pasa **y** su caso que falla:

- Login: correcto → `200` y token con `sub` y `role`; contraseña mala → `401`; email inexistente → `401`
  con el **mismo cuerpo**; email con mayúsculas → `200`; body inválido → `400`.
- Token: sin token → `401`; firmado con otra clave → `401`; caducado → `401`; válido → `200`.
- Roles: OPERATOR en ruta de ADMIN → `403`; ADMIN en ruta de OPERATOR → `200`.
  Las rutas de prueba viven en un controlador **solo de test** (`src/test`), no en producción.
- Primer ADMIN: las cuatro filas de la tabla de arriba.
- Errores `401` / `403` con el formato común.

## Límites

- **Siempre:** test del caso que falla; `./mvnw verify` en verde antes de cada commit; email en minúsculas.
- **Preguntar antes:** cualquier dependencia aparte de los starters de seguridad; cambios de esquema
  (no hacen falta: la tabla `users` de V1 ya sirve).
- **Nunca:** secretos en el repo (los de test viven en `src/test/resources` y solo valen para test);
  registrar contraseñas o tokens en el log; respuestas distintas para "email no existe" y "contraseña mala".

## Criterios de aceptación

1. `./mvnw verify` en verde en local y en la CI, con todos los tests de la sección Tests.
2. `docker compose up --build` arranca, crea el ADMIN y `POST /auth/login` con sus credenciales devuelve un token.
3. Con ese token, una ruta protegida responde; sin él, `401` con el formato común.
4. Sin `JWT_SECRET` (o con menos de 32 bytes) la app no arranca y lo dice.
5. `docs/diseno.md` y `CLAUDE.md` actualizados (decisiones de esta spec y estado).

## Preguntas resueltas

1. `expiresAt` en la respuesta de login: **no** (la demo no lo necesita).
2. Mínimo de 12 caracteres para `ADMIN_PASSWORD`: **sí**.
