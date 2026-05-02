# Lab 6 — CLI de autenticación, refresh y revocación (Cognito)

Este documento soporta el ejercicio de incidente y contención del Lab 6.

## 0. Prerrequisitos

- AWS CLI configurada (`aws configure`) en la misma cuenta/región donde desplegó el stack.
- `jq` instalado (opcional, pero recomendado para extraer tokens).

Variables (reemplazar por outputs del stack):

```bash
export API_BASE_URL="<ApiGatewayUrl>"                # ej. https://xxxx.execute-api.us-east-1.amazonaws.com/lab
export USER_POOL_ID="<CognitoUserPoolId>"
export APP_CLIENT_ID="<CognitoUserPoolClientId>"
```

## 1. Crear usuario de prueba (admin)

Cree un usuario en Cognito (si prefiere, puede hacerlo desde consola).

```bash
aws cognito-idp admin-create-user \
  --user-pool-id "$USER_POOL_ID" \
  --username tendero1@example.com \
  --user-attributes Name=email,Value=tendero1@example.com Name=email_verified,Value=true
```

Defina contraseña permanente:

```bash
aws cognito-idp admin-set-user-password \
  --user-pool-id "$USER_POOL_ID" \
  --username tendero1@example.com \
  --password 'Lab6-Password#2026' \
  --permanent

Opcional: asignar el usuario a un grupo (para RBAC por `cognito:groups`):

```bash
aws cognito-idp admin-add-user-to-group \
  --user-pool-id "$USER_POOL_ID" \
  --username tendero1@example.com \
  --group-name operador
```
```

## 2. Login (obtener access + refresh)

> Este comando requiere que el App Client permita `USER_PASSWORD_AUTH` (el template del lab lo habilita).

```bash
aws cognito-idp initiate-auth \
  --client-id "$APP_CLIENT_ID" \
  --auth-flow USER_PASSWORD_AUTH \
  --auth-parameters USERNAME=tendero1@example.com,PASSWORD='Lab6-Password#2026'
```

Extraer tokens (si tiene `jq`):

```bash
TOKENS_JSON=$(aws cognito-idp initiate-auth \
  --client-id "$APP_CLIENT_ID" \
  --auth-flow USER_PASSWORD_AUTH \
  --auth-parameters USERNAME=tendero1@example.com,PASSWORD='Lab6-Password#2026')

export ACCESS_TOKEN=$(echo "$TOKENS_JSON" | jq -r '.AuthenticationResult.AccessToken')
export REFRESH_TOKEN=$(echo "$TOKENS_JSON" | jq -r '.AuthenticationResult.RefreshToken')
```

## 3. Probar endpoint protegido (ejemplo)

> El lab sugiere `POST /ventas` como endpoint protegido.

```bash
curl -i -X POST "$API_BASE_URL/ventas" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"items":[{"productoId":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","cantidad":1}]}'
```

## 4. Incidente: el atacante refresca tokens indefinidamente

Simule que el atacante roba el refresh token y emite nuevos access tokens:

```bash
aws cognito-idp initiate-auth \
  --client-id "$APP_CLIENT_ID" \
  --auth-flow REFRESH_TOKEN_AUTH \
  --auth-parameters REFRESH_TOKEN="$REFRESH_TOKEN"
```

Extraer nuevo access token (con `jq`):

```bash
NEW_JSON=$(aws cognito-idp initiate-auth \
  --client-id "$APP_CLIENT_ID" \
  --auth-flow REFRESH_TOKEN_AUTH \
  --auth-parameters REFRESH_TOKEN="$REFRESH_TOKEN")

export ATTACKER_ACCESS_TOKEN=$(echo "$NEW_JSON" | jq -r '.AuthenticationResult.AccessToken')
```

Y vuelva a llamar el endpoint:

```bash
curl -i -X POST "$API_BASE_URL/ventas" \
  -H "Authorization: Bearer $ATTACKER_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"items":[{"productoId":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","cantidad":1}]}'
```

## 5. Contención opción A: revocar refresh token

Revocar el refresh token (corta re-emisión):

```bash
aws cognito-idp revoke-token \
  --client-id "$APP_CLIENT_ID" \
  --token "$REFRESH_TOKEN"
```

Verifique que ya no se puede refrescar:

```bash
aws cognito-idp initiate-auth \
  --client-id "$APP_CLIENT_ID" \
  --auth-flow REFRESH_TOKEN_AUTH \
  --auth-parameters REFRESH_TOKEN="$REFRESH_TOKEN"
```

## 6. Contención opción B (recomendada): global sign-out

Cortar todas las sesiones del usuario (incluyendo refresh tokens):

```bash
aws cognito-idp admin-user-global-sign-out \
  --user-pool-id "$USER_POOL_ID" \
  --username tendero1@example.com
```

## 7. Medición de ventana de exposición

- Incluso tras revocar, un access token ya emitido puede seguir funcionando hasta expirar.
- La ventana máxima de exposición reportada debe ser aproximadamente el TTL configurado del access token (2–5 min).

Sugerencia práctica:

1. Revocar.
2. Intentar refrescar (debe fallar de inmediato).
3. Repetir una llamada con el access token ya emitido hasta que falle (401).
