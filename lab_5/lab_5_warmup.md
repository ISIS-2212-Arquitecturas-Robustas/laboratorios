# Warm-up en clase — Lab 5: Disponibilidad en Microservicios (experimentos de caos con Circuit Breaker, Retry, Rate Limiting)

El laboratorio tiene dos fases: primero se corren todos los experimentos en su computador con Docker Compose, y después se confirman en AWS (lo explica la ruta del laboratorio, al comienzo de la ejecución en el enunciado). Este warm-up es el comienzo de la **fase local**: no necesita AWS ni consume créditos.

Al terminar la sesión debe tener el ambiente local arriba, el sidecar calibrado, las fichas de los experimentos de estado estable y de tormenta de reintentos, y los resultados del estado estable y de la tormenta sin sidecar.

## Parte 1 — Ambiente local y sidecar

### El sidecar Envoy: archivos y flujo

En este laboratorio Ventas no llama directamente a Inventario: llama a un **sidecar**, un proxy Envoy que corre junto a Ventas y le agrega reintentos y circuit breaker sin tocar el código de negocio. El directorio `apps/ventas/sidecar/` de la rama `availability` contiene tres archivos:

| Archivo            | Rol                                                                              |
| ------------------ | -------------------------------------------------------------------------------- |
| `Dockerfile`       | Imagen base `envoyproxy/envoy:v1.31` + `gettext-base` para la sustitución de variables |
| `entrypoint.sh`    | Al arrancar, sustituye `${INVENTARIO_UPSTREAM_HOST}` y `${INVENTARIO_UPSTREAM_PORT}` en el template y lanza Envoy |
| `envoy.yaml.tmpl`  | Configuración de Envoy con los parámetros de retry y circuit breaker — **usted debe completar los valores marcados con `???`** |

### Completar la configuración de Envoy

Abra `apps/ventas/sidecar/envoy.yaml.tmpl`. Encontrará seis parámetros marcados con `???` y un comentario `TODO` que explica el criterio de diseño de cada uno. Debe reemplazar cada `???` con el valor que usted considera correcto.

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
- `1 + num_retries` ≤ 2: cada venta genera como máximo `1 + num_retries` llamadas a Inventario, y el ASR de tormenta de reintentos exige que Inventario no reciba más de 2 consultas por pedido.
- `base_ejection_time` < duración del fallo inyectado (`durationMs`), para que el estado HALF-OPEN pueda detectar la recuperación del servicio.
- El ASR de degradación exige p99 < 3000 ms: una petición de prueba en HALF-OPEN que espera el `timeout` completo también cuenta en ese p99.

### Levantar el ambiente local

Use **`docker compose`** (con espacio, Docker Compose v2).

> [!WARNING]
> **Si ya usó Docker Compose en laboratorios anteriores con este mismo repositorio**, el volumen de la base local (`cheapest-api_postgres_data`) conserva el esquema de esas ramas y `npm run db:seed` falla (por ejemplo, con `column "tiendaIds" of relation "promociones" contains null values`). Empiece con una base limpia: `docker compose down -v` borra los contenedores **y la base local** de Docker Compose; después siga con `docker compose up -d --build`.

```bash
git checkout availability
docker compose up -d --build        # postgres, logística, inventario, sidecar y ventas
# Espere ~30 s a que los servicios creen las tablas
npm install
npm run db:seed

curl -i http://localhost:3002/health      # inventario
curl -i http://localhost:3003/health      # ventas
curl -s http://localhost:9901/ready       # sidecar Envoy: debe responder LIVE
```

Si el sidecar no responde `LIVE`, revise `docker compose logs ventas-sidecar`: lo más probable es un `???` sin reemplazar o un valor inválido en `envoy.yaml.tmpl`. Corríjalo y reconstruya solo el sidecar con `docker compose up -d --build ventas-sidecar`.

Desde su carpeta de trabajo local, defina las variables del ambiente local pegando este bloque en la terminal (los comandos del laboratorio usan `$INV`, `$VEN` e `$ITEM`, y los scripts leen las URLs de abajo). Las variables solo viven en esa terminal: péguelo también en cada terminal nueva que abra.

```bash
# Variables del ambiente local (Docker Compose): los servicios se llaman directamente
export AMBIENTE=local
export ITEM=11111111-1111-4111-8111-111111111111
export INV=http://localhost:3002/inventory
export INV_HEALTH=http://localhost:3002/health
export VEN=http://localhost:3003/ventas
# URLs que leen generador_trafico.sh y tormenta_reintentos.sh
export VENTA_URL=$VEN/ventas
export LOGISTICA_URL=http://localhost:3001/health
export INVENTARIO_URL=$INV/items/$ITEM
export CATALOGO_URL=$VEN/productos-externos
```

Cree un producto externo, guarde el `venta.json` y pruébelo, como se indica en el enunciado, en la parte de levantar el ambiente local. La venta debe responder HTTP 201.

### Herramientas para inyectar fallos

En este laboratorio el experimento no es una prueba de carga: el tráfico es bajo y constante, y lo que se manipula es el **fallo**. Para eso el código base trae un endpoint de caos en Inventario, que enciende y apaga un fallo en segundos sin redesplegar. El fallo afecta solo la consulta de disponibilidad que hace Ventas (`GET /inventory/items/disponibilidad/:productoId`):

```bash
# Latencia de 5 s durante 150 s (se retira sola al cumplirse durationMs)
curl -s -X POST $INV/chaos -H 'Content-Type: application/json' \
  -d '{"mode": "latency", "delayMs": 5000, "durationMs": 150000}'

# Retirar el fallo de inmediato
curl -s -X POST $INV/chaos -H 'Content-Type: application/json' -d '{"mode": "off"}'

# Estado actual y contador de llamadas de disponibilidad
curl -s $INV/chaos
```

El código está en `apps/inventario/src/chaos.controller.ts` y `fault.middleware.ts`. No es necesario modificarlo.

### Ajuste de código: graceful degradation en Ventas

El sidecar maneja la capa de red. La decisión de negocio —qué responder al cliente cuando Inventario está caído— debe estar en el código de Ventas.

Cuando el circuito está OPEN, el sidecar devuelve HTTP 503 a Ventas. El cliente HTTP (`InventarioDisponibilidadClient`) convierte ese 503 en una excepción `ServiceUnavailableException`. Sin manejo explícito, esa excepción se propaga y Ventas retorna 503 al tendero.

Este cambio ya está aplicado en la rama `availability` (en `libs/ventas/src/services/venta.service.ts`): revise el archivo para entender la implementación completa antes de continuar.

## Parte 2 — Primer experimento de caos: estado estable y tormenta de reintentos sin protecciones

En esta parte hace, en local, los dos primeros pasos del laboratorio: la medición del estado estable y la tormenta de reintentos con la configuración **sin sidecar** (el grupo de control, en el que Ventas llama directamente a Inventario, sin reintentos ni circuit breaker), para ver la tormenta sin protecciones.

### Antes de empezar: las fichas

Escriba las fichas de los dos experimentos (el formato está en el enunciado, en el diseño del experimento) **antes** de inyectar nada: estado estable que espera, hipótesis, radio de impacto esperado y condición de aborto. Deje para después el campo de predicción para AWS. Discútalas con su grupo: ¿qué cree que le pasará a una venta cuando Inventario tarde 5 s, si Ventas lo espera hasta 9 s y la app del tendero la abandona a los 3 s?

### Preparar los datos y el generador de tráfico

Reponga stock, porque el generador de tráfico vende 2 unidades por segundo y la tormenta muchas más:

```bash
curl -s -X PATCH $INV/items/$ITEM -H 'Content-Type: application/json' -d '{"cantidad": 100000}'
```

El **generador de tráfico** (`lab_5/recursos/generador_trafico.sh`) envía 2 ventas por segundo y, cada 5 s, consulta otros tres endpoints para medir el radio de impacto. Escribe un CSV con la hora, el endpoint, el código HTTP, la latencia y si la venta quedó `pending`. No es una prueba de carga: la carga es la misma en todos los experimentos.

### Experimento de estado estable

Con la configuración completa (la que levanta `docker compose up`), corra el generador de tráfico 5 minutos sin inyectar nada y resúmalo por ventanas de 10 s:

```bash
./lab_5/recursos/generador_trafico.sh estado_estable_local.csv      # Ctrl+C a los 5 minutos
python3 lab_5/recursos/ventanas.py estado_estable_local.csv
```

Anote la disponibilidad percibida (2xx en menos de 3 s), el p99 y el % de `pending` de las ventas: ese es el estado estable contra el que comparará todo lo demás.

### Experimento de tormenta de reintentos, sin sidecar

1. Recree Ventas sin sidecar, apuntando directamente a Inventario, y verifíquelo:
   ```bash
   VENTAS_INVENTARIO_BASE_URL=http://inventario:3002 docker compose up -d ventas
   docker compose exec ventas printenv INVENTARIO_BASE_URL     # debe mostrar http://inventario:3002
   ```
2. Arranque el generador de tráfico en una terminal (`./lab_5/recursos/generador_trafico.sh tormenta_local_sin_sidecar.csv`). Anote el total de filas del Outbox (`curl -s $VEN/outbox/resumen`) y el contador `llamadasDisponibilidad` (`curl -s $INV/chaos`).
3. A los 2 minutos, anote la hora, inyecte la latencia y lance la tormenta en otra terminal (pegue también ahí el bloque de variables):
   ```bash
   curl -s -X POST $INV/chaos -H 'Content-Type: application/json' \
     -d '{"mode": "latency", "delayMs": 5000, "durationMs": 150000}'
   CLIENTES=50 DURACION=120 ./lab_5/recursos/tormenta_reintentos.sh tormenta_local_sin_sidecar_apps.csv
   ```
4. La tormenta termina a los 120 s e imprime su resumen; anote el contador en ese momento. El fallo se retira solo a los 150 s (la hora está en el campo `until`). Observe 3 minutos más, vuelva a leer el total de filas del Outbox y detenga el generador de tráfico.
5. Resuma con `python3 lab_5/recursos/ventanas.py tormenta_local_sin_sidecar.csv`.
6. Vuelva a la configuración completa: `docker compose up -d ventas`.

### Qué observar

- Latencia de Ventas: ¿cómo se propaga a las ventas del generador de tráfico el retraso de 5 s de Inventario? ¿Cambia la disponibilidad percibida aunque las respuestas sigan siendo 201?
- La tormenta: ¿cuántos intentos por pedido necesitaron las apps defectuosas, y cuántos pedidos completaron?
- Consultas a Inventario por pedido (la fórmula está en las métricas del enunciado) y pedidos duplicados: ¿cuántas ventas se registraron frente a los pedidos que realmente se hicieron?
- Radio de impacto: ¿qué otros endpoints del generador de tráfico se afectaron?
- **Recuperación**: ¿cuánto tardó Ventas en volver al estado estable después de que el fallo se retiró?

> Anote estos valores: son el grupo de control contra el que comparará las tácticas en el resto del laboratorio.

## Cierre de la sesión

Al terminar, cada estudiante debe tener: el ambiente local arriba, los 6 parámetros del sidecar calibrados y verificados (`/ready` en `LIVE`), las fichas del estado estable y de la tormenta de reintentos, y los resultados del estado estable y de la tormenta sin sidecar en local (CSV del generador de tráfico y de la tormenta, tabla por ventanas, contador de llamadas y filas del Outbox). Esto es exactamente lo que pide la fase local para esos dos experimentos: no hay que rehacerlo después. Se sigue con las demás configuraciones locales de la tormenta de reintentos (solo reintentos y completa) y con el experimento de caída de Inventario; la fase AWS viene cuando la fase local esté completa.
