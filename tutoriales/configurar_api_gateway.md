# Configurar API Gateway para microservicios de Chiper

## Objetivos

- Crear un API HTTP en Amazon API Gateway para exponer endpoints de los microservicios.
- Integrar rutas GET y POST con servicios desplegados en ECS.
- Publicar un stage y validar que el endpoint de entrada responda correctamente.

## Marco conceptual

### Amazon API Gateway

API Gateway es un servicio administrado para crear, publicar y proteger APIs. Permite centralizar autenticacion, ruteo, limitacion de trafico y observabilidad.

Mas informacion en: [Amazon API Gateway](https://docs.aws.amazon.com/apigateway/latest/developerguide/welcome.html)

### Stages

Un stage representa un entorno desplegado de la API (por ejemplo `dev`, `qa`, `prod`) y define una URL de invocacion.

## Tutorial consola AWS

Si prefiere interfaz grafica, puede apoyarse en:
[Crear APIs HTTP en API Gateway](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api.html)

## Tutorial CloudShell (AWS CLI)

### 0. Configuracion objetivo

| Parámetro | Valor sugerido |
| --- | --- |
| Tipo API | HTTP API |
| Nombre API | `chiper-api` |
| Stage | `dev` |
| Endpoint backend | `http://<IP_PRIVADA_SERVICIO>` |

### 1. Crear API HTTP

```bash
aws apigatewayv2 create-api  --name chiper-api  --protocol-type HTTP
```

Guarde:

- `API_ID`

### 2. Crear integracion HTTP hacia backend

```bash
aws apigatewayv2 create-integration  --api-id <API_ID>  --integration-type HTTP_PROXY  --integration-method ANY  --integration-uri http://<DNS_BACKEND>
```

Guarde:

- `INTEGRATION_ID`

### 3. Crear rutas para endpoints de prueba

Ejemplo para endpoint GET:

```bash
aws apigatewayv2 create-route  --api-id <API_ID>  --route-key "GET /<RUTA_GET>"  --target integrations/<INTEGRATION_ID>
```

Ejemplo para endpoint POST:

```bash
aws apigatewayv2 create-route  --api-id <API_ID>  --route-key "POST /<RUTA_POST>"  --target integrations/<INTEGRATION_ID>
```

### 4. Crear stage

```bash
aws apigatewayv2 create-stage  --api-id <API_ID>  --stage-name dev  --auto-deploy
```

### 5. Obtener URL de invocacion

```bash
aws apigatewayv2 get-api --api-id <API_ID> --query "ApiEndpoint" --output text
```

La URL final sera:

```text
https://<API_ID>.execute-api.<REGION>.amazonaws.com/dev
```

### 6. Probar endpoints

GET:

```bash
curl "https://<API_ID>.execute-api.<REGION>.amazonaws.com/dev/<RUTA_GET>"
```

POST:

```bash
curl -X POST "https://<API_ID>.execute-api.<REGION>.amazonaws.com/dev/<RUTA_POST>"  -H "Content-Type: application/json"  -d '{"items":[{"productoId":"1","cantidad":10}]}'
```

## Resultado final

Al terminar debe tener:

| Recurso | Nombre sugerido | Resultado |
| --- | --- | --- |
| HTTP API | `chiper-api` | Creada |
| Rutas | `GET /<RUTA_GET>`, `POST /<RUTA_POST>` | Integradas |
| Stage | `dev` | Desplegado |
| URL de invocacion | `https://<API_ID>.execute-api.../dev` | Lista para JMeter |

## Limpiar recursos (opcional)

Eliminar API completa:

```bash
aws apigatewayv2 delete-api --api-id <API_ID>
```
