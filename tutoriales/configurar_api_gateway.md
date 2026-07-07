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
| Endpoint backend | `http://<IP_PUBLICA_TAREA_ECS>:<PUERTO_CONTENEDOR>` |

> [!WARNING]
> En este laboratorio las tareas de ECS Fargate corren con `assignPublicIp=ENABLED` y **sin** balanceador de carga ni VPC Link, por lo que la integracion de API Gateway apunta directo a la IP publica de la tarea. Esto expone el contenedor directamente a internet en su puerto (por eso el security group de ECS debe permitir ese puerto desde `0.0.0.0/0`) y es fragil: **la IP publica cambia cada vez que la tarea se reinicia**. Si su endpoint deja de responder despues de funcionar, lo primero que debe revisar es si la tarea obtuvo una IP nueva (`aws ecs describe-tasks` + `aws ec2 describe-network-interfaces`) y actualizar la integracion con `aws apigatewayv2 update-integration.

### 1. Crear API HTTP

```bash
aws apigatewayv2 create-api  --name chiper-api  --protocol-type HTTP
```

Guarde:

- `API_ID`

### 2. Crear integracion HTTP hacia backend
```bash
# Integracion de negocio (ANY, con proxy de ruta)
aws apigatewayv2 create-integration  --api-id <API_ID>  --integration-type HTTP_PROXY  --integration-method ANY  --integration-uri "http://<IP_PUBLICA_TAREA>:<PUERTO>/<PREFIJO_SERVICIO>/{proxy}"  --payload-format-version 1.0
```

```bash
# Integracion de health (GET, ruta fija)
aws apigatewayv2 create-integration  --api-id <API_ID>  --integration-type HTTP_PROXY  --integration-method GET  --integration-uri "http://<IP_PUBLICA_TAREA>:<PUERTO>/health"  --payload-format-version 1.0
```

Guarde el `IntegrationId` de cada una.

### 3. Crear rutas para endpoints de prueba

Ruta de negocio (usa `{proxy+}` para reenviar cualquier sub-ruta del servicio, por ejemplo `GET /logistics/tenderos/productos-disponibles` o `POST /logistics/pedidos`):

```bash
aws apigatewayv2 create-route  --api-id <API_ID>  --route-key "ANY /<PREFIJO_SERVICIO>/{proxy+}"  --target integrations/<INTEGRATION_ID_NEGOCIO>
```

Ruta de health (fija, sin proxy):

```bash
aws apigatewayv2 create-route  --api-id <API_ID>  --route-key "GET /<PREFIJO_SERVICIO>/health"  --target integrations/<INTEGRATION_ID_HEALTH>
```

Repita ambos pasos (integracion + ruta) para cada uno de los tres microservicios.

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

Health (ruta fija, un ejemplo por servicio):

```bash
curl "https://<API_ID>.execute-api.<REGION>.amazonaws.com/dev/<PREFIJO_SERVICIO>/health"
```

GET de negocio (via proxy, ejemplo con `logistics`):

```bash
curl "https://<API_ID>.execute-api.<REGION>.amazonaws.com/dev/logistics/tenderos/productos-disponibles?tiendaId=<UUID_V4>&zona=<ZONA>"
```

POST de negocio (via proxy, ejemplo con `logistics`):

```bash
curl -X POST "https://<API_ID>.execute-api.<REGION>.amazonaws.com/dev/logistics/pedidos"  -H "Content-Type: application/json"  -d '{"identificador":"PED-001","tiendaId":"<UUID>","fechaHoraCreacion":"2026-07-02T00:00:00.000Z","montoTotal":100,"monedaId":"<UUID>","items":[{"productoId":"<UUID>","cantidad":10,"precioUnitario":10,"descuento":0,"monedaId":"<UUID>"}]}'
```

> [!NOTE]
> Los endpoints de escritura (POST) de Chiper referencian entidades existentes por UUID (tienda, moneda, producto). Antes de poder probar un POST exitoso necesita datos base cargados en la RDS (vea el script `npm run db:seed` del repositorio, o cree primero los recursos padres via API). Si no tiene datos base, el POST fallara con un error de base de datos (no de conectividad) — eso igual confirma que la ruta y la integracion de API Gateway estan bien configuradas.

## Resultado final

Al terminar debe tener:

| Recurso | Nombre sugerido | Resultado |
| --- | --- | --- |
| HTTP API | `chiper-api` | Creada |
| Rutas de negocio | `ANY /<prefijo>/{proxy+}` por servicio | Integradas |
| Rutas de health | `GET /<prefijo>/health` por servicio | Integradas |
| Stage | `dev` | Desplegado |
| URL de invocacion | `https://<API_ID>.execute-api.../dev` | Lista para JMeter |

## Limpiar recursos (opcional)

Eliminar API completa:

```bash
aws apigatewayv2 delete-api --api-id <API_ID>
```
