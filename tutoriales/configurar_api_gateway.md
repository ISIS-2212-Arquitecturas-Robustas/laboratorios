# Configurar API Gateway para microservicios de Cheapest

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

> [!IMPORTANT]
> El nombre del stage (`lab`) no es solo una etiqueta: en HTTP API queda como **prefijo de ruta** en la URL de invocacion. Todas las rutas creadas (`/<prefijo_servicio>/health`, `/<prefijo_servicio>/{proxy+}`) quedan disponibles bajo `/dev/...`, no en la raiz del dominio. Es decir, la ruta real es `https://<API_ID>.execute-api.<REGION>.amazonaws.com/dev/logistics/health`, **no** `.../logistics/health`. Si olvida el `/dev` al probar o al configurar JMeter, obtendra 404 aunque la integracion este bien configurada.

## Tutorial consola AWS

Si prefiere interfaz grafica, puede apoyarse en:
[Crear APIs HTTP en API Gateway](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api.html)

## Tutorial CloudShell (AWS CLI)

### 0. Configuracion objetivo

| Parámetro | Valor sugerido |
| --- | --- |
| Tipo API | HTTP API |
| Nombre API | `Cheapest-ms-api` |
| Stage | `lab` |
| Endpoint backend | `http://<ALB_DNS>:<PUERTO_CONTENEDOR>` (DNS del ALB, ver el [tutorial del ALB](./configurar_alb_para_ecs.md)) |

> [!NOTE]
> Las integraciones apuntan al **DNS del ALB** y no a la IP de una tarea. El DNS del ALB no cambia cuando las tareas se reinician o se escalan (el ALB se encarga de encontrarlas), así que no tendrá que actualizar las integraciones por ese motivo. Solo tendría que hacerlo si elimina y vuelve a crear el ALB.

### 1. Crear API HTTP

```bash
aws apigatewayv2 create-api  --name Cheapest-ms-api  --protocol-type HTTP
```

Guarde:

- `API_ID`

### 2. Crear integracion HTTP hacia backend
```bash
# Integracion de negocio (ANY, con proxy de ruta)
aws apigatewayv2 create-integration  --api-id <API_ID>  --integration-type HTTP_PROXY  --integration-method ANY  --integration-uri "http://<ALB_DNS>:<PUERTO>/<PREFIJO_SERVICIO>/{proxy}"  --payload-format-version 1.0
```

```bash
# Integracion de health (GET, ruta fija)
aws apigatewayv2 create-integration  --api-id <API_ID>  --integration-type HTTP_PROXY  --integration-method GET  --integration-uri "http://<ALB_DNS>:<PUERTO>/health"  --payload-format-version 1.0
```

Guarde el `IntegrationId` de cada una.

### 3. Crear las rutas de cada servicio

Una **ruta** le dice a API Gateway qué peticiones (método + ruta) debe reenviar a una integración. Por cada servicio solo necesita **dos rutas**, no una por cada endpoint que vaya a probar:

- **Ruta de negocio:** una sola ruta con `{proxy+}` cubre **todos** los endpoints del servicio. `{proxy+}` significa "cualquier sub-ruta que siga a este prefijo", así que no debe crear rutas adicionales para cada endpoint: por ejemplo, la ruta de `logistics` ya reenvía `GET /logistics/tenderos/productos-disponibles`, `POST /logistics/pedidos` y cualquier otro endpoint de Logística.
- **Ruta de health:** existe aparte solo porque el endpoint de health del contenedor está en `/health` (en la raíz, sin el prefijo del servicio), mientras que la ruta de negocio reenvía a `/<PREFIJO_SERVICIO>/...`. Si el health pasara por la ruta de negocio, llegaría a `/<PREFIJO_SERVICIO>/health`, que no existe en el contenedor. Por eso tiene su propia integración con la URI fija `/health`. Cuando una petición coincide con ambas rutas, API Gateway usa la más específica, es decir, la de health.

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
aws apigatewayv2 create-stage  --api-id <API_ID>  --stage-name lab  --auto-deploy
```

### 5. Obtener URL de invocacion

```bash
aws apigatewayv2 get-api --api-id <API_ID> --query "ApiEndpoint" --output text
```

La URL final sera:

```text
https://<API_ID>.execute-api.<REGION>.amazonaws.com/lab
```

### 6. Probar endpoints

Health (ruta fija, un ejemplo por servicio):

```bash
curl "https://<API_ID>.execute-api.<REGION>.amazonaws.com/lab/<PREFIJO_SERVICIO>/health"
```

GET de negocio (via proxy, ejemplo con `logistics`):

```bash
curl "https://<API_ID>.execute-api.<REGION>.amazonaws.com/lab/logistics/tenderos/productos-disponibles?tiendaId=<UUID_V4>&zona=<ZONA>"
```

POST de negocio (via proxy, ejemplo con `logistics`):

```bash
curl -X POST "https://<API_ID>.execute-api.<REGION>.amazonaws.com/lab/logistics/pedidos"  -H "Content-Type: application/json"  -d '{"identificador":"PED-001","tiendaId":"<UUID>","fechaHoraCreacion":"2026-07-02T00:00:00.000Z","montoTotal":100,"monedaId":"<UUID>","items":[{"productoId":"<UUID>","cantidad":10,"precioUnitario":10,"descuento":0,"monedaId":"<UUID>"}]}'
```

> [!NOTE]
> Los endpoints de escritura (POST) de Cheapest referencian entidades existentes por UUID (tienda, moneda, producto). Antes de poder probar un POST exitoso necesita datos base cargados en la RDS (vea el script `npm run db:seed` del repositorio, o cree primero los recursos padres via API). Si no tiene datos base, el POST fallara con un error de base de datos (no de conectividad) — eso igual confirma que la ruta y la integracion de API Gateway estan bien configuradas.

### 7. Si la dirección del backend cambia: actualizar la integración

Una **integración** es lo que le dice a API Gateway a qué dirección reenviar las peticiones de una ruta (en este laboratorio, `http://<ALB_DNS>:<PUERTO>/...`). Como el DNS del ALB es estable, normalmente no tendrá que tocarla. Solo es necesario si el backend cambia de dirección, por ejemplo si elimina y vuelve a crear el ALB (su DNS cambia). En ese caso, las rutas y el stage no se tocan: solo se cambia la dirección de la integración.

1. **Obtenga el DNS del ALB nuevo:**

   ```bash
   aws elbv2 describe-load-balancers --names Cheapest-alb --query "LoadBalancers[0].DNSName" --output text
   ```

2. **Ubique las integraciones que debe actualizar.** Liste las integraciones de la API:

   ```bash
   aws apigatewayv2 get-integrations --api-id <API_ID> --query "Items[].{Id:IntegrationId,Uri:IntegrationUri}" --output table
   ```

   Cada servicio tiene dos integraciones. Identifíquelas por su `Uri`: la de negocio termina en `/<PREFIJO_SERVICIO>/{proxy}` y la de health termina en `/health`. Use el puerto (3001, 3002 o 3003) para saber a qué servicio pertenece cada una y anote su `Id`.
3. **Actualice cada una con el DNS nuevo** (la de negocio y la de health de cada servicio):

   ```bash
   # Integración de negocio
   aws apigatewayv2 update-integration --api-id <API_ID> --integration-id <INTEGRATION_ID_NEGOCIO> --integration-uri "http://<NUEVO_ALB_DNS>:<PUERTO>/<PREFIJO_SERVICIO>/{proxy}"

   # Integración de health
   aws apigatewayv2 update-integration --api-id <API_ID> --integration-id <INTEGRATION_ID_HEALTH> --integration-uri "http://<NUEVO_ALB_DNS>:<PUERTO>/health"
   ```

4. **Verifique.** Como el stage se creó con `--auto-deploy`, el cambio se publica solo (no hay que crear un deployment). Pruebe de nuevo el health del servicio:

   ```bash
   curl "https://<API_ID>.execute-api.<REGION>.amazonaws.com/lab/<PREFIJO_SERVICIO>/health"
   ```

## Resultado final

Al terminar debe tener:

| Recurso | Nombre sugerido | Resultado |
| --- | --- | --- |
| HTTP API | `Cheapest-ms-api` | Creada |
| Rutas de negocio | `ANY /<prefijo>/{proxy+}` por servicio | Integradas |
| Rutas de health | `GET /<prefijo>/health` por servicio | Integradas |
| Stage | `lab` | Desplegado |
| URL de invocacion | `https://<API_ID>.execute-api.../lab` | Lista para JMeter |

## Limpiar recursos (opcional)

Eliminar API completa:

```bash
aws apigatewayv2 delete-api --api-id <API_ID>
```
