# Lab 5 — Resiliencia en Microservicios: Circuit Breaker, Retry y Rate Limiting

## Objetivos

- Reproducir experimentalmente un fallo en cascada (cascading failure) provocado por un retry storm, tal como ocurre en sistemas en producción reales.
- Implementar tres tácticas de resiliencia a nivel de aplicación: retry con backoff exponencial, circuit breaker con graceful degradation, y rate limiting.
- Desplegar la infraestructura del laboratorio usando Infraestructura como Código (IaaC) con AWS CloudFormation.
- Evaluar el impacto de cada táctica sobre los ASRs del negocio de Chiper mediante pruebas de carga.
- Reflexionar sobre las limitaciones de las tácticas locales frente a enfoques de resiliencia distribuida centralizada.

## Índice

- [1. Experimento](#1-experimento)
- [2. Arquitectura](#2-arquitectura)
- [3. Tecnologías](#3-tecnologías)
- [4. Preparación: IaaC con CloudFormation](#4-preparación-iaac-con-cloudformation)
- [5. Modificaciones al código](#5-modificaciones-al-código)
- [6. Parte 1 — Reproducir el fallo en cascada](#6-parte-1--reproducir-el-fallo-en-cascada)
- [7. Parte 2 — Aplicar tácticas de resiliencia](#7-parte-2--aplicar-tácticas-de-resiliencia)
- [8. Interpretación de resultados](#8-interpretación-de-resultados)
- [9. Entregables](#9-entregables)

## 1. Experimento

### 1.1 Descripción

| Elemento             | Detalle                                                                                                                                                                 |
| -------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Título               | Resiliencia bajo fallo del servicio de Inventario en la arquitectura de microservicios de Chiper                                                                        |
| Propósito            | Reproducir un cascading failure provocado por un retry storm y mitigarlo con circuit breaker, retry con backoff y rate limiting                                         |
| Resultados esperados | Con las tácticas aplicadas, el servicio de Ventas mantiene disponibilidad y responde con graceful degradation en lugar de errores 500, incluso con Inventario degradado |
| Infraestructura      | CloudFormation + API Gateway + ECS/Fargate + ECR + RDS + computador personal para JMeter                                                                                |

### 1.2 Contexto de negocio

Los lunes por la mañana, los tenderos de Chiper realizan sus reabastecimientos semanales. En estos picos, el servicio de **Inventario**, que valida disponibilidad de stock antes de confirmar un pedido, recibe una carga muy superior a la normal. Sin protecciones, el servicio de **Ventas** (que depende de Inventario) empieza a fallar en cadena: los tenderos no pueden confirmar pedidos, las apps móviles reintentán automáticamente, y ese volumen de reintentos amplifica la carga sobre un servicio ya degradado. El resultado: un sistema que se colapsa a sí mismo.

Este escenario es conocido en la industria como **retry storm** y es uno de los patrones de fallo descritos en el artículo [Failure Mitigation for Microservices: An Intro to Aperture](https://careersatdoordash.com/blog/failure-mitigation-for-microservices-an-intro-to-aperture/) de DoorDash.

Un aspecto crítico de este escenario, y que este lab reproduce explícitamente, es que el fallo es **transitorio**: los sistemas de orquestación modernos como ECS detectan tareas poco saludables mediante health checks y las reinician automáticamente. En la práctica, un servicio degradado por un pico de memoria, un pool de conexiones agotado o un spike de CPU puede recuperarse por sí solo en cuestión de segundos o minutos. El servicio de Inventario en este laboratorio simula exactamente eso: se degrada al arrancar y se recupera automáticamente tras `RECOVERY_TIME_MS` milisegundos. Esto hace que el estado **HALF-OPEN** del circuit breaker no sea solo teórico: cuando Inventario se recupera, el circuit breaker lo detecta y vuelve al estado CLOSED, restaurando el flujo normal sin intervención humana.

### 1.3 ASRs involucrados

| ID    | Descripción                                                                                                                                                                                           | Medidas de respuesta a satisfacer                                                                                                                            |
| ----- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| ASR-1 | Como tendero, quiero poder confirmar un pedido incluso cuando el servicio de Inventario esté degradado. Un pedido con stock no confirmado es preferible a un error que me impida completar la compra. | Durante fallo total de Inventario, Ventas responde HTTP 200 con `status: pending_stock_confirmation` en p99 < 3000 ms                           |
| ASR-2 | Como negocio, quiero que los reintentos automáticos ante fallos no amplifiquen la carga sobre servicios ya degradados, para evitar empeorar el incidente.                                             | El volumen de requests recibidos por Inventario con reintentos activos no debe superar 2x el volumen de la línea base sin reintentos            |
| ASR-3 | Como negocio, quiero que el tráfico de confirmación de pedidos no se vea afectado por picos de tráfico de baja prioridad (ej. consultas de catálogo masivas).                                         | El rate limiter rechaza el tráfico excedente con HTTP 429 sin que el throughput de pedidos válidos caiga más de un 10% respecto a la línea base |

### 1.4 Qué se va a probar

Se realizan cuatro rondas de pruebas de carga con JMeter sobre `POST /ventas` con Inventario en estado de fallo controlado:

1. **Baseline (sin protecciones)**: sin timeout, sin retry, sin circuit breaker.
2. **Con retry + backoff exponencial**: axios-retry, máx 2 reintentos, jitter.
3. **Con circuit breaker + graceful degradation**: opossum, fallback a `pending_stock_confirmation`.
4. **Con las tres tácticas combinadas** (retry + circuit breaker + rate limiting en API Gateway).

## 2. Arquitectura

### 2.1 Estilos de arquitectura asociados

| Estilo | Análisis |
| --- | --- |
| Microservicios | Favorece aislamiento de fallos por servicio y despliegue independiente.<br>Sin tácticas de resiliencia, la comunicación HTTP entre servicios introduce puntos de fallo en cadena. |
| API Gateway | Actúa como punto de control centralizado para rate limiting y throttling.<br>Protege los servicios upstream de picos de tráfico que superan su capacidad. |
| Fallar con gracia (Graceful Degradation) | Favorece continuidad operativa durante incidentes: el sistema entrega respuestas útiles aunque parciales en lugar de fallar completamente.<br>Requiere acuerdos de negocio claros sobre qué funcionalidades pueden degradarse sin romper la experiencia crítica del tendero. |
| Control de recursos (Resource Control) | Favorece estabilidad bajo carga al limitar concurrencia, throughput y consumo por cliente/ruta (throttling, cuotas, aislamiento).<br>Sin una buena calibración, puede rechazar tráfico legítimo y afectar temporalmente la percepción de disponibilidad. |

### 2.2 Tácticas

| Táctica                                     | Análisis                                                                                                                                                                                                                                                         |
| ------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Reintentos con backoff exponencial + jitter | Favorece la recuperación automática ante fallos transitorios.<br>Sin backoff ni jitter, los reintentos sincronizados pueden amplificar la carga (thundering herd), agravando el incidente en lugar de resolverlo.                                                |
| Circuit Breaker (CLOSED / OPEN / HALF-OPEN) | Favorece disponibilidad del servicio cliente al dejar de enviar requests a un servicio que ya está fallando.<br>Desfavorece consistencia inmediata: el estado OPEN implica que algunas operaciones retornan respuestas degradadas en lugar de resultados reales. |
| Graceful Degradation (fallback)             | Favorece experiencia de usuario y disponibilidad percibida: el sistema sigue aceptando pedidos en modo degradado.<br>Introduce complejidad en la lógica de negocio para manejar el estado `pending_stock_confirmation`.                                          |
| Rate Limiting (API Gateway throttling)      | Favorece protección de servicios backend ante picos de tráfico y retry storms.<br>Puede afectar a usuarios legítimos si los límites no están bien calibrados para los patrones reales de la demanda.                                                             |

### Nueva dependencia: Ventas → Inventario

En este laboratorio se introduce explícitamente una dependencia HTTP entre servicios: **Ventas llama a Inventario** para verificar disponibilidad de stock antes de registrar una venta. Esta dependencia es el punto de fallo que se va a explorar.

```
Tendero → API Gateway → Ventas (ECS) → Inventario (ECS) → RDS
```

Si Inventario se degrada, sin protecciones Ventas también falla. Con las tácticas implementadas, Ventas es capaz de continuar operando de forma degradada.

## 3. Tecnologías

| Categoría                          | Tecnologías                               |
| ---------------------------------- | ----------------------------------------- |
| Infraestructura como Código        | AWS CloudFormation                        |
| Gateway de entrada + Rate Limiting | Amazon API Gateway (throttling por stage) |
| Orquestación de contenedores       | Amazon ECS (Fargate)                      |
| Registro de imágenes               | Amazon ECR                                |
| Base de datos relacional           | Amazon RDS (PostgreSQL)                   |
| Framework backend                  | NestJS                                    |
| Lenguaje                           | TypeScript                                |
| ORM                                | TypeORM                                   |
| Cliente HTTP con retry             | axios + axios-retry                       |
| Circuit Breaker                    | opossum                                   |
| Pruebas de carga                   | Apache JMeter                             |

## 4. Preparación: IaaC con CloudFormation

### 4.1 ¿Qué es Infraestructura como Código?

En los labs anteriores, la infraestructura se creó paso a paso desde la consola de AWS: security groups, instancias EC2, RDS, ECS, API Gateway. Este enfoque manual tiene un problema: es propenso a errores, difícil de reproducir y no deja registro de qué se configuró exactamente.

**Infraestructura como Código (IaaC)** resuelve esto declarando la infraestructura en un archivo de texto (código), que puede versionarse, revisarse y ejecutarse de forma reproducible. **AWS CloudFormation** es el servicio nativo de AWS para esto: usted define un *template* YAML o JSON que describe los recursos, y CloudFormation se encarga de crearlos, actualizarlos o eliminarlos.

### 4.2 Template CloudFormation del laboratorio

Se provee el archivo `lab_5/recursos/cloudformation_template.yaml` con toda la infraestructura del laboratorio declarada. Lea el template antes de ejecutarlo: cada sección tiene comentarios que explican qué recurso crea y por qué.

El template incluye:

| Sección            | Recursos creados                                                              |
| ------------------ | ----------------------------------------------------------------------------- |
| `Parameters`       | ARNs de imágenes ECR, credenciales RDS, VPC/subnets                           |
| `VPC y Networking` | VPC, subnets públicas/privadas, Internet Gateway, Security Groups             |
| `RDS`              | Instancia PostgreSQL, subnet group, security group de base de datos           |
| `ECS Cluster`      | Cluster Fargate compartido, roles IAM de ejecución                            |
| `Task Definitions` | Una por servicio (Logistica, Inventario, Ventas) con variables de entorno     |
| `ECS Services`     | Un servicio ECS por Task Definition, conectado a su ALB                       |
| `Load Balancers`   | ALB por servicio con Target Groups y Health Checks                            |
| `API Gateway`      | HTTP API con rutas `/logistica/*`, `/inventario/*`, `/ventas/*` y stage `lab` |

### 4.3 Preparar parámetros

Antes de desplegar, publique las imágenes Docker en ECR (igual que en el Lab 4) y anote los URIs. Los necesitará como parámetros del template.

| Servicio   | Nombre sugerido repositorio | Tag imagen |
| ---------- | --------------------------- | ---------- |
| Logística  | `chiper-logistica`          | `2.0.0`    |
| Inventario | `chiper-inventario`         | `2.0.0`    |
| Ventas     | `chiper-ventas`             | `2.0.0`    |

Tutorial de apoyo:
- [Subir imágenes Docker a Amazon ECR](../tutoriales/subir_imagenes%20_a_ecr.md)

> Use el tag `2.0.0` para distinguir las imágenes con las modificaciones de este lab de las del Lab 4. La rama inicial para este laboratorio se llama *graceful-degradation*

### 4.4 Desplegar el stack

```bash
aws cloudformation deploy --template-file lab_5/recursos/cloudformation_template.yaml --stack-name chiper-lab5 --parameter-overrides LogisticaImageUri=<URI_ECR_LOGISTICA>:2.0.0 InventarioImageUri=<URI_ECR_INVENTARIO>:2.0.0 VentasImageUri=<URI_ECR_VENTAS>:2.0.0 DBPassword=<SU_CONTRASEÑA> --capabilities CAPABILITY_NAMED_IAM --region us-east-1
```

Monitoree el progreso en la consola de AWS → CloudFormation → Stack `chiper-lab5` → pestaña **Events**.

### 4.5 Verificar el despliegue

Una vez el stack esté en estado `CREATE_COMPLETE`:

```bash
# Obtener la URL del API Gateway
aws cloudformation describe-stack --stack-name chiper-lab5 --query "Stacks[0].Outputs[?OutputKey=='ApiGatewayUrl'].OutputValue" --output text
```

Desde su computador verifique que los tres servicios responden:

```
GET https://<API_ID>.execute-api.<REGION>.amazonaws.com/lab/logistica/health
GET https://<API_ID>.execute-api.<REGION>.amazonaws.com/lab/inventario/health
GET https://<API_ID>.execute-api.<REGION>.amazonaws.com/lab/ventas/health
```

Los tres deben retornar HTTP 200 antes de continuar.

## 5. Modificaciones al código

Las siguientes modificaciones son necesarias antes de publicar las imágenes `2.0.0`. Aplíquelas en el monorepo de microservicios.

### 5.1 Lógica de inyección de fallos con auto-recuperación en Inventario

El servicio de Inventario incorpora un mecanismo de fallo transitorio controlado por dos variables de entorno:

- `FAULT_DELAY_MS`: delay artificial en ms que se agrega a cada respuesta durante el período de fallo.
- `RECOVERY_TIME_MS`: tiempo en ms desde el arranque del proceso hasta que el servicio se recupera automáticamente. Pasado este tiempo, el delay desaparece y el servicio responde con normalidad.

**`apps/inventario/src/fault.middleware.ts`** — módulo de inyección de fallos:

```typescript
// Tiempo de inicio del proceso. Si FAULT_DELAY_MS está configurado,
// el servicio arranca en modo degradado y se recupera tras RECOVERY_TIME_MS.
const FAULT_START = Date.now();
const FAULT_DELAY_MS = parseInt(process.env.FAULT_DELAY_MS ?? '0', 10);
const RECOVERY_TIME_MS = parseInt(process.env.RECOVERY_TIME_MS ?? '0', 10);

export function isFaulting(): boolean {
  if (FAULT_DELAY_MS <= 0) return false;
  if (RECOVERY_TIME_MS <= 0) return true; // fallo permanente si no hay recovery
  return Date.now() - FAULT_START < RECOVERY_TIME_MS;
}

export async function applyFaultDelay(): Promise<void> {
  if (isFaulting()) {
    await new Promise(resolve => setTimeout(resolve, FAULT_DELAY_MS));
  }
}
```

Llame a `applyFaultDelay()` al inicio del endpoint de verificación de disponibilidad (el que Ventas consume), de forma que el delay afecte exactamente el flujo que el circuit breaker monitorea.

### 5.2 Dependencia HTTP de Ventas hacia Inventario

Agregue la llamada HTTP de Ventas a Inventario en el flujo de creación de ventas. Primero, instale las dependencias:

```bash
cd apps/ventas
npm install axios axios-retry opossum
npm install --save-dev @types/opossum
```

**`apps/ventas/src/ventas.service.ts`** — agregue la verificación de stock antes de registrar la venta:

```typescript
import axios from 'axios';
import axiosRetry from 'axios-retry';
import CircuitBreaker from 'opossum';

// --- Configuración de Retry (Táctica 1) ---
const inventarioClient = axios.create({
  baseURL: process.env.INVENTARIO_BASE_URL,
  timeout: 2000,
});

axiosRetry(inventarioClient, {
  retries: 2,
  retryDelay: (retryCount) => {
    const base = 100 * Math.pow(2, retryCount - 1);       // 100ms, 200ms
    const jitter = Math.floor(Math.random() * base * 0.2); // ±20% jitter
    return base + jitter;
  },
  retryCondition: (error) =>
    axiosRetry.isNetworkOrIdempotentRequestError(error) ||
    (error.response?.status ?? 0) >= 500,
});

// --- Configuración de Circuit Breaker (Táctica 2) ---
async function checkInventario(productoId: string): Promise<boolean> {
  const response = await inventarioClient.get(
    `/inventario/disponibilidad/${productoId}`,
  );
  return response.data.disponible as boolean;
}

const circuitBreaker = new CircuitBreaker(checkInventario, {
  timeout: 2000,           // fallo si tarda más de 2s
  errorThresholdPercentage: 50, // abre con 50% de fallos
  resetTimeout: 15000,     // intenta HALF-OPEN cada 15s
  volumeThreshold: 5,      // mínimo 5 llamadas antes de evaluar
});

circuitBreaker.fallback(() => {
  // Graceful degradation: en lugar de lanzar error, retorna false
  return false;
});

// --- En el método create de VentasService ---
async create(dto: CreateVentaDto) {
  const disponible = await circuitBreaker.fire(dto.productoId);

  if (!disponible) {
    // Degraded response: la venta queda pendiente de confirmación de stock
    return {
      ...dto,
      status: 'pending_stock_confirmation',
      message: 'Pedido registrado. La disponibilidad de stock será confirmada próximamente.',
    };
  }

  // Flujo normal de creación de venta
  return this.ventasRepository.save(dto);
}
```

> El estado del circuit breaker (CLOSED, OPEN, HALF-OPEN) es visible en los logs del contenedor ECS. Puede observarlo en CloudWatch Logs durante las pruebas.

### 5.3 Variables de entorno adicionales

Actualice las Task Definitions (o el template CloudFormation) con las nuevas variables:

| Servicio   | Variable nueva        | Ejemplo                                                   |
| ---------- | --------------------- | --------------------------------------------------------- |
| Inventario | `FAULT_DELAY_MS`      | `0` (sin fallo) / `5000` (degradado: 5s de delay)         |
| Inventario | `RECOVERY_TIME_MS`    | `60000` (el servicio se recupera 60s después de arrancar) |
| Ventas     | `INVENTARIO_BASE_URL` | `http://<ALB_INVENTARIO>`                                 |

Para las pruebas de este lab, use `FAULT_DELAY_MS=5000` y `RECOVERY_TIME_MS=600000`. Esto significa que Inventario arranca degradado durante 10 minutos y luego se recupera automáticamente. Configure `resetTimeout` del circuit breaker en un valor inferior a `RECOVERY_TIME_MS` para que el estado HALF-OPEN pueda detectar la recuperación.

## 6. Parte 1 — Reproducir el fallo en cascada

### 6.1 Configurar el fallo

1. En la consola de AWS → ECS → Task Definition `td-chiper-inventario`, cree una nueva revisión con:
   - `FAULT_DELAY_MS=5000`
   - `RECOVERY_TIME_MS=60000`
2. Actualice el servicio ECS de Inventario para que use la nueva revisión y espere que las tareas sean reemplazadas.
3. Asegúrese de que **Ventas esté en versión sin protecciones** (sin retry ni circuit breaker, solo el código naïve con una llamada HTTP directa sin timeout explícito).

> Con esta configuración, Inventario arrancará degradado y responderá con 5s de delay. Pasados 10 minutos desde el arranque, se recuperará automáticamente. Anote el momento exacto de arranque de la tarea (visible en ECS → Tasks → Started at) para correlacionarlo con las métricas de JMeter.

### 6.2 Pruebas de carga

Ejecute JMeter con carga sobre `POST /ventas`. El endpoint de Ventas hace una llamada interna a Inventario, que ahora responde con 5 segundos de delay.

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
- Requests totales a Inventario: ¿aumentan con el tiempo sin retry?
- **Recuperación espontánea**: ¿qué sucede con la latencia de Ventas a los 60s del arranque de Inventario? ¿El sistema se recupera solo? ¿Cuánto tarda Ventas en notar que Inventario ya está bien?
- Punto de colapso: ¿a partir de cuántos threads el sistema deja de responder?

> Anote estos valores como Base. Son el punto de comparación para las tácticas. La recuperación espontánea en el baseline es el caso de control: sin circuit breaker, el sistema se recupera cuando Inventario se recupera, pero el tiempo de recuperación percibido por Ventas puede ser mayor de lo esperado.

## 7. Parte 2 — Aplicar tácticas de resiliencia

Aplique y pruebe cada táctica de forma incremental, usando la misma matriz de carga de la Parte 1 para comparabilidad.

### 7.1 Táctica 1 — Retry con backoff exponencial + jitter

Active el código de `axios-retry` en Ventas (según la sección 5.2). Publique una nueva imagen `2.1.0` y actualice el servicio ECS.

**Comportamiento esperado**: ante un fallo de Inventario, Ventas reintenta máximo 2 veces con esperas de ~100ms y ~200ms antes de fallar definitivamente.

**Qué medir**:
- ¿El p99 de Ventas mejora respecto al baseline?
- ¿El volumen de requests a Inventario aumenta? ¿En qué factor? (verificar ASR-2)
- ¿El error % de Ventas mejora? Si Inventario falla consistentemente, el retry no resolverá el error, solo lo retrasará.

> **Observación clave**: el retry solo ayuda con fallos transitorios. Para fallos persistentes (como el delay de 5s que simulamos), el retry amplifica la carga sin mejorar la disponibilidad. Este es el problema que el circuit breaker resuelve.

### 7.2 Táctica 2 — Circuit Breaker con graceful degradation

Active el `CircuitBreaker` de opossum con el fallback definido en la sección 5.2. Publique la imagen `2.2.0` y actualice el servicio ECS.

**Comportamiento esperado**:
- Primeras llamadas: el circuit breaker está en estado **CLOSED**, las llamadas llegan a Inventario y fallan (Inventario está degradado).
- Tras 5 fallos en la ventana de evaluación: el circuit breaker pasa a **OPEN**.
- En estado OPEN: las llamadas ya no llegan a Inventario. Ventas ejecuta el fallback inmediatamente y retorna `status: pending_stock_confirmation` con HTTP 200.
- Tras 15s (resetTimeout): el circuit breaker intenta **HALF-OPEN** y envía una sola llamada de prueba a Inventario.
  - Si Inventario todavía está degradado (antes de los 60s): la prueba falla → vuelve a OPEN.
  - **Si Inventario ya se recuperó** (después de los 60s): la prueba tiene éxito → el circuit breaker vuelve a **CLOSED** y el flujo normal se restaura automáticamente.

Esta es la demostración clave del laboratorio: el circuit breaker no solo protege durante el fallo, sino que **detecta la recuperación** del servicio sin intervención humana. En producción, este mecanismo permite que el sistema se auto-sane tras un reinicio de contenedor en ECS.

**Qué medir**:
- ¿El p99 de Ventas cae significativamente una vez el circuit breaker está OPEN? (verificar ASR-1)
- ¿El error % de Ventas llega a 0% una vez que el circuito está abierto?
- ¿Cuántos requests llegan a Inventario en estado OPEN vs. estado CLOSED?
- **¿En qué momento exacto el circuit breaker detecta la recuperación de Inventario y pasa a CLOSED?** Compare con el momento de recuperación automática de Inventario (los 60s del arranque).
- Observe los logs de CloudWatch para identificar todas las transiciones: CLOSED → OPEN → HALF-OPEN → CLOSED.

### 7.3 Táctica 3 — Rate Limiting en API Gateway

Configure throttling en el stage `lab` del API Gateway para limitar el tráfico entrante.

**Configuración sugerida**:

| Parámetro | Valor | Justificación |
| --- | --- | --- |
| Rate (req/s) | 100 | Límite sostenido para operación normal de Chiper |
| Burst | 200 | Permite absorber picos breves sin rechazar pedidos legítimos |

Pasos en la consola de AWS:

1. API Gateway → seleccione `chiper-ms-api`.
2. Stage `lab` → **Default route throttling**.
3. Configure `Rate` y `Burst` con los valores de la tabla.
4. Haga clic en **Save**.

**Prueba**: ejecute una carga que supere el rate limit (ej. 300 req/s). Observe que API Gateway devuelve HTTP 429 para las requests que superan el límite. Las requests dentro del límite deben seguir respondiendo normalmente.

**Qué medir**:
- ¿Qué porcentaje de las requests recibe HTTP 429?
- ¿El throughput de las requests que pasan el límite se mantiene estable?
- ¿Cómo cambia el comportamiento de Inventario al estar protegido por el rate limit?

### 7.4 Combinación de las tres tácticas

Con las tres tácticas activas simultáneamente, ejecute la misma matriz de carga. Esta es la configuración final del laboratorio.

Complete la tabla comparativa (ver entregables).

## 8. Interpretación de resultados

Analice los resultados con enfoque en disponibilidad:

- p99 y error % de Ventas en cada ronda (baseline, táctica 1, táctica 2, tácticas combinadas).
- Requests recibidos por Inventario en cada ronda (CloudWatch: ECS invocation count o ALB request count).
- Transiciones de estado del circuit breaker correlacionadas con la carga.
- Requests rechazadas por API Gateway (HTTP 429).

### 8.1 Umbrales por ASR

- **ASR-1**: Ventas responde HTTP 200 con `pending_stock_confirmation` en p99 < 3000 ms durante fallo de Inventario. Se verifica en la ronda con circuit breaker activo.
- **ASR-2**: Requests a Inventario con retry activo ≤ 2x los requests de la línea base. Se verifica comparando CloudWatch entre ronda baseline y ronda táctica 1.
- **ASR-3**: Con rate limiting activo, throughput de pedidos válidos cae < 10% respecto a la línea base dentro del límite. Se verifica en la ronda con rate limiting.

## 9. Entregables

### 9.1 Tabla comparativa de tácticas

Entregue una tabla con los resultados de las cuatro rondas:

| Ronda | p99 Ventas (ms) | Error % Ventas | Requests/s a Inventario | HTTP 429 % |
| --- | ---: | ---: | ---: | ---: |
| Baseline (sin protecciones) | | | | N/A |
| Retry + backoff | | | | N/A |
| Circuit Breaker + fallback | | | | N/A |
| Las tres tácticas combinadas | | | | |

Incluya también una tabla por escenario de carga (misma estructura que labs anteriores):

| # threads | Ramp-up (s) | p99 (ms) | p95 (ms) | Throughput (req/s) | Error % |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 50 | 10 | | | | |
| 200 | 20 | | | | |
| 500 | 50 | | | | |
| 1500 | 75 | | | | |

Presente una tabla por ronda de pruebas.

### 9.2 Evidencias

Adjunte capturas de:

- Stack CloudFormation en estado `CREATE_COMPLETE`.
- Servicios ECS de los tres microservicios en estado RUNNING.
- API Gateway con throttling configurado devolviendo HTTP 429.
- Logs de CloudWatch con las transiciones de estado del circuit breaker (CLOSED → OPEN → HALF-OPEN).
- Summary Report de JMeter para la ronda baseline y la ronda con tácticas combinadas.
- Iteración donde cada ASR deja de cumplirse (o donde empieza a cumplirse con las tácticas).

### 9.3 Evidencias y prompts

Adjunte
- Prompts utilizados (si usó IA).
- Scripts adicionales de carga (si aplica).

### 9.4 Análisis breve

Incluya un análisis de 1 a 2 páginas que responda:

1. ¿Por qué el retry sin backoff ni jitter puede empeorar una situación de fallo? Relacione la respuesta con el ASR-2 y con el escenario de Chiper (tenderos reintentando pedidos en el pico del lunes).
2. ¿Qué diferencia operativa tiene para un tendero recibir un error 500 frente a `status: pending_stock_confirmation`? ¿Bajo qué condiciones la degradación es aceptable para el negocio?
3. ¿En qué momento el circuit breaker debería pasar a estado HALF-OPEN? ¿Qué riesgos hay en abrir demasiado pronto frente a demasiado tarde?
4. ¿Cómo se complementan retry y circuit breaker? ¿Pueden conflictuarse? Describa un escenario concreto donde usarlos juntos sin coordinación podría generar un problema.
5. ¿Por qué el rate limiting en API Gateway protege mejor ante un retry storm que el rate limiting implementado dentro del propio servicio?
6. Lea el artículo [Failure Mitigation for Microservices: An Intro to Aperture](https://careersatdoordash.com/blog/failure-mitigation-for-microservices-an-intro-to-aperture/) de DoorDash. ¿Qué problema específico resuelve Aperture que las tácticas implementadas en este lab no resuelven? ¿En qué punto del crecimiento de Chiper tendría sentido adoptar un enfoque centralizado como ese?
7. ¿Qué ventajas concretas tuvo desplegar con CloudFormation frente a la configuración manual del Lab 4? ¿En qué escenarios del negocio de Chiper (ej. expansión a México o Brasil, un incidente que requiera reconstruir el ambiente) sería esta capacidad crítica?

## Nota final (créditos AWS)

Cuando termine el laboratorio, elimine todos los recursos para evitar consumo innecesario de créditos:

```bash
aws cloudformation delete-stack --stack-name chiper-lab5 --region us-east-1
```

Verifique en la consola que el stack pase a estado `DELETE_COMPLETE` y que no queden recursos huérfanos (especialmente instancias RDS e imágenes en ECR).
