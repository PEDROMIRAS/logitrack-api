# Plan: autenticación (`feat/auth`)

Spec aprobada: [`docs/specs/auth.md`](../docs/specs/auth.md) (sin `expiresAt`; `ADMIN_PASSWORD` ≥ 12 caracteres).
Tareas: [`tasks/todo.md`](todo.md).

## Resumen

Login con JWT HS256 de 1 hora, contraseñas BCrypt, roles `ADMIN` ⊃ `OPERATOR`, primer ADMIN desde
variables de entorno y errores `400`/`401`/`403` con el formato común. En cinco tareas pequeñas; cada una
deja `./mvnw verify` en verde.

## APIs comprobadas (Boot 4.1.0 → Spring Security 7.1.0, Spring 7.0.8)

Comprobado sobre los jars reales con `javap`, no de memoria:

| Para | API | Estado |
|------|-----|--------|
| Firmar | `NimbusJwtEncoder.withSecretKey(SecretKey).algorithm(MacAlgorithm.HS256).build()` | ✓ existe |
| Validar | `NimbusJwtDecoder.withSecretKey(SecretKey)` | ✓ existe |
| Roles | `RoleHierarchyImpl.withDefaultRolePrefix().role("ADMIN").implies("OPERATOR").build()` | ✓ existe |
| Claim `role` → autoridad | `JwtGrantedAuthoritiesConverter.setAuthoritiesClaimName("role")` + `setAuthorityPrefix("ROLE_")` | ✓ existe |
| MockMvc en tests | `org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc` (paquete nuevo en Boot 4) | ✓ en `spring-boot-webmvc-test` |

## Dependencias nuevas

| Artefacto | Scope | Por qué |
|-----------|-------|---------|
| `spring-boot-starter-security-oauth2-resource-server` | compile | Spring Security + Nimbus (firmar y validar JWT). El nombre antiguo sin `security-` está *deprecated* en Boot 4 |
| `spring-boot-starter-security-oauth2-resource-server-test` | test | Trae `spring-security-test` |
| `spring-boot-starter-webmvc-test` | test | **MockMvc ya no viene en `spring-boot-starter-test`** en Boot 4 (comprobado con `dependency:tree`). Es la única dependencia fuera de "starters de seguridad": **necesita tu visto bueno** al aprobar este plan |

## Decisiones de implementación

- **`JWT_SECRET` se lee con `@Value("${JWT_SECRET}")`, sin valor por defecto.** Si falta, Spring no arranca
  ("Could not resolve placeholder"). Si tiene menos de 32 bytes, `SecurityConfig` lanza un error claro.
  32 bytes no es arbitrario: Nimbus rechaza claves HS256 de menos de 256 bits.
- **Secreto de test en `src/test/resources/application.properties`.** Ojo: **no** `application.yml`, porque un
  `application.yml` en `src/test` *taparía* el de `src/main` (Spring carga solo el primero que encuentra con ese
  nombre). Con `.properties` se cargan los dos.
- **`AuthService` compara contra un hash BCrypt ficticio cuando el email no existe.** Así "email no existe" y
  "contraseña mala" tardan lo mismo y no se puede averiguar qué emails están registrados midiendo tiempos.
- **`LoginRequest` y `LoginResponse` como records anidados en `AuthController`.** Solo los usa ese controlador.
- **El usuario actual, en los próximos endpoints:** `@AuthenticationPrincipal Jwt jwt` →
  `UUID.fromString(jwt.getSubject())`. Esta rama no añade helper; se verá cuando haya un primer uso real.
- **401/403 con formato común:** `AuthenticationEntryPoint` y `AccessDeniedHandler` propios en `SecurityConfig`,
  que escriben `ErrorResponse` (de `shared`) con el `ObjectMapper` de Spring.

## Orden y por qué

1. **Seguridad base (T1)** primero: es lo más arriesgado (configuración nueva de Boot 4) y, en cuanto entra
   Spring Security, **todo** queda protegido. `/health` y Swagger tienen que seguir abiertos desde el primer commit.
2. **Login (T2)** y **roles (T3)**: el flujo completo de un usuario existente.
3. **Primer ADMIN (T4)**: independiente del login; los tests de T2/T3 crean sus usuarios a mano.
4. **Arranque real y documentación (T5)**: Docker, diseño y estado.

## Riesgos

| Riesgo | Impacto | Mitigación |
|--------|---------|------------|
| Al añadir Spring Security, `/health` y Swagger devuelven 401 | Alto (Render usa `/health`) | T1 los abre y lo prueba |
| `MigrationsTest` deja de arrancar por falta de `JWT_SECRET` | Medio | T1 añade el secreto de test; `./mvnw verify` completo en cada tarea |
| Enumeración de usuarios por tiempo de respuesta | Medio | Hash ficticio (ver decisiones) |
| Secreto real en el repo | Alto | Solo valores de test en `src/test` y de desarrollo en `docker-compose.yml`, como ya pasa con la BD local |

## Preguntas abiertas

- ¿Apruebas `spring-boot-starter-webmvc-test` como dependencia de test? Sin ella no hay MockMvc y los tests
  de endpoints tendrían que levantar un servidor real.
