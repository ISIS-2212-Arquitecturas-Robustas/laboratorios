# Warm-up en clase — Lab 5: Disponibilidad en Microservicios (experimentos de caos con Circuit Breaker, Retry, Rate Limiting)

## Preparación: IaaC con CloudFormation

### ¿Qué es Infraestructura como Código?

En los labs anteriores, la infraestructura se creó paso a paso desde la consola de AWS: security groups, instancias EC2, RDS, ECS, API Gateway. Este enfoque manual tiene un problema: es propenso a errores, difícil de reproducir y no deja registro de qué se configuró exactamente.

**Infraestructura como Código (IaaC)** resuelve esto declarando la infraestructura en un archivo de texto (código), que puede versionarse, revisarse y ejecutarse de forma reproducible. **AWS CloudFormation** es el servicio nativo de AWS para esto: usted define un *template* YAML o JSON que describe los recursos, y CloudFormation se encarga de crearlos, actualizarlos o eliminarlos.

### Template CloudFormation del laboratorio

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

### Preparar parámetros

Antes de desplegar, publique las imágenes Docker en ECR y anote los URIs. En este laboratorio hay **cuatro imágenes**: las tres del monorepo más la del sidecar Envoy.

| Servicio          | Repositorio sugerido     | Tag     | Dockerfile                          |
| ----------------- | ------------------------ | ------- | ----------------------------------- |
| Logística         | `cheapest-logistica`       | `2.0.0` | `apps/logistica/Dockerfile`         |
| Inventario        | `cheapest-inventario`      | `2.0.0` | `apps/inventario/Dockerfile`        |
| Ventas            | `cheapest-ventas`          | `2.0.0` | `apps/ventas/Dockerfile`            |
| Ventas sidecar    | `cheapest-ventas-sidecar`  | `1.0.0` | `apps/ventas/sidecar/Dockerfile`    |

Tutorial de apoyo:
- [Subir imágenes Docker a Amazon ECR](../tutoriales/subir_imagenes%20_a_ecr.md)

> Use el tag `2.0.0` para distinguir las imágenes con las modificaciones de este lab de las del Lab 4. La rama de trabajo para este laboratorio es **`availability`**.
> Recuerde que debe construir el sidecar como una imagen Docker aparte, usando el Dockerfile en `apps/ventas/sidecar/`, y subirla a ECR también.

### Desplegar el stack

```bash
aws cloudformation deploy  --template-file lab_5/recursos/cloudformation_template.yaml  --stack-name Cheapest-lab5  --parameter-overrides LogisticaImageUri=<URI_ECR_LOGISTICA>:2.0.0 InventarioImageUri=<URI_ECR_INVENTARIO>:2.0.0 VentasImageUri=<URI_ECR_VENTAS>:2.0.0  VentasSidecarImageUri=<URI_ECR_SIDECAR>:1.0.0 DBPassword=<SU_CONTRASEÑA>  --region us-east-1
```

Monitoree el progreso en la consola de AWS → CloudFormation → Stack `Cheapest-lab5` → pestaña **Events**.

### Verificar el despliegue

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

## Configuración del sidecar y ajuste de código

Las modificaciones de este laboratorio se dividen en tres partes:

1. La inyección de fallos en Inventario (ya implementada en el código base).
2. La **configuración del sidecar Envoy** en Ventas: aquí es donde usted define los parámetros de retry y circuit breaker.
3. Un ajuste mínimo en el servicio de Ventas para la graceful degradation.

### Herramientas para inyectar fallos

En este laboratorio el experimento no es una prueba de carga: el tráfico es bajo y constante, y lo que se manipula es el **fallo**. Para eso el código base trae un endpoint de caos en Inventario, que enciende y apaga un fallo en segundos sin redesplegar. El fallo afecta solo la consulta de disponibilidad que hace Ventas (`GET /inventory/items/disponibilidad/:productoId`):

```bash
# Latencia de 5 s durante 3 minutos (se retira sola al cumplirse durationMs)
curl -s -X POST $BASE_URL/inventario/chaos -H 'Content-Type: application/json' \
  -d '{"mode": "latency", "delayMs": 5000, "durationMs": 180000}'

# Retirar el fallo de inmediato
curl -s -X POST $BASE_URL/inventario/chaos -H 'Content-Type: application/json' -d '{"mode": "off"}'

# Estado actual y contador de llamadas de disponibilidad
curl -s $BASE_URL/inventario/chaos
```

El código está en `apps/inventario/src/chaos.controller.ts` y `fault.middleware.ts`. No es necesario modificarlo. Los demás mecanismos (apagar el sidecar, detener tareas, reiniciar la base) se presentan en la sección 5.8 del enunciado.

### El sidecar Envoy: arquitectura y flujo

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

### Completar la configuración de Envoy

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

**Restricciones de calibración** (úselas para justificar los valores que escoja):

- `timeout` de la ruta ≥ `connect_timeout` × (1 + `num_retries`) + backoff acumulado; de lo contrario los reintentos son abortados por el propio sidecar.
- `1 + num_retries` ≤ 2: en el peor caso cada venta genera `1 + num_retries` llamadas a Inventario, y el ASR-2 exige que no reciba más del doble que sin reintentos.
- `base_ejection_time` < duración del fallo inyectado (`durationMs`), para que el estado HALF-OPEN pueda detectar la recuperación del servicio.

**Verificar la configuración de Envoy localmente antes de subir a ECR:**

```bash
# Construir la imagen del sidecar
docker build -t cheapest-ventas-sidecar:local apps/ventas/sidecar/

# Lanzar el sidecar apuntando a un inventario local (para verificar que el YAML es válido)
docker run --rm \
  -e INVENTARIO_UPSTREAM_HOST=host.docker.internal \
  -e INVENTARIO_UPSTREAM_PORT=3002 \
  -p 10000:10000 -p 9901:9901 \
  cheapest-ventas-sidecar:local

# En otra terminal: verificar que Envoy está listo
curl http://localhost:9901/ready
```

Si el YAML tiene errores de sintaxis o valores inválidos (como `???` sin reemplazar), Envoy imprimirá el error y saldrá. Corrija antes de publicar la imagen.

### Ajuste de código: graceful degradation en Ventas

El sidecar maneja la capa de red. La decisión de negocio —qué responder al cliente cuando Inventario está caído— debe estar en el código de Ventas.

Cuando el circuito está OPEN, el sidecar devuelve HTTP 503 a Ventas. El cliente HTTP (`InventarioDisponibilidadClient`) convierte ese 503 en una excepción `ServiceUnavailableException`. Sin manejo explícito, esa excepción se propaga y Ventas retorna 503 al tendero.

Este cambio ya está aplicado en la rama `availability` (en `libs/ventas/src/services/venta.service.ts`): revise el archivo para entender la implementación completa antes de continuar.

### Variables de entorno

El template de CloudFormation ya configura todas las variables de las tareas; no tiene que escribirlas a mano:

| Servicio          | Variable                   | Valor en el template                                                       |
| ----------------- | --------------------------- | ---------------------------------------------------------------------------- |
| Inventario        | `FAULT_DELAY_MS`           | `0` (arranca sano; los fallos se inyectan con el endpoint de caos)          |
| Ventas            | `INVENTARIO_BASE_URL`      | `http://localhost:10000` (apunta al sidecar en ECS)                        |
| Ventas            | `INVENTARIO_TIMEOUT_MS`    | `9000`                                                                     |
| Ventas            | `SIDECAR_ADMIN_URL`        | `http://localhost:9901` (puerto de administración de Envoy)                |
| Ventas            | `OUTBOX_MAX_ATTEMPTS`      | `600`                                                                      |
| Ventas sidecar    | `INVENTARIO_UPSTREAM_HOST` | `<ALB DNS del servicio de Inventario>`                                     |
| Ventas sidecar    | `INVENTARIO_UPSTREAM_PORT` | `80`                                                                       |

## Parte 1 — Primer experimento de caos: estado estable y fallo en cascada

En esta parte hace los dos primeros experimentos del catálogo del laboratorio, E0 (estado estable) y E1 con la configuración **sin sidecar** (grupo de control), para ver el fallo en cascada sin protecciones.

### Antes de empezar: las fichas

Escriba las fichas de E0 y de E1 sin sidecar (sección 4.4.3 del enunciado) **antes** de inyectar nada: estado estable que espera, hipótesis, radio de impacto esperado y condición de aborto. Discútalas con su grupo: ¿qué cree que le pasará a una venta cuando Inventario tarde 5 s, si Ventas lo espera hasta 9 s?

### Preparar los datos y el generador de tráfico

Siga la sección 5.6 del enunciado para sembrar la base, crear un producto externo y guardar `venta.json`. Luego reponga stock, porque el generador de tráfico vende 2 unidades por segundo:

```bash
curl -s -X PATCH $BASE_URL/inventario/items/11111111-1111-4111-8111-111111111111 \
  -H 'Content-Type: application/json' -d '{"cantidad": 100000}'
```

El **generador de tráfico** (`lab_5/recursos/generador_trafico.sh`) envía 2 ventas por segundo y, cada 5 s, consulta otros tres endpoints para medir el radio de impacto. Escribe un CSV con la hora, el endpoint, el código HTTP, la latencia y si la venta quedó `pending`. No es una prueba de carga: la carga es la misma en todos los experimentos.

### E0 — Estado estable

Con la configuración completa (la que creó CloudFormation), corra el generador de tráfico 5 minutos sin inyectar nada y resúmala por ventanas de 10 s:

```bash
BASE_URL=$BASE_URL ./lab_5/recursos/generador_trafico.sh e0.csv      # Ctrl+C a los 5 minutos
python3 lab_5/recursos/ventanas.py e0.csv
```

Anote la disponibilidad percibida (2xx en menos de 3 s), el p99 y el % de `pending` de las ventas: ese es el estado estable contra el que comparará todo lo demás.

### E1 sin sidecar — Inventario lento

1. Prepare la revisión **sin sidecar** de `td-Cheapest-ventas` (procedimiento B, paso 2, del enunciado) y despliéguela.
2. Arranque el generador de tráfico en una terminal (`./lab_5/recursos/generador_trafico.sh e1_sin_sidecar.csv`).
3. A los 2 minutos, anote el contador y la hora, e inyecte la latencia:
   ```bash
   curl -s $BASE_URL/inventario/chaos
   curl -s -X POST $BASE_URL/inventario/chaos -H 'Content-Type: application/json' \
     -d '{"mode": "latency", "delayMs": 5000, "durationMs": 180000}'
   ```
4. Observe durante los 3 minutos del fallo y 3 minutos más después de que se retire solo (la hora está en el campo `until`). Vuelva a leer el contador y detenga el generador de tráfico.
5. Resuma con `python3 lab_5/recursos/ventanas.py e1_sin_sidecar.csv`.

En CloudWatch (namespace **ApplicationELB**, target group de Inventario) revise `RequestCount`, `HTTPCode_Target_5XX_Count` y `TargetResponseTime` en el intervalo del experimento (Period de 1 minuto).

### Qué observar

- Latencia de Ventas: ¿cómo se propaga al generador de tráfico el retraso de 5 s de Inventario? ¿Cambia la disponibilidad percibida aunque las respuestas sigan siendo 201?
- Radio de impacto: ¿qué otros endpoints del generador de tráfico se afectaron?
- Llamadas por venta: ¿cuántas recibió Inventario por cada venta del generador de tráfico?
- **Recuperación**: ¿cuánto tardó Ventas en volver al estado estable después de que el fallo se retiró?

> Anote estos valores: son el grupo de control contra el que comparará las tácticas en el laboratorio. Sin sidecar, el sistema se recupera cuando Inventario se recupera, pero mientras tanto el tendero espera cada vez lo que tarde Inventario.


## Cierre de la sesión

Al terminar, cada estudiante debe tener: el stack de CloudFormation desplegado y verificado, los 6 parámetros del sidecar calibrados y verificados localmente, las fichas de E0 y E1, y los resultados de E0 y de E1 sin sidecar (CSV del generador de tráfico, tabla por ventanas y contador de llamadas). Esto es exactamente lo que pide el laboratorio para esos dos experimentos: no hay que rehacerlo después, se sigue directamente con las demás configuraciones de E1 y con el resto del catálogo.
