# Warm-up en clase — Lab 6: Aseguramiento de Microservicios con JWT

## Contexto

- **Access token**: credencial de corta vida que viaja en cada request (`Authorization: Bearer`). Su verificación es local (firma, issuer, audience); mientras no expire, un servicio que confía en su firma lo acepta.
- **Refresh token**: credencial de larga vida que **no** se usa para llamar APIs; solo sirve para pedir nuevos access tokens.

## Tarea práctica

### 6. Parte 1 — Incidente: secuestro de token

Este ejercicio simula que un atacante obtiene un **refresh token** de un usuario.

Siga los comandos en `recursos/auth_cli.md` para:

1. Crear un usuario de prueba (o usar uno existente).
2. Hacer login y obtener `ACCESS_TOKEN` + `REFRESH_TOKEN`.
3. Probar un endpoint protegido con `ACCESS_TOKEN`.
4. Como "atacante", usar `REFRESH_TOKEN` para emitir nuevos access tokens repetidamente.

Endpoint protegido para el experimento:

- `POST <ApiGatewayUrl>/ventas`

Guarden evidencia de cada paso (capturas o output de consola): el login exitoso, la respuesta del endpoint protegido con `ACCESS_TOKEN`, y las múltiples emisiones de nuevos access tokens usando `REFRESH_TOKEN`.

## Cierre de la sesión

Al terminar, cada equipo debe tener el `ACCESS_TOKEN` y `REFRESH_TOKEN` capturados, con evidencia de que el "atacante" pudo emitir nuevos access tokens repetidamente. Esto es exactamente la sección "6. Parte 1 — Incidente" del laboratorio — no hay que rehacerlo después, se sigue directamente con la contención (revocación) en la Parte 2.
