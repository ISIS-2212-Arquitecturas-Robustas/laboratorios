# Warm-up en clase — Lab 5: Disponibilidad en Microservicios (Circuit Breaker, Retry, Rate Limiting)

## 4. Preparación: IaaC con CloudFormation

### 4.1 ¿Qué es Infraestructura como Código?

En los labs anteriores, la infraestructura se creó paso a paso desde la consola de AWS: security groups, instancias EC2, RDS, ECS, API Gateway. Este enfoque manual tiene un problema: es propenso a errores, difícil de reproducir y no deja registro de qué se configuró exactamente.

**Infraestructura como Código (IaaC)** resuelve esto declarando la infraestructura en un archivo de texto (código), que puede versionarse, revisarse y ejecutarse de forma reproducible. **AWS CloudFormation** es el servicio nativo de AWS para esto: usted define un *template* YAML o JSON que describe los recursos, y CloudFormation se encarga de crearlos, actualizarlos o eliminarlos.

### 4.2 Template CloudFormation del laboratorio

Se provee el archivo `lab_5/recursos/cloudformation_template.yaml` con toda la infraestructura del laboratorio declarada. Lea el template antes de ejecutarlo: cada sección tiene comentarios que explican qué recurso crea y por qué.

El template incluye:

| Sección            | Recursos creados                                                              |
| ------------------ | ------------------------------------------------------------------------------- |
| `Parameters`       | ARNs de imágenes ECR, credenciales RDS, VPC/subnets                           |
| `VPC y Networking` | VPC, subnets públicas/privadas, Internet Gateway, Security Groups             |
| `RDS`              | Instancia PostgreSQL, subnet group, security group de base de datos           |
| `ECS Cluster`      | Cluster Fargate compartido, roles IAM de ejecución                            |
| `Task Definitions` | Una por servicio (Logistica, Inventario, Ventas) con variables de entorno     |
| `ECS Services`     | Un servicio ECS por Task Definition, conectado a su ALB                       |
| `Load Balancers`   | ALB por servicio con Target Groups y Health Checks                            |
| `API Gateway`      | HTTP API con rutas `/logistica/*`, `/inventario/*`, `/ventas/*` y stage `lab` |

### 4.3 Preparar parámetros

Antes de desplegar, publique las imágenes Docker en ECR y anote los URIs. En este laboratorio hay **cuatro imágenes**: las tres del monorepo más la del sidecar Envoy.

| Servicio          | Repositorio sugerido     | Tag     | Dockerfile                          |
| ----------------- | ------------------------ | ------- | ----------------------------------- |
| Logística         | `Cheapest-logistica`       | `2.0.0` | `apps/logistica/Dockerfile`         |
| Inventario        | `Cheapest-inventario`      | `2.0.0` | `apps/inventario/Dockerfile`        |
| Ventas            | `Cheapest-ventas`          | `2.0.0` | `apps/ventas/Dockerfile`            |
| Ventas sidecar    | `Cheapest-ventas-sidecar`  | `1.0.0` | `apps/ventas/sidecar/Dockerfile`    |

Tutorial de apoyo:
- [Subir imágenes Docker a Amazon ECR](../tutoriales/subir_imagenes%20_a_ecr.md)

> Use el tag `2.0.0` para distinguir las imágenes con las modificaciones de este lab de las del Lab 4. La rama de trabajo para este laboratorio es **`availability`**.
> Recuerde que debe construir el sidecar como una imagen Docker aparte, usando el Dockerfile en `apps/ventas/sidecar/`, y subirla a ECR también.

### 4.4 Desplegar el stack

```bash
aws cloudformation deploy  --template-file lab_5/recursos/cloudformation_template.yaml  --stack-name Cheapest-lab5  --parameter-overrides LogisticaImageUri=<URI_ECR_LOGISTICA>:2.0.0 InventarioImageUri=<URI_ECR_INVENTARIO>:2.0.0 VentasImageUri=<URI_ECR_VENTAS>:2.0.0  VentasSidecarImageUri=<URI_ECR_SIDECAR>:2.0.0 DBPassword=<SU_CONTRASEÑA>  --region us-east-1
```

Monitoree el progreso en la consola de AWS → CloudFormation → Stack `Cheapest-lab5` → pestaña **Events**.

### 4.5 Verificar el despliegue

Una vez el stack esté en estado `CREATE_COMPLETE`:

```bash
# Obtener la URL del API Gateway
aws cloudformation describe-stacks --stack-name Cheapest-lab5 --query "Stacks[0].Outputs[?OutputKey=='ApiGatewayUrl'].OutputValue" --output text
```

Desde su computador verifique que los tres servicios responden:

```
GET https://<API_ID>.execute-api.<REGION>.amazonaws.com/lab/logistica/health
GET https://<API_ID>.execute-api.<REGION>.amazonaws.com/lab/inventario/health
GET https://<API_ID>.execute-api.<REGION>.amazonaws.com/lab/ventas/health
```

Los tres deben retornar HTTP 200 antes de continuar.

## 5. Configuración del sidecar y ajuste de código

Las modificaciones de este laboratorio se dividen en tres partes:

1. La inyección de fallos en Inventario (ya implementada en el código base).
2. La **configuración del sidecar Envoy** en Ventas: aquí es donde usted define los parámetros de retry y circuit breaker.
3. Un ajuste mínimo en el servicio de Ventas para la graceful degradation.

### 5.1 Lógica de inyección de fallos con auto-recuperación en Inventario

El servicio de Inventario ya incorpora un mecanismo de fallo transitorio controlado por dos variables de entorno:

- `FAULT_DELAY_MS`: delay artificial en ms que se agrega a cada respuesta durante el período de fallo.
- `RECOVERY_TIME_MS`: tiempo en ms desde el arranque del proceso hasta que el servicio se recupera automáticamente.

Este código ya existe en `apps/inventario/src/fault.middleware.ts` y se aplica en el endpoint `GET /inventory/items/disponibilidad/:productoId` que Ventas consume. No es necesario modificarlo.

### 5.2 El sidecar Envoy: arquitectura y flujo

El directorio `apps/ventas/sidecar/` contiene tres archivos:

| Archivo            | Rol                                                                              |
| ------------------ | -------------------------------------------------------------------------------- |
| `Dockerfile`       | Imagen base `envoyproxy/envoy:v1.31` + `gettext-base` para la sustitución de variables |
| `entrypoint.sh`    | Al arrancar, sustituye `${INVENTARIO_UPSTREAM_HOST}` y `${INVENTARIO_UPSTREAM_PORT}` en el template y lanza Envoy |
| `envoy.yaml.tmpl`  | Configuración de Envoy con los parámetros de retry y circuit breaker — **usted debe completar los valores marcados con `???`** |

**Variables de entorno del sidecar:**

| Variable                   | docker-compose         | ECS (mismo task)          |
| -------------------------- | ---------------------- | ------------------------- |
| `INVENTARIO_UPSTREAM_HOST` | `inventario`           | `<ALB DNS de inventario>` |
| `INVENTARIO_UPSTREAM_PORT` | `3002`                 | `80`                      |

**Variable de entorno del contenedor ventas:**

| Variable              | Valor en ECS          | Por qué                                              |
| --------------------- | --------------------- | ---------------------------------------------------- |
| `INVENTARIO_BASE_URL` | `http://localhost:10000` | En ECS los containers del mismo task comparten la red; el sidecar escucha en ese puerto |
| `INVENTARIO_TIMEOUT_MS` | `9000`              | Debe ser mayor que el timeout total del sidecar para no abortar antes de que Envoy resuelva los reintentos |

### 5.3 Completar la configuración de Envoy

Abra `apps/ventas/sidecar/envoy.yaml.tmpl`. Encontrará seis parámetros marcados con `???` y un comentario `TODO` que explica el criterio de diseño de cada uno. Debe reemplazar cada `???` con el valor que usted considera correcto.

Los seis puntos a completar son:

| # | Parámetro Envoy          | Sección              | Qué controla                                                                 |
| - | ------------------------ | --------------------- | ------------------------------------------------------------------------------ |
| 1 | `timeout`                | `route`              | Tiempo máximo total que el sidecar espera por una respuesta (incluyendo todos los reintentos) |
| 2 | `num_retries`            | `retry_policy`       | Número máximo de reintentos ante errores 5xx                                 |
| 3 | `base_interval`          | `retry_back_off`     | Espera base entre reintentos (Envoy añade ±25% de jitter automáticamente)    |
| 4 | `max_interval`           | `retry_back_off`     | Espera máxima entre reintentos                                               |
| 5 | `consecutive_5xx`        | `outlier_detection`  | Errores 5xx consecutivos que abren el circuito (estado OPEN)                 |
| 6 | `base_ejection_time`     | `outlier_detection`  | Tiempo que el circuito permanece OPEN antes de intentar HALF-OPEN            |

**Restricciones de calibración** (úselas para justificar sus valores en la sección de análisis):

- `timeout` de la ruta ≥ `connect_timeout` × (1 + `num_retries`) + backoff acumulado; de lo contrario los reintentos son abortados por el propio sidecar.
- `num_retries` × factor de amplificación ≤ 2× tráfico baseline (ASR-2).
- `base_ejection_time` < `RECOVERY_TIME_MS` de Inventario, para que el estado HALF-OPEN pueda detectar la recuperación automática del servicio.

**Verificar la configuración de Envoy localmente antes de subir a ECR:**

```bash
# Construir la imagen del sidecar
docker build -t Cheapest-ventas-sidecar:local apps/ventas/sidecar/

# Lanzar el sidecar apuntando a un inventario local (para verificar que el YAML es válido)
docker run --rm \
  -e INVENTARIO_UPSTREAM_HOST=host.docker.internal \
  -e INVENTARIO_UPSTREAM_PORT=3002 \
  -p 10000:10000 -p 9901:9901 \
  Cheapest-ventas-sidecar:local

# En otra terminal: verificar que Envoy está listo
curl http://localhost:9901/ready
```

Si el YAML tiene errores de sintaxis o valores inválidos (como `???` sin reemplazar), Envoy imprimirá el error y saldrá. Corrija antes de publicar la imagen.

### 5.4 Ajuste de código: graceful degradation en Ventas

El sidecar maneja la capa de red. La decisión de negocio —qué responder al cliente cuando Inventario está caído— debe estar en el código de Ventas.

Cuando el circuito está OPEN, el sidecar devuelve HTTP 503 a Ventas. El cliente HTTP (`InventarioDisponibilidadClient`) convierte ese 503 en una excepción `ServiceUnavailableException`. Sin manejo explícito, esa excepción se propaga y Ventas retorna 503 al tendero.

Este cambio ya está aplicado en la rama `availability` (en `libs/ventas/src/services/venta.service.ts`): revise el archivo para entender la implementación completa antes de continuar.

### 5.5 Variables de entorno adicionales

Actualice las Task Definitions del template CloudFormation con las siguientes variables:

| Servicio          | Variable                   | Valor para pruebas                                                         |
| ----------------- | --------------------------- | ---------------------------------------------------------------------------- |
| Inventario        | `FAULT_DELAY_MS`           | `0` (baseline) / `5000` (degradado: 5s de delay)                           |
| Inventario        | `RECOVERY_TIME_MS`         | `600000` (el servicio se recupera 10 minutos después de arrancar)          |
| Ventas            | `INVENTARIO_BASE_URL`      | `http://localhost:10000` (apunta al sidecar en ECS)                        |
| Ventas            | `INVENTARIO_TIMEOUT_MS`    | `9000`                                                                     |
| Ventas sidecar    | `INVENTARIO_UPSTREAM_HOST` | `<ALB DNS del servicio de Inventario>`                                     |
| Ventas sidecar    | `INVENTARIO_UPSTREAM_PORT` | `80`                                                                       |

> Configure `base_ejection_time` del sidecar en un valor inferior a `RECOVERY_TIME_MS` (600s) para que el estado HALF-OPEN pueda detectar la recuperación automática de Inventario.

## 6. Parte 1 — Reproducir el fallo en cascada

### 6.1 Configurar el fallo

1. En la consola de AWS → ECS → Task Definition `td-Cheapest-inventario`, cree una nueva revisión con:
   - `FAULT_DELAY_MS=5000`
   - `RECOVERY_TIME_MS=600000`
2. Actualice el servicio ECS de Inventario para que use la nueva revisión y espere que las tareas sean reemplazadas.
3. Asegúrese de que **el task de Ventas esté desplegado sin el sidecar** para este baseline: use la Task Definition con un solo container (ventas) y `INVENTARIO_BASE_URL` apuntando directamente al ALB de Inventario.

> Con esta configuración, Inventario arrancará degradado y responderá con 5s de delay. Pasados 10 minutos desde el arranque, se recuperará automáticamente. Anote el momento exacto de arranque de la tarea (visible en ECS → Tasks → Started at) para correlacionarlo con las métricas de JMeter.

### 6.2 Pruebas de carga

Ejecute JMeter con carga sobre `POST /ventas`. El endpoint de Ventas hace una llamada interna a Inventario, que ahora responde con 5 segundos de delay. Las métricas clave serán visibles desde CloudWatch.

**Abrir CloudWatch (consola AWS):**

1. Verifique la región: arriba a la derecha seleccione **us-east-1** (la misma región donde desplegó el stack).
2. En la consola de AWS use el buscador y abra **CloudWatch**.
3. En el menú izquierdo: **Metrics** → **All metrics**.

**Ver requests y errores hacia Inventario (vía ALB/Target Group):**

1. En **All metrics** seleccione el namespace **ApplicationELB**.
2. Abra **TargetGroup, LoadBalancer** (o similar). Si no lo ve, pruebe también **LoadBalancer**.
3. Identifique el *target group* de Inventario (normalmente incluye "inventario" en el nombre) y marque estas métricas:
   - `RequestCount` (tráfico total hacia el target group)
   - `HTTPCode_Target_5XX_Count` (errores 5xx generados por el servicio)
   - `TargetResponseTime` (latencia del target vista por el ALB; no reemplaza el p99 de JMeter, pero ayuda a correlacionar)
4. En el gráfico, ajuste:
   - **Time range** al intervalo exacto de su prueba JMeter
   - **Period** a 1 minuto (recomendado) para ver cambios con claridad
   - **Statistic**: `Sum` para `RequestCount` y `HTTPCode_Target_5XX_Count`

> Para estimar *requests/s* desde CloudWatch: si su `RequestCount` es por minuto (period=60s), entonces $\text{req/s} \approx \text{RequestCount}/60$.

| Test | Ramp-Up | Threads | Loops |
| --- | --- | --- | --- |
| Baja carga | 10s | 50 | 1 |
| Carga media | 20s | 200 | 1 |
| Operación normal | 50s | 500 | 1 |
| Alta carga | 75s | 1500 | N/A |

Registre para cada escenario: p99, error %, throughput total, y throughput recibido por Inventario (visible en CloudWatch).

### 6.3 Qué observar

- Latencia de Ventas: ¿cómo se propaga el delay de 5s de Inventario?
- Error % de Ventas: ¿empieza a devolver errores 500 o 503?
- Requests totales a Inventario: ¿aumentan con el tiempo?
- **Recuperación espontánea**: ¿qué sucede con la latencia de Ventas a los 600s del arranque de Inventario? ¿El sistema se recupera solo? ¿Cuánto tarda Ventas en notar que Inventario ya está bien?
- Punto de colapso: ¿a partir de cuántos threads el sistema deja de responder?

> Anote estos valores como Base. Son el punto de comparación para las tácticas. La recuperación espontánea en el baseline es el caso de control: sin circuit breaker, el sistema se recupera cuando Inventario se recupera, pero el tiempo de recuperación percibido por Ventas puede ser mayor de lo esperado.

## Cierre de la sesión

Al terminar, cada equipo debe tener: el stack de CloudFormation desplegado y verificado (sección 4), los 6 parámetros del sidecar calibrados y verificados localmente (sección 5), y la tabla de métricas baseline del fallo en cascada sin protecciones (sección 6). Esto es exactamente lo que pide el laboratorio antes de aplicar las tácticas de resiliencia — no hay que rehacerlo después, se sigue directamente con la Parte 2.
