# Warm-up en clase — Lab 6: Aseguramiento de Microservicios con JWT

## Contexto

- **Access token**: credencial de corta vida que viaja en cada request (`Authorization: Bearer`). Su verificación es local (firma, issuer, audience); mientras no expire, un servicio que confía en su firma lo acepta.
- **Refresh token**: credencial de larga vida que **no** se usa para llamar APIs; solo sirve para pedir nuevos access tokens.

Este warm-up asume que el stack de CloudFormation del Lab 6 (sección 4 del enunciado) **ya está desplegado**. Necesitarán los Outputs del stack:

- `ApiGatewayUrl`
- `CognitoUserPoolId`
- `CognitoUserPoolClientId`

## Prerrequisitos (antes de empezar)

1. Tener AWS CLI instalada y configurada (`aws configure`) apuntando a la misma cuenta/región donde se desplegó el stack.
2. Tener `jq` instalado (permite extraer los tokens del JSON de respuesta sin copiar/pegar a mano). Verifiquen con:
   ```bash
   jq --version
   ```
3. Exportar las variables de entorno con los Outputs del stack (reemplacen los valores `<...>` por los suyos):
   ```bash
   export API_BASE_URL="<ApiGatewayUrl>"
   export USER_POOL_ID="<CognitoUserPoolId>"
   export APP_CLIENT_ID="<CognitoUserPoolClientId>"
   ```

Si tienen dudas sobre algún comando, la referencia completa (con más opciones) está en `recursos/auth_cli.md`.

## Tarea práctica

### 6. Parte 1 — Incidente: secuestro de token

Este ejercicio simula que un atacante obtiene un **refresh token** de un usuario. Van a hacer, en orden, los 4 pasos siguientes. Cada paso indica el comando exacto a ejecutar y qué deben capturar como evidencia.

#### Paso 1 — Crear un usuario de prueba

Crear el usuario:

```bash
aws cognito-idp admin-create-user \
  --user-pool-id "$USER_POOL_ID" \
  --username tendero1@example.com \
  --user-attributes Name=email,Value=tendero1@example.com Name=email_verified,Value=true
```

Definir una contraseña permanente (necesaria para poder hacer login con `USER_PASSWORD_AUTH`):

```bash
aws cognito-idp admin-set-user-password \
  --user-pool-id "$USER_POOL_ID" \
  --username tendero1@example.com \
  --password 'Lab6-Password#2026' \
  --permanent
```

**Evidencia a guardar**: output de ambos comandos (o confirmación de que el usuario ya existía).

#### Paso 2 — Login y obtención de `ACCESS_TOKEN` + `REFRESH_TOKEN`

Ejecutar el login guardando la respuesta completa en una variable, y extraer ambos tokens con `jq`:

```bash
TOKENS_JSON=$(aws cognito-idp initiate-auth \
  --client-id "$APP_CLIENT_ID" \
  --auth-flow USER_PASSWORD_AUTH \
  --auth-parameters USERNAME=tendero1@example.com,PASSWORD='Lab6-Password#2026')

export ACCESS_TOKEN=$(echo "$TOKENS_JSON" | jq -r '.AuthenticationResult.AccessToken')
export REFRESH_TOKEN=$(echo "$TOKENS_JSON" | jq -r '.AuthenticationResult.RefreshToken')
```

Verifique que ambas variables tengan contenido (no vacío):

```bash
echo "ACCESS_TOKEN length: ${#ACCESS_TOKEN}"
echo "REFRESH_TOKEN length: ${#REFRESH_TOKEN}"
```

**Evidencia a guardar**: el login exitoso (el JSON de `TOKENS_JSON` o al menos confirmación de que `ACCESS_TOKEN`/`REFRESH_TOKEN` no están vacíos).

#### Paso 3 — Probar el endpoint protegido con `ACCESS_TOKEN`

Endpoint protegido para el experimento: `POST <ApiGatewayUrl>/ventas`.

```bash
curl -i -X POST "$API_BASE_URL/ventas" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"items":[{"productoId":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","cantidad":1}]}'
```

Resultado esperado: código `2xx` (la request es aceptada porque el token es válido).

**Evidencia a guardar**: la respuesta completa del `curl -i` (código de estado + cuerpo).

#### Paso 4 — Como "atacante", reemitir access tokens usando`REFRESH_TOKEN`

Simule que un atacante ya tiene el `REFRESH_TOKEN` (en este ejercicio, usted mismo) y lo usa para pedir un access token nuevo, sin volver a autenticarse con usuario/contraseña:

```bash
NEW_JSON=$(aws cognito-idp initiate-auth \
  --client-id "$APP_CLIENT_ID" \
  --auth-flow REFRESH_TOKEN_AUTH \
  --auth-parameters REFRESH_TOKEN="$REFRESH_TOKEN")

export ATTACKER_ACCESS_TOKEN=$(echo "$NEW_JSON" | jq -r '.AuthenticationResult.AccessToken')
```

Use ese nuevo token contra el mismo endpoint protegido:

```bash
curl -i -X POST "$API_BASE_URL/ventas" \
  -H "Authorization: Bearer $ATTACKER_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"items":[{"productoId":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","cantidad":1}]}'
```

**Repitan este paso (refrescar + llamar al endpoint) al menos 2-3 veces**, para dejar evidencia de que el "atacante" puede emitir nuevos access tokens **repetidamente** mientras el refresh token siga vigente y no haya sido revocado.

**Evidencia a guardar**: cada iteración de refresh (el `NEW_JSON` o al menos confirmación de que `ATTACKER_ACCESS_TOKEN` cambió) y la respuesta `2xx` del endpoint en cada una.

## Cierre de la sesión

Al terminar los 4 pasos, cada estudiante debe tener:

- El `ACCESS_TOKEN` y `REFRESH_TOKEN` originales, capturados (Paso 2).
- Evidencia de la llamada exitosa al endpoint protegido con `ACCESS_TOKEN` (Paso 3).
- Evidencia de que el "atacante" pudo emitir nuevos access tokens repetidamente usando `REFRESH_TOKEN`, y que cada uno de esos tokens funcionó contra el endpoint protegido (Paso 4).

Esto es exactamente la sección "6. Parte 1 — Incidente" del laboratorio — **no hay que rehacerlo después**, se sigue directamente con la contención (revocación) en la Parte 2 (sección 7 del enunciado, `lab_6_jwt_revocacion.md`).
