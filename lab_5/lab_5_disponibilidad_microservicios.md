# Lab 5 — Disponibilidad en Microservicios: Circuit Breaker, Retry, Rate Limiting, Outbox e Idempotencia

## 1. Índice

- [1. Índice](#1-índice)
- [2. Etapas del laboratorio](#2-etapas-del-laboratorio)
- [3. Objetivos](#3-objetivos)
- [4. Planeación del laboratorio](#4-planeación-del-laboratorio)
- [5. Ejecución del laboratorio](#5-ejecución-del-laboratorio)
- [6. Realización de pruebas](#6-realización-de-pruebas)
- [7. Entregables](#7-entregables)
- [Nota final (créditos AWS)](#nota-final-créditos-aws)

## 2. Etapas del laboratorio

| Etapa                                      | Resumen                                                                                                          | Uso de IA generativa                                                                                      |
| ------------------------------------------ | ---------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| 1. Contexto del experimento de resiliencia | Modelado del escenario en el que los reintentos automáticos tumban un servicio que ya estaba degradado (*retry storm*), hipótesis de diseño, escenarios de calidad vinculados (ASRs), diseño y planeación del experimento. | Uso acotado para comprender patrones de falla; el criterio de negocio debe ser propio.                    |
| 2. Arquitectura y tacticas                 | Analisis de las tacticas de disponibilidad del laboratorio: un contenedor auxiliar que intercepta las llamadas entre servicios (sidecar), respuestas degradadas en lugar de errores (graceful degradation), corte de llamadas a un servicio caido (circuit breaker) y control de recursos. | Recomendado para comparar parametros y riesgos de configuracion.                                          |
| 3. Preparacion de infraestructura con IaC  | Despliegue reproducible en AWS a partir de un archivo que describe toda la infraestructura (infraestructura como codigo, con CloudFormation) y verificacion del despliegue. | Recomendado para asistir en comandos y troubleshooting de despliegue.                                     |
| 4. Configuración del sidecar de resiliencia | Implementacion de falla controlada en Inventario y configuración del sidecar (el proxy Envoy) en Ventas.                     | Recomendado para soporte de implementacion, revision de parametros y pruebas; validar manualmente resultados. |
| 5. Ejecucion de experimentos y analisis    | Comparacion de la linea base sin protecciones contra cada tactica, y evaluacion de su impacto en los ASRs.                          | No recomendado para redactar conclusiones sin evidencia empirica del laboratorio.                         |
| 6. Consistencia bajo fallo: Outbox e Idempotencia | Demostración del problema de inconsistencia de datos y su solución con dos patrones: Outbox (entrega garantizada de una operación pendiente) e idempotencia (una operación repetida no se aplica dos veces).   | Recomendado para soporte de implementacion; validar manualmente el experimento.                           |

## 3. Objetivos

- Reproducir experimentalmente un **fallo en cascada** (un servicio que falla arrastra a los que dependen de él) provocado por un *retry storm* (una avalancha de reintentos automáticos), tal como ocurre en sistemas en producción reales.
- Implementar tres tácticas de resiliencia a nivel de infraestructura: reintentos con espera creciente entre intentos (*retry* con *backoff* exponencial), corte de llamadas a un servicio caído con respuesta degradada (*circuit breaker* con *graceful degradation*) y límite de peticiones por segundo (*rate limiting*).
- Desplegar la infraestructura del laboratorio usando Infraestructura como Código (describir la infraestructura en un archivo, en lugar de crearla a mano) con AWS CloudFormation.
- Evaluar el impacto de cada táctica sobre los ASRs del negocio de Cheapest mediante pruebas de carga.
- Demostrar que la resiliencia de infraestructura (circuit breaker, retry) no garantiza consistencia de datos, e implementar los patrones **Outbox** e **Idempotencia** para cerrar esa brecha.
- Reflexionar sobre las limitaciones de las tácticas locales frente a enfoques de resiliencia distribuida centralizada.

## 4. Planeación del laboratorio

En el Lab 4 usted desplegó Cheapest como tres microservicios (Logística, Inventario y Ventas) y midió su escalabilidad. Hasta ahora todos los servicios funcionaban; el único problema era la carga. En este laboratorio se estudia qué pasa cuando **uno de los servicios falla** y los demás dependen de él.

Para eso se introduce explícitamente una dependencia HTTP entre servicios: **Ventas llama a Inventario** para verificar que hay stock antes de registrar una venta. Esta dependencia es el punto de fallo que se va a explorar: **si Inventario se degrada, sin protecciones Ventas también falla.**

**Contexto de negocio.**

Los lunes por la mañana, los tenderos de Cheapest realizan sus reabastecimientos semanales. En estos picos, el servicio de **Inventario**, que valida disponibilidad de stock antes de confirmar un pedido, recibe una carga muy superior a la normal. Sin protecciones, el servicio de **Ventas** (que depende de Inventario) empieza a fallar en cadena: los tenderos no pueden confirmar pedidos, las apps móviles reintentán automáticamente, y ese volumen de reintentos amplifica la carga sobre un servicio ya degradado. El resultado: un sistema que se colapsa a sí mismo.

Este escenario es conocido en la industria como **retry storm** y es uno de los patrones de fallo descritos en el artículo [Failure Mitigation for Microservices: An Intro to Aperture](https://careersatdoordash.com/blog/failure-mitigation-for-microservices-an-intro-to-aperture/) de DoorDash.

> [!IMPORTANT]
> **Pregunta 1:**
> En Cheapest, ¿qué decisión de producto y operación debería tomarse primero cuando aparece un retry storm: proteger disponibilidad percibida (respuestas degradadas) o proteger consistencia estricta (rechazar operaciones)?
> Argumente su respuesta considerando impacto en tenderos, riesgo financiero y costo de reconciliación posterior.

Un aspecto crítico de este escenario, y que este lab reproduce explícitamente, es que el fallo es **transitorio**: los sistemas de orquestación modernos como ECS detectan tareas poco saludables mediante health checks y las reinician automáticamente. En la práctica, un servicio degradado por un pico de memoria, un pool de conexiones agotado o un spike de CPU puede recuperarse por sí solo en cuestión de segundos o minutos. El servicio de Inventario en este laboratorio simula exactamente eso: se degrada al arrancar y se recupera automáticamente tras `RECOVERY_TIME_MS` milisegundos. Esto hace que el estado **HALF-OPEN** del circuit breaker no sea solo teórico: cuando Inventario se recupera, el circuit breaker lo detecta y vuelve al estado CLOSED, restaurando el flujo normal sin intervención humana.

**Conceptos que se presentan en este laboratorio.** Cada uno se explica con más detalle, y con su aplicación en Cheapest, en la parte de tácticas y patrones.

| Concepto | Qué es |
| --- | --- |
| Fallo en cascada (*cascading failure*) | Un servicio que falla hace fallar a los servicios que dependen de él, y estos a los que dependen de ellos. |
| Timeout | Tiempo máximo que un servicio espera la respuesta de otro antes de darla por fallida. |
| Reintento (*retry*) | Volver a enviar automáticamente una petición que falló. |
| *Retry storm* | Avalancha de reintentos: muchos clientes reintentan al mismo tiempo contra un servicio que ya está degradado y terminan de tumbarlo. |
| *Backoff* exponencial | Esperar cada vez más entre un reintento y el siguiente (por ejemplo 0,1 s, 0,2 s, 0,4 s...). |
| *Jitter* | Variación aleatoria que se le suma a esa espera para que los clientes no reintenten todos en el mismo instante. |
| *Circuit breaker* | Mecanismo que, al detectar que un servicio falla repetidamente, deja de enviarle peticiones por un tiempo y responde de inmediato con un error. Tiene tres estados: CLOSED (el tráfico pasa), OPEN (el tráfico se corta) y HALF-OPEN (deja pasar una petición de prueba para ver si el servicio se recuperó). |
| *Graceful degradation* (fallar con gracia) | Cuando una dependencia no está disponible, responder algo útil aunque incompleto en lugar de un error. La respuesta alternativa se llama *fallback*. |
| *Rate limiting* (o *throttling*) | Limitar cuántas peticiones por segundo se aceptan. Las que exceden el límite se rechazan con el código HTTP 429 (*Too Many Requests*). |
| Proxy | Programa intermediario por el que pasan las peticiones entre dos servicios, y que puede aplicarles reglas (reintentar, cortar, registrar). |
| Sidecar | Contenedor auxiliar que se despliega junto al contenedor de un servicio, dentro de la misma tarea de ECS, y que se encarga de asuntos transversales (aquí, la resiliencia de las llamadas a Inventario) sin tocar el código del servicio. |
| Envoy | El proxy de código abierto que se usa como sidecar en este laboratorio. A su implementación del circuit breaker la llama *outlier detection*. |
| Infraestructura como Código (IaC) | Describir la infraestructura en un archivo de texto que se puede versionar y ejecutar, en lugar de crearla a mano en la consola. |
| CloudFormation | El servicio de AWS para infraestructura como código. El archivo que describe los recursos se llama **template** y el conjunto de recursos que crea a partir de él se llama **stack**. |
| Outbox | Patrón en el que una operación que hay que enviarle a otro servicio se guarda primero en una tabla local, en la misma transacción que el dato de negocio, y un proceso aparte la envía después hasta que logra entregarla. |
| Idempotencia | Propiedad de una operación que produce el mismo resultado aunque se ejecute varias veces. Se logra con una **clave de idempotencia**: un identificador que le permite al receptor reconocer una operación que ya procesó. |
| Línea base (*baseline*) | Medición del sistema sin ninguna protección, contra la que se compara cada táctica. |

### 4.1 Hipótesis de diseño

| # | Hipótesis |
| --- | --- |
| H1 | **Si** implementamos un circuit breaker con graceful degradation en el sidecar Envoy de Ventas, **entonces** `POST /ventas` responde HTTP 200 con `pending_stock_confirmation` en p99 < 3000 ms aun con Inventario en falla total, **porque** el circuito abierto corta las llamadas al servicio caído y Ventas responde con un fallback local en lugar de esperar timeouts y propagar el error. |
| H2 | **Si** configuramos retry con backoff exponencial + jitter en el sidecar (en lugar de reintentos inmediatos), **entonces** el volumen de requests que recibe Inventario no supera 2x la línea base, **porque** el backoff y el jitter dispersan los reintentos en el tiempo y evitan la amplificación sincronizada (retry storm). |
| H3 | **Si** aplicamos rate limiting (throttling) en API Gateway, **entonces** el tráfico excedente de baja prioridad se rechaza con HTTP 429 sin que el throughput de pedidos válidos caiga más de 10%, **porque** el límite se aplica en el borde, antes de que el tráfico consuma capacidad de los servicios. |
| H4 | **Si** registramos las ventas degradadas con el patrón Outbox y protegemos Inventario con una clave de idempotencia, **entonces** todo decremento de stock pendiente se entrega exactamente una vez tras la recuperación (PENDING → DELIVERED en < 30 s, sin duplicados), **porque** el Outbox garantiza entrega al menos una vez y la idempotencia descarta los reintentos repetidos. |

### 4.2 Escenarios de calidad vinculados

| ID    | Estímulo                                                                                     | Fuente del estímulo                                              | Entorno                                                                  | Artefacto                                                    | Respuesta                                                                                                  | Medida de respuesta                                                                                                                                    |
| ----- | ---------------------------------------------------------------------------------------------- | ------------------------------------------------------------------ | --------------------------------------------------------------------------- | --------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| ASR-1 | El servicio de Inventario deja de responder correctamente (falla total / timeouts sostenidos). | Servicio de Inventario, del cual depende Ventas.                   | Operación normal, pico de tráfico de reabastecimiento (lunes en la mañana). | Servicio de Ventas (endpoint `POST /ventas`).                   | Ventas registra el pedido en modo degradado en lugar de propagar el error al tendero.                          | Durante fallo total de Inventario, Ventas responde HTTP 200 con `status: pending_stock_confirmation` en p99 < 3000 ms.                                   |
| ASR-2 | Los clientes (o el sidecar) reintentan automáticamente las llamadas fallidas hacia Inventario. | Política de retry del sidecar Envoy ante errores 5xx de Inventario. | Inventario degradado, reintentos activos.                                   | Servicio de Inventario.                                          | Los reintentos no deben amplificar desproporcionadamente la carga recibida por Inventario.                      | El volumen de requests recibidos por Inventario con reintentos activos no debe superar 2x el volumen de la línea base sin reintentos.                    |
| ASR-3 | Un pico de tráfico de baja prioridad (ej. consultas de catálogo masivas) llega al sistema.     | Clientes externos generando tráfico de baja prioridad.               | Operación normal, con tráfico mixto de alta y baja prioridad.               | API Gateway / servicio de Ventas (confirmación de pedidos).     | El rate limiter rechaza el tráfico excedente sin afectar la confirmación de pedidos.                            | El rate limiter rechaza el tráfico excedente con HTTP 429 sin que el throughput de pedidos válidos caiga más de un 10% respecto a la línea base.         |
| ASR-4 | Inventario se recupera tras un período de caída durante el cual se registraron ventas en modo degradado. | Recuperación del servicio de Inventario.                             | Transición de modo degradado a modo normal.                                 | Mecanismo de Outbox (Ventas) + endpoint de idempotencia (Inventario). | Toda venta registrada en modo degradado entrega su decremento de stock exactamente una vez, sin duplicados.     | Tras la recuperación de Inventario, toda venta con OutboxHttpCall en estado PENDING transita a DELIVERED en < 30 s; ningún `item_inventario.cantidad` refleja decrementos duplicados. |

Contexto de negocio de cada ASR (motivación, no parte de la especificación formal):

- **ASR-1**: Como tendero, quiero poder confirmar un pedido incluso cuando el servicio de Inventario esté degradado. Un pedido con stock no confirmado es preferible a un error que me impida completar la compra.
- **ASR-2**: Como negocio, quiero que los reintentos automáticos ante fallos no amplifiquen la carga sobre servicios ya degradados, para evitar empeorar el incidente.
- **ASR-3**: Como negocio, quiero que el tráfico de confirmación de pedidos no se vea afectado por picos de tráfico de baja prioridad.
- **ASR-4**: Como negocio, quiero que toda venta registrada, incluso en modo degradado (`pending_stock_confirmation`), tenga su decremento de stock entregado exactamente una vez cuando Inventario se recupere.

### 4.3 Tácticas y patrones

#### 4.3.1 Patrones de diseño

##### Sidecar

Un **sidecar** es un contenedor auxiliar que se despliega junto al contenedor principal dentro de la misma unidad de ejecución (tarea ECS en este caso). Comparte el namespace de red con el servicio principal, lo que le permite interceptar el tráfico sin que la aplicación lo sepa.

![Diagrama de sidecar](./recursos/sidecar.png)

**¿Por qué sidecar en lugar de código?**

En este laboratorio las tácticas de disponibilidad se implementan en el sidecar y no dentro del servicio NestJS por tres razones:

1. **Separación de responsabilidades**: el código de negocio de Ventas no debería saber si el circuito está abierto o cerrado; eso es una política de infraestructura.
2. **Cambios sin redespliegue del servicio**: ajustar `num_retries` o `base_ejection_time` solo requiere actualizar la config del sidecar y reiniciarlo, sin tocar ni recompilar la aplicación.
3. **Consistencia cross-lenguaje**: si mañana Ventas se reescribe en Go o Python, el sidecar sigue funcionando igual, sin reimplementar la lógica de retry en cada SDK.

**Relación entre sidecar y graceful degradation**

El sidecar maneja la red (retry, circuit breaker). La graceful degradation —retornar `status: pending_stock_confirmation` en lugar de propagar el error— es una decisión de negocio que vive en el código de Ventas. El sidecar le comunica al servicio que Inventario está caído (mediante un 503 rápido en lugar de un timeout lento), y el servicio decide qué respuesta dar al cliente.

##### Circuit Breaker

Un **circuit breaker** es un control de fallos que corta el tráfico hacia un servicio cuando detecta errores persistentes. Evita que un servicio degradado reciba más carga y permite al cliente responder rápido con una salida controlada.

**Estados básicos**

- **CLOSED**: el circuito está cerrado y el tráfico fluye normalmente.
- **OPEN**: el circuito está abierto, el tráfico se corta inmediatamente y se devuelve un error o respuesta degradada.
- **HALF-OPEN**: tras un tiempo de espera, el circuito permite pasar algunos requests de prueba para verificar si el servicio se ha recuperado. Si esos requests tienen éxito, el circuito vuelve a CLOSED; si fallan, vuelve a OPEN.

![Diagrama de estados del circuit breaker](./recursos/circuit_breaker.png)

**Cómo se ve en Cheapest**

- Ventas llama a Inventario a traves del sidecar Envoy.
- Si Inventario empieza a fallar (timeouts o 5xx), Envoy cuenta los errores.
- Tras `consecutive_5xx`, abre el circuito (OPEN) y responde 503 inmediato.
- Ventas detecta el 503 y aplica graceful degradation.

**Por qué importa**

- Reduce el p99 de Ventas al evitar timeouts largos.
- Protege a Inventario de recibir mas trafico cuando ya esta degradado.
- Permite detectar la recuperacion automatica de Inventario (HALF-OPEN) sin intervencion humana.

**Riesgo si se calibra mal**

- Umbral demasiado bajo: el circuito abre con fallos transitorios y corta trafico legitimo.
- Umbral demasiado alto: tarda en abrir y el sistema sigue colapsando en cascada.

##### Outbox e idempotencia

El circuit breaker y la respuesta degradada mantienen a Ventas disponible, pero dejan un problema de datos: la venta quedó registrada y el stock de Inventario nunca se descontó. Dos patrones cierran esa brecha:

- **Outbox:** en la misma transacción en la que Ventas guarda la venta, guarda también una fila en una tabla local (`outbox_http_calls`) que representa "hay que descontar este stock en Inventario". Un proceso en segundo plano lee esa tabla cada 2 segundos y envía la petición a Inventario hasta que logra entregarla. La garantía es de entrega **al menos una vez** (*at-least-once*).
- **Idempotencia:** como "al menos una vez" significa que la misma petición puede llegar repetida, Inventario recibe con cada petición una clave de idempotencia y guarda las claves que ya procesó. Si llega una clave repetida, no vuelve a descontar.

Juntos logran que cada venta descuente el stock exactamente una vez. Verá ambos patrones en detalle, sobre el código, en la última ronda de pruebas.

#### 4.3.2 Tácticas de arquitectura

| Táctica                                     | Análisis                                                                                                                                                                                                                                                         |
| ------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Reintentos con backoff exponencial + jitter | Favorece la recuperación automática ante fallos transitorios.<br>Sin backoff ni jitter, los reintentos sincronizados pueden amplificar la carga (thundering herd), agravando el incidente en lugar de resolverlo.                                                |
| Circuit Breaker (CLOSED / OPEN / HALF-OPEN) | Favorece disponibilidad del servicio cliente al dejar de enviar requests a un servicio que ya está fallando.<br>Desfavorece consistencia inmediata: el estado OPEN implica que algunas operaciones retornan respuestas degradadas en lugar de resultados reales. |
| Graceful Degradation (fallback)             | Favorece experiencia de usuario y disponibilidad percibida: el sistema sigue aceptando pedidos en modo degradado.<br>Introduce complejidad en la lógica de negocio para manejar el estado `pending_stock_confirmation`.                                          |
| Rate Limiting (API Gateway throttling)      | Favorece protección de servicios backend ante picos de tráfico y retry storms.<br>Puede afectar a usuarios legítimos si los límites no están bien calibrados para los patrones reales de la demanda.                                                             |
| Proxy sidecar (Envoy)                   | Permite implementar retry y circuit breaker en la capa de red, sin tocar el código de negocio.<br>El sidecar intercepta el tráfico saliente de Ventas hacia Inventario y aplica las políticas configuradas en su archivo YAML.<br>Introduce un salto de red adicional y requiere que los parámetros del sidecar sean coherentes con los timeouts de la aplicación. |

##### Retries (reintentos)

Los **reintentos** permiten recuperar solicitudes ante fallos transitorios (timeouts cortos, reinicios, errores 5xx momentaneos). Para evitar sincronizacion masiva, se usan **backoff exponencial + jitter**.

**Flujo tipico**

```
intento 1 -> falla
espera base_interval (+/- jitter)
intento 2 -> falla
espera min(2x, max_interval)
intento 3 -> exito o error final
```

**Cómo se ve en Cheapest**

- Envoy reintenta automaticamente cuando Inventario responde 5xx.
- El timeout total de la ruta debe cubrir el tiempo de reintentos.
- El numero de reintentos debe respetar ASR-2: no puede duplicar en exceso el trafico hacia Inventario.

**Por qué importa**

- Mejora disponibilidad cuando el fallo es breve.
- Si el fallo es persistente, los retries solo amplifican carga y empeoran el incidente.

##### Graceful Degradation

La **graceful degradation** es una decision de negocio: el servicio devuelve una respuesta util aunque parcial cuando un componente critico no esta disponible. No evita la falla, pero protege la experiencia del usuario.

**Cómo se ve en Cheapest**

- Si Inventario no responde, Ventas registra el pedido con `status: pending_stock_confirmation`.
- El tendero recibe confirmacion de pedido, pero la verificacion de stock queda diferida.

**Por qué importa**

- Mantiene la disponibilidad percibida (ASR-1) aun con Inventario degradado.
- Requiere reglas claras: que significa "pendiente", cuanto tiempo puede estarlo, y como se reconcilia.

> [!IMPORTANT]
> **Pregunta 3 (parte A — propuesta de parámetros):**
> Retry, circuit breaker y rate limiting pueden entrar en conflicto si se calibran mal.
> Proponga un conjunto coherente de parámetros iniciales para Cheapest (timeouts, retries, umbral de apertura, reset timeout, rate y burst) y justifique cómo evitaría inestabilidad sistémica.

#### 4.3.3 Estilos aplicados

| Estilo | Análisis |
| --- | --- |
| Microservicios | Favorece aislamiento de fallos por servicio y despliegue independiente.<br>Sin tácticas de resiliencia, la comunicación HTTP entre servicios introduce puntos de fallo en cadena. |
| API Gateway | Actúa como punto de control centralizado para rate limiting y throttling.<br>Protege los servicios upstream de picos de tráfico que superan su capacidad. |
| Fallar con gracia (Graceful Degradation) | Favorece continuidad operativa durante incidentes: el sistema entrega respuestas útiles aunque parciales en lugar de fallar completamente.<br>Requiere acuerdos de negocio claros sobre qué funcionalidades pueden degradarse sin romper la experiencia crítica del tendero. |
| Control de recursos (Resource Control) | Favorece estabilidad bajo carga al limitar concurrencia, throughput y consumo por cliente/ruta (throttling, cuotas, aislamiento).<br>Sin una buena calibración, puede rechazar tráfico legítimo y afectar temporalmente la percepción de disponibilidad. |
| Sidecar | Externaliza responsabilidades transversales (resiliencia, observabilidad, seguridad) a un proceso proxy que corre junto al servicio principal.<br>Permite aplicar y cambiar políticas de resiliencia sin modificar el código de negocio ni redesplegar la aplicación. |

### 4.4 Diseño del experimento

#### 4.4.1 ¿Cómo se va a validar la hipótesis?

Comparando contra una línea base sin protecciones, bajo la misma matriz de carga y con el mismo fallo controlado en Inventario, y aplicando las tácticas de forma incremental para aislar el efecto de cada una.

Se realizan cinco rondas de pruebas de carga con JMeter sobre `POST /ventas`, con Inventario en estado de fallo controlado:

1. **Baseline (sin protecciones)**: el sidecar no está activo; Ventas llama directamente a Inventario sin timeout, retry ni circuit breaker.
2. **Con retry + backoff exponencial** (sidecar activado, solo política de retry): el proxy Envoy reintenta automáticamente ante errores 5xx.
3. **Con circuit breaker + graceful degradation** (sidecar con outlier detection): Envoy abre el circuito y Ventas retorna `pending_stock_confirmation`.
4. **Con las tres tácticas combinadas** (retry + circuit breaker en sidecar + rate limiting en API Gateway).
5. **Con Outbox + Idempotencia**: Inventario caído, se crean ventas que retornan `pending_stock_confirmation`. Se restaura Inventario y se observa la reconciliación automática vía Outbox. Se valida que reintentos con la misma clave no producen decrementos dobles.

> [!IMPORTANT]
> **Pregunta 2:**
> Si fuera el líder encargado de ejecutar este plan en Cheapest seguiría este orden teniendo en cuenta el riesgo de estos cambios? Describa un plan de migración que mitigue los riesgos asociados.
> El plan de migración debe incluir: etapas, tiempo estimado por etapa y las tareas a realizar en cada una.

#### 4.4.2 ¿Qué componentes se van a diseñar o modificar?

| Componente | Cambio |
| --- | --- |
| Inventario | Inyección de un fallo que se recupera solo después de un tiempo (`FAULT_DELAY_MS`, `RECOVERY_TIME_MS`) y endpoint que recibe los descuentos de stock con clave de idempotencia. |
| Ventas | Respuesta degradada (`pending_stock_confirmation`) cuando Inventario no está disponible, y escritura transaccional de la venta junto con su fila de Outbox. |
| Sidecar Envoy (en la tarea de Ventas) | Configuración del timeout, de los reintentos con backoff y jitter, y del circuit breaker. |
| API Gateway | Rate limiting sobre el stage `lab`. |

#### 4.4.3 ¿Qué métricas se van a medir?

| Métrica | Hipótesis / ASR | Umbral |
| --- | --- | --- |
| p99 de `POST /ventas` y % de respuestas 200 con `pending_stock_confirmation` | H1 / ASR-1 | p99 < 3000 ms |
| Requests recibidos por Inventario vs. línea base | H2 / ASR-2 | ≤ 2x |
| Throughput de pedidos válidos y % de respuestas 429 | H3 / ASR-3 | caída ≤ 10% |
| Tiempo de PENDING → DELIVERED y decrementos duplicados en `item_inventario.cantidad` | H4 / ASR-4 | < 30 s, 0 duplicados |

### 4.5 Planeación del experimento

#### 4.5.1 Recursos requeridos

| Recurso | Detalle |
| --- | --- |
| Infraestructura AWS | Stack de CloudFormation (API Gateway, ECS/Fargate, RDS, balanceadores y sidecar Envoy) desplegado en su cuenta, más los repositorios de ECR con las imágenes |
| Herramientas locales | Docker, AWS CLI, JMeter, un cliente de PostgreSQL y el backend de la rama `availability` |
| Datos de prueba | Script de seed de la rama `availability` (`npm run db:seed`) |
| Créditos AWS | Elimine el stack al terminar |

> [!NOTE]
> No se espera que llegue con experiencia previa en todas estas tecnologías. La columna **Recurso para entender qué hace** apunta a documentación oficial u otra referencia introductoria; revísela antes de tocar el template o el sidecar. Adicionalmente, se recomienda usar un asistente de IA (Claude, ChatGPT, etc.) para explorar cada servicio de AWS: pregúntele qué problema resuelve, qué recursos crea "por debajo" y qué pasaría si no existiera esa pieza en la arquitectura. Esto ayuda a construir intuición más allá de copiar comandos.

| Categoría                          | Tecnologías                                | Recurso para entender qué hace                                                                                     |
| ----------------------------------- | -------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| Infraestructura como Código        | AWS CloudFormation                            | [¿Qué es AWS CloudFormation?](https://docs.aws.amazon.com/es_es/AWSCloudFormation/latest/UserGuide/Welcome.html)     |
| Gateway de entrada + Rate Limiting | Amazon API Gateway (throttling por stage)     | [¿Qué es Amazon API Gateway?](https://docs.aws.amazon.com/es_es/apigateway/latest/developerguide/welcome.html)       |
| Orquestación de contenedores       | Amazon ECS (Fargate)                          | [¿Qué es Amazon ECS?](https://docs.aws.amazon.com/es_es/AmazonECS/latest/developerguide/Welcome.html) · [AWS Fargate](https://docs.aws.amazon.com/es_es/AmazonECS/latest/userguide/what-is-fargate.html) |
| Registro de imágenes               | Amazon ECR                                    | [¿Qué es Amazon ECR?](https://docs.aws.amazon.com/es_es/AmazonECR/latest/userguide/what-is-ecr.html)                 |
| Base de datos relacional           | Amazon RDS (PostgreSQL)                       | [¿Qué es Amazon RDS?](https://docs.aws.amazon.com/es_es/AmazonRDS/latest/UserGuide/Welcome.html)                     |
| Observabilidad                     | Amazon CloudWatch                             | [¿Qué es Amazon CloudWatch?](https://docs.aws.amazon.com/es_es/AmazonCloudWatch/latest/monitoring/WhatIsCloudWatch.html) |
| Framework backend                  | NestJS                                        | [Documentación de NestJS](https://docs.nestjs.com/)                                                                   |
| Lenguaje                           | TypeScript                                    | [Handbook de TypeScript](https://www.typescriptlang.org/docs/handbook/intro.html)                                     |
| ORM                                | TypeORM                                       | [Documentación de TypeORM](https://typeorm.io/)                                                                       |
| Proxy sidecar                       | Envoy Proxy                                  | [¿Qué es Envoy?](https://www.envoyproxy.io/docs/envoy/latest/intro/what_is_envoy) · [Patrón Sidecar](https://learn.microsoft.com/es-es/azure/architecture/patterns/sidecar) |
| Pruebas de carga                   | Apache JMeter                                 | [Guía de introducción a JMeter](https://jmeter.apache.org/usermanual/get-started.html)                                |

> [!IMPORTANT]
> **Sugerencia de prompt para IA:** *"Actúo como estudiante de arquitectura de software. Explícame qué hace [servicio de AWS], qué problema arquitectónico resuelve, qué recursos concretos crea cuando lo despliego con CloudFormation, y qué riesgos de disponibilidad o costo debería tener en cuenta al usarlo en un sistema de microservicios como el de este laboratorio."* Use esto como punto de partida, no como respuesta final: valide lo que la IA le diga contra la documentación oficial y contra lo que observe en su propio despliegue.

#### 4.5.2 Elementos de arquitectura involucrados

Servicios de Ventas e Inventario (y Logística como parte del stack), sidecar Envoy, API Gateway, base de datos RDS (tablas `outbox_http_calls` e `item_inventario`) y JMeter como generador de carga. El conector que se estudia es la llamada HTTP de Ventas a Inventario.

![Diagrama de despliegue y pruebas de carga](./recursos/diagrama_componentes.png)

*Figura 1. Vista de despliegue del laboratorio: API Gateway enruta hacia los servicios de Logística, Inventario y Ventas corriendo en ECS/Fargate; el sidecar Envoy corre como segundo contenedor dentro de la misma tarea de Ventas e intercepta el tráfico hacia Inventario; JMeter genera la carga de pruebas desde el computador del estudiante.*

> [!NOTE]
> Note que el sidecar se despliega como un contenedor adicional dentro de la misma tarea ECS que Ventas, y el tráfico entre Ventas e Inventario pasa a través del proxy Envoy. Esto permite implementar las tácticas de resiliencia sin modificar el código de negocio de Ventas, y ajustar los parámetros de retry y circuit breaker sin necesidad de redesplegar la aplicación.

#### 4.5.3 Esfuerzo estimado

Referencia para planear; puede variar según su experiencia con AWS.

| Etapa | Esfuerzo aprox. |
| --- | --- |
| Preparación de infraestructura con CloudFormation | 0,5 h |
| Configuración del sidecar y revisión del código | 0,5 h |
| Ronda de línea base: fallo en cascada | 0,5 h |
| Rondas con tácticas de resiliencia | 1 h |
| Ronda de Outbox e idempotencia | 1 h |
| Análisis y entregables | 0,5 h |
| **Total** | **4 h-persona** |

## 5. Ejecución del laboratorio

### 5.1 ¿Qué es Infraestructura como Código?

En los labs anteriores, la infraestructura se creó paso a paso desde la consola de AWS: security groups, instancias EC2, RDS, ECS, API Gateway. Este enfoque manual tiene un problema: es propenso a errores, difícil de reproducir y no deja registro de qué se configuró exactamente.

**Infraestructura como Código (IaaC)** resuelve esto declarando la infraestructura en un archivo de texto (código), que puede versionarse, revisarse y ejecutarse de forma reproducible. **AWS CloudFormation** es el servicio nativo de AWS para esto: usted define un *template* YAML o JSON que describe los recursos, y CloudFormation se encarga de crearlos, actualizarlos o eliminarlos.

### 5.2 El template de CloudFormation del laboratorio

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

> [!NOTE]
> Los prefijos de ruta de este laboratorio son **`logistica`/`inventario`**, a diferencia de `logistics`/`inventory usados en el Lab 4. El API Gateway traduce correctamente hacia los prefijos reales del backend (`/logistics/*`, `/inventory/*`); si prueba manualmente con los prefijos en inglés obtendrá 404.

### 5.3 Publicar las imágenes en ECR

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

### 5.4 Desplegar el stack

```bash
aws cloudformation deploy  --template-file lab_5/recursos/cloudformation_template.yaml  --stack-name Cheapest-lab5  --parameter-overrides LogisticaImageUri=<URI_ECR_LOGISTICA>:2.0.0 InventarioImageUri=<URI_ECR_INVENTARIO>:2.0.0 VentasImageUri=<URI_ECR_VENTAS>:2.0.0  VentasSidecarImageUri=<URI_ECR_SIDECAR>:1.0.0 DBPassword=<SU_CONTRASEÑA>  --region us-east-1
```

Monitoree el progreso en la consola de AWS → CloudFormation → Stack `Cheapest-lab5` → pestaña **Events**.

### 5.5 Verificar el despliegue

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

### 5.6 Cargar datos base

La base de datos RDS de este stack se crea con `PubliclyAccessible: false`, por lo que no es alcanzable desde su computador. El procedimiento es el mismo que usó en el Lab 4: hágala temporalmente pública y abra el puerto 5432 **solo para su IP**, corra el seed desde su máquina apuntando a la RDS real, y luego revierta ambos cambios.

```bash
# 1. Anote su IP pública actual
MY_IP=$(curl -s https://checkip.amazonaws.com)
echo $MY_IP

# 2. Identifique el Security Group de RDS del stack (tag Name: Cheapest-lab5-rds-sg)
SG_RDS_ID=$(aws ec2 describe-security-groups --filters Name=tag:Name,Values=Cheapest-lab5-rds-sg --query "SecurityGroups[0].GroupId" --output text)

# 3. Haga la instancia temporalmente pública
aws rds modify-db-instance --db-instance-identifier Cheapest-lab5-db --publicly-accessible --apply-immediately

# 4. Espere a que el cambio se aplique (puede tardar 1-2 minutos)
aws rds describe-db-instances --db-instance-identifier Cheapest-lab5-db --query "DBInstances[0].PubliclyAccessible"

# 5. Abra el puerto 5432 SOLO para su IP
aws ec2 authorize-security-group-ingress --group-id $SG_RDS_ID --protocol tcp --port 5432 --cidr ${MY_IP}/32

# 6. Corra el backend en local (rama availability) apuntando a la RDS real y sembrando datos
git checkout availability
npm install
DB_HOST=<RDS_ENDPOINT_DEL_STACK> DB_PORT=5432 DB_USER=postgres DB_PASSWORD=<SU_CONTRASEÑA> DB_NAME=Cheapest npm run db:seed
```

Al terminar, **revierta ambos cambios** para no dejar la base expuesta:

```bash
aws rds modify-db-instance --db-instance-identifier Cheapest-lab5-db --no-publicly-accessible --apply-immediately
aws ec2 revoke-security-group-ingress --group-id $SG_RDS_ID --protocol tcp --port 5432 --cidr ${MY_IP}/32
```

Con los datos sembrados, ya puede ejecutar las pruebas usando los IDs fijos de `seed.sql` (los mismos de los laboratorios anteriores: tienda `bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb`, producto `aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa`, moneda `cccccccc-cccc-4ccc-8ccc-cccccccccccc`).

### 5.7 Explorar lo que se desplegó

> [!IMPORTANT]
> Antes de seguir a la configuración del sidecar, tómese unos minutos para explorar en la consola de AWS lo que CloudFormation acaba de crear. El objetivo es que el stack no sea una "caja negra": usted debe poder señalar, para cada recurso relevante, con qué parte del template se corresponde y qué rol cumple en la arquitectura.

Realice los siguientes pasos:

1. En **CloudFormation → Stack `Cheapest-lab5` → pestaña Resources**, recorra la lista completa de recursos creados. Por cada tipo de recurso (VPC, Subnets, Security Groups, Target Groups, ALBs, Task Definitions, ECS Services, RDS, API Gateway), identifique la sección correspondiente en `cloudformation_template.yaml`.
2. En **ECS → Clusters**, entre al cluster del laboratorio y revise los tres servicios. Para cada uno, abra la pestaña **Tasks** y confirme que el estado es `RUNNING` y que los health checks pasan.
3. En **EC2 → Load Balancers**, ubique los ALBs creados y revise sus **Target Groups**: confirme que los targets registrados están `healthy`.
4. En **RDS → Databases**, ubique la instancia PostgreSQL y revise su Security Group: confirme que solo permite tráfico desde los security groups de los servicios (no desde `0.0.0.0/0`).
5. En **API Gateway**, abra la API `Cheapest-ms-api` y revise las rutas configuradas (`/logistica/*`, `/inventario/*`, `/ventas/*`) y el stage `lab`.
6. (Opcional, recomendado) Pídale a un asistente de IA que le ayude a interpretar algún recurso o configuración que no le quede clara — por ejemplo, pegue un fragmento del template o una captura de la consola y pregunte qué hace ese recurso específico y cómo se relaciona con los demás.

> [!IMPORTANT]
> **Actividad post-despliegue (hace parte de las evidencias que debe entregar):**
> Elija dos recursos creados por el stack que no haya usado directamente en laboratorios anteriores (por ejemplo, un Target Group, un rol IAM, o una ruta del API Gateway) y explique, en sus propias palabras, qué hacen y por qué son necesarios para que el laboratorio funcione. Acompañe su respuesta con una captura de pantalla de la consola de AWS por cada recurso elegido.

### 5.8 Configurar el sidecar y revisar el código

Las modificaciones de este laboratorio se dividen en tres partes:

1. La inyección de fallos en Inventario (ya implementada en el código base).
2. La **configuración del sidecar Envoy** en Ventas: aquí es donde usted define los parámetros de retry y circuit breaker.
3. Un ajuste mínimo en el servicio de Ventas para la graceful degradation.

#### Inyección de fallos con auto-recuperación en Inventario

El servicio de Inventario ya incorpora un mecanismo de fallo transitorio controlado por dos variables de entorno:

- `FAULT_DELAY_MS`: delay artificial en ms que se agrega a cada respuesta durante el período de fallo.
- `RECOVERY_TIME_MS`: tiempo en ms desde el arranque del proceso hasta que el servicio se recupera automáticamente.

Este código ya existe en `apps/inventario/src/fault.middleware.ts` y se aplica en el endpoint `GET /inventory/items/disponibilidad/:productoId` que Ventas consume. No es necesario modificarlo.

#### El sidecar Envoy: archivos y flujo

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

#### Completar la configuración de Envoy

Abra `apps/ventas/sidecar/envoy.yaml.tmpl`. Encontrará seis parámetros marcados con `???` y un comentario `TODO` que explica el criterio de diseño de cada uno. Debe reemplazar cada `???` con el valor que usted considera correcto.

Los seis puntos a completar son:

| # | Parámetro Envoy          | Sección              | Qué controla                                                                 |
| - | ------------------------ | -------------------- | ---------------------------------------------------------------------------- |
| 1 | `timeout`                | `route`              | Tiempo máximo total que el sidecar espera por una respuesta (incluyendo todos los reintentos) |
| 2 | `num_retries`            | `retry_policy`       | Número máximo de reintentos ante errores 5xx                                 |
| 3 | `base_interval`          | `retry_back_off`     | Espera base entre reintentos (Envoy añade ±25% de jitter automáticamente)    |
| 4 | `max_interval`           | `retry_back_off`     | Espera máxima entre reintentos                                               |
| 5 | `consecutive_5xx`        | `outlier_detection`  | Errores 5xx consecutivos que abren el circuito (estado OPEN)                 |
| 6 | `base_ejection_time`     | `outlier_detection`  | Tiempo que el circuito permanece OPEN antes de intentar HALF-OPEN            |

**Restricciones de calibración** (úselas para justificar los valores que escoja):

- `timeout` de la ruta ≥ `connect_timeout` × (1 + `num_retries`) + backoff acumulado; de lo contrario los reintentos son abortados por el propio sidecar.
- `num_retries` × factor de amplificación ≤ 2× el tráfico de la línea base. Es lo que exige el ASR-2: con reintentos activos, Inventario no debe recibir más del doble de las peticiones que recibe sin reintentos.
- `base_ejection_time` < `RECOVERY_TIME_MS` de Inventario, para que el estado HALF-OPEN pueda detectar la recuperación automática del servicio.

> [!IMPORTANT]
> **Pregunta 3 (parte B — valores implementados; es la continuación de la parte A, en la que propuso un conjunto inicial de parámetros):**
> Documente en su entregable los valores que eligió para cada `TODO`, la justificación cuantitativa de cada uno y cómo garantiza que no violan el ASR-2 (Inventario no recibe más del doble de las peticiones de la línea base).

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

#### Ajuste de código: respuesta degradada en Ventas

El sidecar maneja la capa de red. La decisión de negocio —qué responder al cliente cuando Inventario está caído— debe estar en el código de Ventas.

Cuando el circuito está OPEN, el sidecar devuelve HTTP 503 a Ventas. El cliente HTTP (`InventarioDisponibilidadClient`) convierte ese 503 en una excepción `ServiceUnavailableException`. Sin manejo explícito, esa excepción se propaga y Ventas retorna 503 al tendero.

El único cambio de código necesario es en `libs/ventas/src/services/venta.service.ts`: capturar la excepción y retornar la respuesta degradada:

```typescript
// Agregar ServiceUnavailableException al import existente de @nestjs/common
import {
  BadRequestException,
  Injectable,
  NotFoundException,
  ServiceUnavailableException,   // ← nuevo
} from '@nestjs/common';

// Tipo de retorno del método create (agrega la unión con el tipo degradado)
async create(dto: CreateVentaDto): Promise<VentaResponseDto | PendingStockConfirmationDto> {
  // ...
  // Reemplazar la llamada directa a isDisponible por un bloque try/catch:
  try {
    const disponible = await this.inventarioClient.isDisponible(item.productoId);
    if (!disponible) {
      throw new BadRequestException(
        `Producto con id ${item.productoId} sin stock disponible`,
      );
    }
  } catch (error) {
    // El sidecar abrió el circuito o Inventario no está disponible:
    // registrar la venta en modo degradado en lugar de cascadear el fallo.
    if (error instanceof ServiceUnavailableException) {
      return {
        ...dto,
        status: 'pending_stock_confirmation',
        message:
          'Pedido registrado. La disponibilidad de stock será confirmada próximamente.',
      };
    }
    throw error;  // otros errores (BadRequest, Not Found) se propagan normalmente
  }
  // ...
}
```

> Este cambio ya está aplicado en la rama `availability`. Revise el archivo para entender la implementación completa antes de continuar.

#### Variables de entorno adicionales

Actualice las Task Definitions del template CloudFormation con las siguientes variables:

| Servicio          | Variable                   | Valor para pruebas                                                         |
| ----------------- | -------------------------- | -------------------------------------------------------------------------- |
| Inventario        | `FAULT_DELAY_MS`           | `0` (baseline) / `5000` (degradado: 5s de delay)                           |
| Inventario        | `RECOVERY_TIME_MS`         | `600000` (el servicio se recupera 10 minutos después de arrancar)          |
| Ventas            | `INVENTARIO_BASE_URL`      | `http://localhost:10000` (apunta al sidecar en ECS)                        |
| Ventas            | `INVENTARIO_TIMEOUT_MS`    | `9000`                                                                     |
| Ventas sidecar    | `INVENTARIO_UPSTREAM_HOST` | `<ALB DNS del servicio de Inventario>`                                     |
| Ventas sidecar    | `INVENTARIO_UPSTREAM_PORT` | `80`                                                                       |

> Configure `base_ejection_time` del sidecar en un valor inferior a `RECOVERY_TIME_MS` (600s) para que el estado HALF-OPEN pueda detectar la recuperación automática de Inventario.

### 5.9 Cómo ver métricas en CloudWatch

> [!NOTE]
> **Amazon CloudWatch** es el servicio de observabilidad de AWS para ver métricas (series de tiempo), registros (logs) y alarmas. En este laboratorio lo usará principalmente para observar **cuántas peticiones llegan a Inventario** y **cuántos errores 5xx** se producen durante cada prueba. Estos pasos los repetirá en cada ronda de pruebas.

**Abrir CloudWatch (consola AWS):**

1. Verifique la región: arriba a la derecha seleccione **us-east-1** (la misma región donde desplegó el stack).
2. En la consola de AWS use el buscador y abra **CloudWatch**.
3. En el menú izquierdo: **Metrics** → **All metrics**.

**Ver requests y errores hacia Inventario (vía ALB/Target Group):**

1. En **All metrics** seleccione el namespace **ApplicationELB**.
2. Abra **TargetGroup, LoadBalancer** (o similar). Si no lo ve, pruebe también **LoadBalancer**.
3. Identifique el *target group* de Inventario (normalmente incluye “inventario” en el nombre) y marque estas métricas:
  - `RequestCount` (tráfico total hacia el target group)
  - `HTTPCode_Target_5XX_Count` (errores 5xx generados por el servicio)
  - `TargetResponseTime` (latencia del target vista por el ALB; no reemplaza el p99 de JMeter, pero ayuda a correlacionar)
4. En el gráfico, ajuste:
  - **Time range** al intervalo exacto de su prueba JMeter
  - **Period** a 1 minuto (recomendado) para ver cambios con claridad
  - **Statistic**: `Sum` para `RequestCount` y `HTTPCode_Target_5XX_Count`

> Para estimar *requests/s* desde CloudWatch: si su `RequestCount` es por minuto (period=60s), entonces $\text{req/s} \approx \text{RequestCount}/60$.

## 6. Realización de pruebas

En la sección anterior dejó desplegado el stack, configurado el sidecar y revisado el código. Aquí se explica qué debe modificar de ese despliegue en cada ronda de pruebas y qué parámetros puede ajustar para mejorar o empeorar el comportamiento del sistema.

### 6.1 Puntos de sensibilidad

| Punto de sensibilidad | Dónde se modifica | Efecto esperado |
| --- | --- | --- |
| **Duración del fallo de Inventario** (`FAULT_DELAY_MS`) | Parámetro `FaultDelayMs` del template de CloudFormation (vuelva a ejecutar `aws cloudformation deploy` agregando `FaultDelayMs=5000` a `--parameter-overrides`), o una nueva revisión de la task definition de Inventario en la consola de ECS. | `0` = Inventario sano. `5000` = cada respuesta tarda 5 s: el fallo que se quiere estudiar. |
| **Tiempo hasta la recuperación** (`RECOVERY_TIME_MS`) | Parámetro `RecoveryTimeMs` del template (por defecto `60000`), o la task definition de Inventario. | Define cuánto dura el incidente desde que arranca la tarea de Inventario. Con `600000` hay 10 minutos para medir. |
| **Presencia del sidecar** | Task definition de Ventas: con un solo contenedor (`ventas`) y `INVENTARIO_BASE_URL` apuntando al balanceador de Inventario, no hay sidecar; con el contenedor `ventas-sidecar` y `INVENTARIO_BASE_URL=http://localhost:10000`, las llamadas pasan por Envoy. | Sin sidecar no hay timeout corto, ni reintentos, ni circuit breaker. |
| **Reintentos** (`num_retries`, `base_interval`, `max_interval`) | Archivo `apps/ventas/sidecar/envoy.yaml.tmpl`. Cada cambio exige reconstruir la imagen del sidecar, publicarla en ECR con un tag nuevo y actualizar el servicio de Ventas en ECS. | Más reintentos recuperan más fallos transitorios, pero multiplican las peticiones que recibe Inventario. |
| **Timeout de la ruta** (`timeout`) | El mismo archivo `envoy.yaml.tmpl`. | Un timeout corto libera rápido a Ventas, pero puede cortar peticiones que habrían respondido. |
| **Umbral de apertura del circuito** (`consecutive_5xx`) | El mismo archivo `envoy.yaml.tmpl`, sección `outlier_detection`. | Bajo: el circuito abre rápido, incluso por fallos pasajeros. Alto: tarda en abrir y el fallo se propaga más tiempo. |
| **Tiempo que el circuito permanece abierto** (`base_ejection_time`) | El mismo archivo `envoy.yaml.tmpl`, sección `outlier_detection`. | Corto: prueba con frecuencia si Inventario se recuperó. Largo: Ventas tarda en notar la recuperación. |
| **Timeout de Ventas hacia el sidecar** (`INVENTARIO_TIMEOUT_MS`) | Variable de entorno del contenedor `ventas`. | Debe ser mayor que el timeout total del sidecar; si es menor, Ventas aborta antes de que Envoy termine sus reintentos. |
| **Límite de peticiones** (*Rate* y *Burst*) | API Gateway → `Cheapest-ms-api` → stage `lab` → *Default route throttling*. | Un límite bajo protege a los servicios, pero rechaza peticiones legítimas. |
| **Carga** | Threads y ramp-up de JMeter. | Define el nivel de carga de cada fila de la matriz. |

### 6.2 Matriz de carga

Todas las rondas usan la misma matriz sobre `POST /ventas`, para que sean comparables:

| Test | Ramp-Up | Threads | Loops |
| --- | --- | --- | --- |
| Baja carga | 10s | 50 | 1 |
| Carga media | 20s | 200 | 1 |
| Operación normal | 50s | 500 | 1 |
| Alta carga | 75s | 1500 | N/A |

Registre para cada fila: p99, error %, throughput total y peticiones por segundo recibidas por Inventario (se obtienen de CloudWatch).

### 6.3 Ronda 1 — Línea base: reproducir el fallo en cascada

**Qué modificar del despliegue:**

1. En la consola de AWS → ECS → Task Definition `td-Cheapest-inventario`, cree una nueva revisión con:
   - `FAULT_DELAY_MS=5000`
   - `RECOVERY_TIME_MS=600000`
2. Actualice el servicio ECS de Inventario para que use la nueva revisión y espere a que las tareas sean reemplazadas.
3. Asegúrese de que **la tarea de Ventas esté desplegada sin el sidecar** para esta línea base: use una task definition con un solo contenedor (`ventas`) y `INVENTARIO_BASE_URL` apuntando directamente al balanceador de Inventario.

> Con esta configuración, Inventario arrancará degradado y responderá con 5s de delay. Pasados 10 minutos desde el arranque, se recuperará automáticamente. Anote el momento exacto de arranque de la tarea (visible en ECS → Tasks → Started at) para correlacionarlo con las métricas de JMeter.

**Ejecución.** Ejecute la matriz de carga con JMeter sobre `POST /ventas`. El endpoint de Ventas hace una llamada interna a Inventario, que ahora responde con 5 segundos de retraso. Consulte en CloudWatch las peticiones y los errores del target group de Inventario durante cada corrida.

**Qué observar:**

- Latencia de Ventas: ¿cómo se propaga el delay de 5s de Inventario?
- Error % de Ventas: ¿empieza a devolver errores 500 o 503?
- Requests totales a Inventario: ¿aumentan con el tiempo?
- **Recuperación espontánea**: ¿qué sucede con la latencia de Ventas a los 600s del arranque de Inventario? ¿El sistema se recupera solo? ¿Cuánto tarda Ventas en notar que Inventario ya está bien?
- Punto de colapso: ¿a partir de cuántos threads el sistema deja de responder?

> Anote estos valores como Base. Son el punto de comparación para las tácticas. La recuperación espontánea en el baseline es el caso de control: sin circuit breaker, el sistema se recupera cuando Inventario se recupera, pero el tiempo de recuperación percibido por Ventas puede ser mayor de lo esperado.

### 6.4 Ronda 2 — Reintentos con backoff exponencial y jitter (sidecar)

Aplique y pruebe cada táctica de forma incremental, usando la misma matriz de carga de la línea base para que los resultados sean comparables. A partir de esta ronda, la tarea de Ventas incluye el sidecar Envoy.

**Qué modificar del despliegue:**

Active el sidecar en la Task Definition de Ventas. Para esta ronda, configure el sidecar **solo con la política de retry** (deje `outlier_detection` comentado o con `enforcing_consecutive_5xx: 0`). Publique las imágenes `2.1.0` y actualice el servicio ECS.

El sidecar se activa en la Task Definition agregando el container `ventas-sidecar` junto a `ventas` y ajustando `INVENTARIO_BASE_URL=http://localhost:10000` en el container de ventas.

**Comportamiento esperado**: ante un fallo de Inventario, el sidecar reintenta automáticamente con el backoff que usted configuró, antes de devolver error a Ventas.

**Qué medir**:
- ¿El p99 de Ventas mejora respecto al baseline?
- ¿El volumen de requests a Inventario aumenta? ¿En qué factor? (verificar ASR-2 — no debe superar 2×)
- ¿El error % de Ventas mejora? Si Inventario falla consistentemente, el retry no resolverá el error, solo lo retrasará.
- Verifique los logs del sidecar en CloudWatch (grupo de logs del container `ventas-sidecar`): debe ver los reintentos con sus intervalos de backoff.

> **Observación clave**: el retry solo ayuda con fallos transitorios. Para fallos persistentes (como el delay de 5s que simulamos), el retry amplifica la carga sin mejorar la disponibilidad. Este es el problema que el circuit breaker resuelve.

### 6.5 Ronda 3 — Circuit breaker con respuesta degradada (sidecar y código)

**Qué modificar del despliegue:**

Active la `outlier_detection` en el sidecar con los valores que definió en `envoy.yaml.tmpl`. Publique la imagen del sidecar `2.2.0` y actualice el servicio ECS.

**Comportamiento esperado**:
- Primeras llamadas: el circuito está **CLOSED**; las llamadas llegan a Inventario y fallan (delay 5s → timeout).
- Tras `consecutive_5xx` errores seguidos: el sidecar eyecta el host y el circuito pasa a **OPEN**.
- En estado OPEN: el sidecar rechaza las llamadas inmediatamente con 503. Ventas captura el 503 y retorna `status: pending_stock_confirmation` con HTTP 200 en p99 muy bajo.
- Tras `base_ejection_time` segundos: el sidecar intenta **HALF-OPEN** enviando una sola request de prueba a Inventario.
  - Si Inventario sigue degradado: la prueba falla → vuelve a OPEN.
  - **Si Inventario se recuperó** (después de los 600s): la prueba tiene éxito → el circuito vuelve a **CLOSED** y el flujo normal se restaura automáticamente.

Esta es la demostración clave del laboratorio: el circuit breaker no solo protege durante el fallo, sino que **detecta la recuperación** del servicio sin intervención humana.

**Cómo observar el estado del circuito en tiempo real:**

```bash
# Desde su máquina, con port-forward al puerto admin del sidecar (9901)
# o accediendo al endpoint de admin si está expuesto en la Task Definition
curl http://localhost:9901/clusters | grep -E "ejected|cx_active|rq_total"
```

El campo `outlier_detection.ejections_active` > 0 indica que el circuito está OPEN.

**Qué medir**:
- ¿El p99 de Ventas cae significativamente una vez el circuito está OPEN?
- ¿El error % de Ventas llega a 0% una vez que el circuito está abierto?
- ¿Cuántos requests llegan a Inventario en estado OPEN vs. estado CLOSED?
- **¿En qué momento exacto el circuito pasa a CLOSED tras la recuperación de Inventario?**
- Observe los logs de acceso del sidecar en CloudWatch para identificar las transiciones de estado.

### 6.6 Ronda 4 — Rate limiting en API Gateway y combinación de las tres tácticas

**Qué modificar del despliegue:** configure el límite de peticiones (*throttling*) en el stage `lab` del API Gateway.

**Configuración sugerida**:

| Parámetro | Valor | Justificación |
| --- | --- | --- |
| Rate (req/s) | 100 | Límite sostenido para operación normal de Cheapest |
| Burst | 200 | Permite absorber picos breves sin rechazar pedidos legítimos |

Pasos en la consola de AWS:

1. API Gateway → seleccione `Cheapest-ms-api`.
2. Stage `lab` → **Default route throttling**.
3. Configure `Rate` y `Burst` con los valores de la tabla.
4. Haga clic en **Save**.

**Prueba**: ejecute una carga que supere el rate limit (ej. 300 req/s). Observe que API Gateway devuelve HTTP 429 para las requests que superan el límite. Las requests dentro del límite deben seguir respondiendo normalmente.

**Qué medir**:
- ¿Qué porcentaje de las requests recibe HTTP 429?
- ¿El throughput de las requests que pasan el límite se mantiene estable?
- ¿Cómo cambia el comportamiento de Inventario al estar protegido por el rate limit?

**Combinación de las tres tácticas.** Con las tres tácticas activas simultáneamente (sidecar completo y rate limiting en API Gateway), ejecute la misma matriz de carga. Esta es la configuración final de las tácticas de resiliencia.

> [!IMPORTANT]
> **Pregunta 4:**
> Si las tres tácticas cumplen ASRs en este laboratorio, ¿qué riesgo residual seguiría existiendo para una operación real de Cheapest a mayor escala?
> Responda identificando al menos dos clases de fallos que estas tácticas no resuelven por sí solas y qué capacidad adicional haría falta.

### 6.7 Ronda 5 — Consistencia bajo fallo: Outbox e idempotencia

#### El problema que el circuit breaker no resuelve

El circuit breaker y la "caida con gracia" mantienen a Ventas *disponible*: el tendero recibe HTTP 200 incluso cuando Inventario está caído. Pero hay un efecto secundario silencioso: **el stock nunca se decrementó**. Cuando Inventario se recupera, el sistema no sabe cuántas ventas ocurrieron mientras estaba caído.

Peor aún, cuando se retoman llamadas normales (circuito HALF-OPEN → CLOSED), si un cliente externo reintentó su llamada durante la degradación, el decremento puede llegar dos veces.

Esto demuestra que **resiliencia de infraestructura ≠ consistencia de datos**.

#### Fase 0 — Demostración del problema (sin Outbox ni idempotencia)

> [!NOTE]
> Esta ronda se ejecuta **en su computador**, con los tres servicios y la base de datos levantados con Docker Compose desde la rama `availability` (`docker compose up`), porque necesita apagar y encender Inventario a voluntad. `<BASE_URL>` es la dirección local de cada servicio: `http://localhost:3002` para Inventario y `http://localhost:3003` para Ventas.

Para ver el problema, ejecute el siguiente flujo con el código de la rama **antes del commit del Outbox** (o revierta el `VentaService` a la versión sin `OutboxHttpCall`):

1. Registrar el stock inicial de un producto:
   ```bash
   GET <BASE_URL>/inventory/items/<itemInventarioId>
   # Anotar cantidad inicial
   ```

2. Bajar el contenedor de Inventario:
   ```bash
   docker-compose stop inventario
   ```

3. Crear 3 ventas (el circuit breaker está cerrado al principio, se abrirá tras algunos fallos):
   ```bash
   POST <BASE_URL>/ventas/ventas
   { "tiendaId": "...", "items": [{ "productoId": "...", "cantidad": 1, ... }] }
   # Repetir 3 veces — primeros pedidos fallarán; cuando el circuito abre, retornarán pending_stock_confirmation
   ```

4. Restaurar Inventario:
   ```bash
   docker-compose start inventario
   ```

5. Esperar 30 segundos y verificar el stock:
   ```bash
   GET <BASE_URL>/inventory/items/<itemInventarioId>
   ```
   **Resultado esperado**: la cantidad NO cambió — el stock sigue igual aunque se registraron ventas.

6. Enviar la misma venta dos veces consecutivas (simula retry de cliente):
   ```bash
   POST <BASE_URL>/ventas/ventas
   # Misma petición dos veces
   ```
   Luego verificar stock: bajó en 2 cuando debería haber bajado en 1.

> [!IMPORTANT]
> **Pregunta 5:**
> Describa con precisión el estado de inconsistencia que se produce en cada escenario:
> 1. Ventas registradas durante degradación: ¿qué diferencia hay entre lo que dice `ventas` en PostgreSQL y lo que dice `item_inventario.cantidad`?
> 2. Retry sin idempotencia: ¿qué invariante de negocio se viola? ¿Cómo lo detectaría operacionalmente en Cheapest?

#### Conceptos: Outbox e idempotencia

##### Outbox HTTP

El **patrón Outbox** resuelve la inconsistencia del escenario 1. En lugar de intentar decrementar el stock en el mismo momento que se crea la venta (lo cual falla si Inventario está caído), se escribe en una tabla local `outbox_http_calls` dentro de **la misma transacción** que guarda la venta:

```
POST /ventas/ventas
  ├── INSERT ventas                ┐
  └── INSERT outbox_http_calls     ┘  misma transacción → atomicidad garantizada
                                       si la tx hace commit, el decremento llegará eventualmente
                                       si la tx hace rollback, tampoco queda ningún outbox pendiente

OutboxHttpPublisherService (polling 2 s):
  SELECT * FROM outbox_http_calls WHERE status = 'PENDING'
  → POST /inventory/ventas/desde-outbox (con X-Idempotency-Key)
  → UPDATE SET status = 'DELIVERED' si 2xx o 409
```

La garantía: **at-least-once** — si la venta se guardó, el decremento de stock se entregará eventualmente, incluso si Inventario estuvo caído horas.

##### Idempotencia

El **patrón de Idempotencia** resuelve la inconsistencia del escenario 2. El publisher puede enviar el mismo `OutboxHttpCall` más de una vez (si falla entre enviar y marcar `DELIVERED`). El endpoint `/inventory/ventas/desde-outbox` usa el `id` del `OutboxHttpCall` como `X-Idempotency-Key`:

```
POST /inventory/ventas/desde-outbox  (Header: X-Idempotency-Key: <outbox-id>)
  → ¿Existe processed_calls WHERE idempotencyKey = <outbox-id>?
      SÍ → responder 409 (ya procesado, no hacer nada)
      NO → decrementar stock + INSERT processed_calls en la misma transacción
```

Combinando at-least-once (Outbox) con idempotencia (ProcessedCall), el sistema efectivamente garantiza que cada venta decrementa el stock **exactamente una vez**.

#### Revisar la escritura transaccional en `VentaService`

Archivo: `libs/ventas/src/services/venta.service.ts`

El método `create()` ya implementa el Outbox. Revise el código y verifique:
1. La `Venta` y el `OutboxHttpCall` se guardan en la misma transacción. ¿Qué ocurre si el proceso muere entre el `manager.save(Venta)` y el `manager.save(OutboxHttpCall)`?
2. ¿Por qué el `OutboxHttpCall` se crea incluso en el path degradado (`isDegraded = true`)?
3. ¿Qué payload lleva el `OutboxHttpCall`? Verifique que incluye todos los campos que `POST /inventory/ventas/desde-outbox` necesita.

#### Revisar el endpoint con idempotencia en Inventario

Archivo: `libs/inventario/src/services/registro-venta.service.ts` → método `createDesdeOutbox()`

Analice el flujo implementado y responda:
1. ¿Qué ocurre si el proceso de Inventario muere entre `decrementCantidad()` y el `save(ProcessedCall)`? ¿Puede producirse un decremento sin ProcessedCall?
2. ¿Por qué se usa el `id` del `OutboxHttpCall` como clave de idempotencia en lugar del `ventaId`?

#### Fase 2 — Verificación del Outbox y la idempotencia

Con el código completo del Outbox activado:

1. Registrar el stock inicial:
   ```bash
   GET <BASE_URL>/inventory/items/<itemInventarioId>
   # Anotar cantidad
   ```

2. Bajar Inventario:
   ```bash
   docker-compose stop inventario
   ```

3. Crear 3 ventas — deberían retornar `pending_stock_confirmation`:
   ```bash
   POST <BASE_URL>/ventas/ventas  # x3
   ```

4. Verificar que hay OutboxHttpCalls pendientes:
   ```sql
   SELECT id, status, attempts FROM outbox_http_calls ORDER BY created_at DESC LIMIT 5;
   ```
   **Esperado**: `status = 'PENDING'`, `attempts` creciendo cada 2 s.

5. Restaurar Inventario y esperar ~10 s:
   ```bash
   docker-compose start inventario
   ```

6. Verificar reconciliación automática:
   ```sql
   SELECT id, status, delivered_at FROM outbox_http_calls ORDER BY created_at DESC LIMIT 5;
   ```
   **Esperado**: `status = 'DELIVERED'`.

   ```bash
   GET <BASE_URL>/inventory/items/<itemInventarioId>
   ```
   **Esperado**: la cantidad bajó exactamente en 3 (una por cada venta).

7. Probar idempotencia: enviar de nuevo `POST /inventory/ventas/desde-outbox` con el mismo `X-Idempotency-Key`:
   ```bash
   POST <BASE_URL>/inventory/ventas/desde-outbox
   Header: X-Idempotency-Key: <id-del-outbox-call>
   ```
   **Esperado**: HTTP 409. La cantidad no cambia.

#### Impacto del Outbox en la latencia

Repita la fila de 500 threads y 50 s de ramp-up sobre `POST /ventas` con Inventario sano (sin inyección de fallos, `FAULT_DELAY_MS=0`) y el Outbox activo, para que el circuito esté CLOSED y cada petición haga la escritura transaccional completa (la venta y su fila de Outbox). Compare el resultado con la misma fila de la ronda de tácticas combinadas, que no tenía Outbox: la diferencia es el costo en latencia de la escritura adicional.

### 6.8 Cómo leer los resultados

Analice los resultados con enfoque en disponibilidad:

- p99 y error % de Ventas en cada ronda (línea base, reintentos, circuit breaker, tácticas combinadas).
- Peticiones recibidas por Inventario en cada ronda (CloudWatch: `RequestCount` del target group de Inventario).
- Transiciones de estado del circuit breaker correlacionadas con la carga (registros del sidecar en CloudWatch).
- Peticiones rechazadas por API Gateway (HTTP 429).

**Umbrales por ASR:**

- **ASR-1** (Ventas sigue respondiendo cuando Inventario falla): Ventas responde HTTP 200 con `pending_stock_confirmation` en p99 < 3000 ms durante el fallo de Inventario. Se verifica en la ronda con circuit breaker activo en el sidecar.
- **ASR-2** (los reintentos no amplifican la carga): las peticiones a Inventario con reintentos activos son ≤ 2× las de la línea base. Se verifica comparando en CloudWatch la ronda de línea base con la ronda de reintentos.
- **ASR-3** (el tráfico excedente no afecta los pedidos): con rate limiting activo, el throughput de pedidos válidos cae menos de 10% respecto a la línea base. Se verifica en la ronda con rate limiting.
- **ASR-4** (cada venta degradada descuenta su stock exactamente una vez): se verifica en dos dimensiones:
  - **Consistencia**: toda venta con `pending_stock_confirmation` pasa a `DELIVERED` en menos de 30 s tras la recuperación de Inventario; ningún `item_inventario.cantidad` refleja descuentos duplicados.
  - **Impacto en latencia**: el p99 de `POST /ventas` con Inventario sano y Outbox activo no debe superar en más de 50 ms el p99 de la ronda de tácticas combinadas sin Outbox. Esto verifica que la escritura adicional en `outbox_http_calls` no degrada perceptiblemente la operación principal.

## 7. Entregables

Entregue un informe organizado con los siguientes numerales.

### 7.1 Resultados

#### 7.1.1 ¿Qué se observó?

Describa, sin interpretar todavía, lo que observó en cada ronda:

- **Línea base:** cómo se propagó a Ventas el retraso de 5 s de Inventario, qué errores devolvió Ventas (500, 503, tiempos de espera agotados), a partir de cuántos threads dejó de responder, y qué pasó a los 600 s del arranque de Inventario, cuando este se recuperó solo.
- **Reintentos:** qué pasó con la latencia y los errores de Ventas, y con el número de peticiones que recibió Inventario.
- **Circuit breaker:** en qué momento se abrió el circuito, qué respondió Ventas mientras estuvo abierto y en qué momento volvió a cerrarse tras la recuperación de Inventario.
- **Rate limiting y tácticas combinadas:** qué proporción de las peticiones fue rechazada con 429 y qué pasó con las que sí pasaron.
- **Outbox e idempotencia:** qué pasó con el stock y con la tabla `outbox_http_calls` sin los patrones y con ellos, y qué respondió Inventario ante una petición repetida.

#### 7.1.2 ¿Qué métricas se obtuvieron?

Entregue una tabla comparativa con los resultados de las cuatro rondas de tácticas:

| Ronda | p99 Ventas (ms) | Error % Ventas | Requests/s a Inventario | HTTP 429 % |
| --- | ---: | ---: | ---: | ---: |
| Baseline (sin sidecar, sin protecciones) | | | | N/A |
| Sidecar: retry + backoff | | | | N/A |
| Sidecar: circuit breaker + graceful degradation | | | | N/A |
| Sidecar completo + rate limiting API Gateway | | | | |

Entregue también, **por cada ronda**, una tabla por fila de la matriz de carga:

| # threads | Ramp-up (s) | p99 (ms) | p95 (ms) | Throughput (req/s) | Error % |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 50 | 10 | | | | |
| 200 | 20 | | | | |
| 500 | 50 | | | | |
| 1500 | 75 | | | | |

Agregue los datos de la ronda de Outbox e idempotencia:

**a. Impacto en latencia de `POST /ventas` (Inventario sano, circuito CLOSED):**

| Ronda | p99 Ventas (ms) | p95 Ventas (ms) | Throughput (req/s) | Error % |
| --- | ---: | ---: | ---: | ---: |
| Tácticas combinadas (sin Outbox) | | | | |
| Tácticas combinadas + Outbox activo | | | | |
| Δ absoluto (con Outbox − sin Outbox) | | | | |

> Use la fila de 500 threads y 50 s de ramp-up con Inventario sano (sin inyección de fallos).

**b. Consistencia y reconciliación:**

| Fase | Descripción | `outbox_http_calls` PENDING → DELIVERED (s) | Descuentos duplicados |
| --- | --- | ---: | ---: |
| Fase 0 — sin Outbox ni idempotencia | Problema: ventas sin descuento de stock y descuentos duplicados | N/A | sí |
| Fase 2 — con Outbox e idempotencia | Solución aplicada | | 0 |

Reporte también los seis valores que escogió en `envoy.yaml.tmpl` y los valores de *Rate* y *Burst* de API Gateway.

### 7.2 Análisis de resultados

Extensión sugerida para el análisis completo: 1 a 2 páginas.

#### 7.2.1 ¿Qué significan los datos frente al escenario de calidad?

Para cada ASR, compare lo medido con su medida de respuesta e indique si se cumple:

- **ASR-1** (Ventas responde HTTP 200 con `pending_stock_confirmation` en p99 < 3000 ms durante el fallo de Inventario). ¿Qué diferencia operativa tiene para un tendero recibir un error 500 frente a `status: pending_stock_confirmation`? ¿Bajo qué condiciones la degradación es aceptable para el negocio?
- **ASR-2** (con reintentos activos, Inventario no recibe más del doble de las peticiones de la línea base). ¿Por qué el reintento sin backoff ni jitter puede empeorar una situación de fallo? Relacione la respuesta con el escenario de Cheapest (tenderos reintentando pedidos en el pico del lunes).
- **ASR-3** (el rate limiter rechaza el excedente con 429 sin que el throughput de pedidos válidos caiga más de 10%). ¿Por qué el rate limiting en API Gateway protege mejor ante una avalancha de reintentos que un rate limiting implementado dentro del propio servicio?
- **ASR-4** (toda venta degradada pasa de PENDING a DELIVERED en menos de 30 s tras la recuperación, sin descuentos duplicados). Con base en los datos de impacto en latencia, ¿el patrón Outbox aumenta la latencia de `POST /ventas`? Argumente en qué condiciones ese costo sería aceptable para Cheapest y en cuáles representaría un riesgo para los ASRs. Considere el volumen transaccional, la latencia de la base de datos RDS y si la escritura adicional en `outbox_http_calls` ocurre dentro o fuera de la transacción principal.
- ¿En qué momento el circuit breaker debería pasar al estado HALF-OPEN? ¿Qué riesgos hay en hacerlo demasiado pronto frente a demasiado tarde? Sustente con los tiempos que midió.

#### 7.2.2 ¿Se cumple la hipótesis?

Para cada hipótesis indique si se cumple, se cumple parcialmente o no se cumple, y con qué dato lo sustenta:

- H1: con circuit breaker y respuesta degradada, `POST /ventas` responde HTTP 200 con `pending_stock_confirmation` en p99 < 3000 ms aun con Inventario en falla total.
- H2: con reintentos con backoff exponencial y jitter, Inventario no recibe más del doble de las peticiones de la línea base.
- H3: con rate limiting en API Gateway, el tráfico excedente se rechaza con 429 sin que el throughput de pedidos válidos caiga más de 10%.
- H4: con Outbox e idempotencia, cada descuento de stock pendiente se entrega exactamente una vez tras la recuperación, en menos de 30 s.

### 7.3 Conclusión

#### 7.3.1 ¿Qué se aprendió del experimento?

Más allá de si cada táctica funcionó, reflexione sobre:

- ¿Cómo se complementan los reintentos y el circuit breaker en el sidecar? ¿Pueden entrar en conflicto? Describa un escenario concreto en el que usarlos juntos sin coordinación generaría un problema.
- ¿Por qué "entrega al menos una vez" más idempotencia no equivale a una garantía distribuida de "exactamente una vez"? ¿Qué requeriría una garantía real de exactamente una vez entre dos servicios con bases de datos independientes?
- ¿Qué ventajas concretas tuvo desplegar con CloudFormation frente a la configuración manual del Lab 4? ¿En qué escenarios del negocio de Cheapest (por ejemplo, la expansión a México o Brasil, o un incidente que obligue a reconstruir el ambiente) sería crítica esta capacidad?

### 7.4 Decisión arquitectónica

#### 7.4.1 ¿Qué se decide?

Para cada táctica (reintentos con backoff y jitter, circuit breaker con respuesta degradada, rate limiting en API Gateway, Outbox con idempotencia) indique si la **adopta, la modifica o la descarta** para Cheapest, y con qué parámetros. Incluya en su decisión:

- En este laboratorio las tácticas de resiliencia se implementaron en un sidecar y no en el código de negocio. ¿Qué ventajas concretas tuvo este enfoque? ¿En qué escenarios el sidecar no sería suficiente y se necesitaría lógica de resiliencia dentro de la aplicación?

#### 7.4.2 ¿Qué cambios se hacen a la arquitectura?

- Describa los cambios que quedan en la arquitectura de Cheapest después del experimento: qué componentes nuevos se agregan, con qué configuración y qué reglas de negocio hay que acordar (por ejemplo, cuánto tiempo puede quedar un pedido como pendiente de confirmación de stock).
- Lea el artículo [Failure Mitigation for Microservices: An Intro to Aperture](https://careersatdoordash.com/blog/failure-mitigation-for-microservices-an-intro-to-aperture/) de DoorDash. ¿Qué problema específico resuelve Aperture que el sidecar Envoy de este laboratorio no resuelve? ¿En qué punto del crecimiento de Cheapest tendría sentido adoptar un enfoque centralizado como ese?

### 7.5 Respuestas a las preguntas orientadoras

Incluya las respuestas argumentadas a las preguntas planteadas a lo largo del laboratorio. Cada respuesta debe incluir los elementos que pide la pregunta (tablas, gráficas o diagramas) y debe ir más allá de lo superficial. Se repiten aquí para que no tenga que buscarlas:

- **Pregunta 1.** En Cheapest, ¿qué decisión de producto y operación debería tomarse primero cuando aparece una avalancha de reintentos: proteger la disponibilidad percibida (respuestas degradadas) o proteger la consistencia estricta (rechazar operaciones)? Argumente considerando el impacto en tenderos, el riesgo financiero y el costo de reconciliación posterior.
- **Pregunta 2.** Si usted fuera el líder encargado de ejecutar en Cheapest el plan de cinco rondas (línea base, reintentos, circuit breaker, tácticas combinadas, Outbox e idempotencia), ¿seguiría ese orden, teniendo en cuenta el riesgo de estos cambios? Describa un plan de migración que mitigue los riesgos, con etapas, tiempo estimado por etapa y tareas de cada una.
- **Pregunta 3 (partes A y B, se responden y califican juntas).** Parte A: los reintentos, el circuit breaker y el rate limiting pueden entrar en conflicto si se calibran mal. Proponga un conjunto coherente de parámetros iniciales para Cheapest (timeouts, reintentos, umbral de apertura, tiempo de reapertura, rate y burst) y justifique cómo evitaría inestabilidad sistémica. Parte B: documente los valores que finalmente eligió para cada `TODO` de `envoy.yaml.tmpl`, la justificación cuantitativa de cada uno y cómo garantiza que no violan el ASR-2 (Inventario no recibe más del doble de las peticiones de la línea base).
- **Pregunta 4.** Si las tres tácticas cumplen los ASRs en este laboratorio, ¿qué riesgo residual seguiría existiendo para una operación real de Cheapest a mayor escala? Identifique al menos dos clases de fallos que estas tácticas no resuelven por sí solas y qué capacidad adicional haría falta.
- **Pregunta 5.** Describa con precisión el estado de inconsistencia que se produce en cada escenario de la demostración sin Outbox ni idempotencia: (1) ventas registradas durante la degradación: ¿qué diferencia hay entre lo que dice la tabla `ventas` y lo que dice `item_inventario.cantidad`?; (2) reintento sin idempotencia: ¿qué invariante de negocio se viola y cómo lo detectaría operacionalmente en Cheapest?
- **Revisión de la escritura transaccional en `VentaService`.** ¿Qué ocurre si el proceso muere entre el guardado de la venta y el guardado de su fila de Outbox? ¿Por qué la fila de Outbox se crea incluso cuando la venta se registra en modo degradado? ¿Qué datos lleva la fila de Outbox y son suficientes para lo que necesita `POST /inventory/ventas/desde-outbox`?
- **Revisión del endpoint con idempotencia en Inventario.** ¿Qué ocurre si el proceso de Inventario muere entre el descuento de stock y el guardado de la clave procesada? ¿Puede producirse un descuento sin clave registrada? ¿Por qué se usa como clave de idempotencia el `id` de la fila de Outbox y no el `ventaId`?

### 7.6 Evidencias

Adjunte capturas de:

- Stack CloudFormation en estado `CREATE_COMPLETE`.
- Actividad post-despliegue: los dos recursos del stack que eligió al explorar lo que se desplegó, con una captura de la consola por cada uno y su explicación.
- Task Definition de Ventas mostrando los **dos containers**: `ventas` y `ventas-sidecar`.
- Servicios ECS de los tres microservicios en estado RUNNING.
- API Gateway con throttling configurado devolviendo HTTP 429.
- `envoy.yaml.tmpl` con los valores completados por el estudiante (los seis `TODO`).
- Logs de CloudWatch del container `ventas-sidecar` mostrando: reintentos (acceso log con múltiples líneas por request) y transiciones de estado del circuit breaker (`ejections_active`).
- Respuesta HTTP 200 con `status: pending_stock_confirmation` capturada en JMeter durante el fallo de Inventario.
- Summary Report de JMeter para la ronda baseline y la ronda con tácticas combinadas.
- Captura de la tabla `outbox_http_calls` en estado PENDING durante el fallo de Inventario.
- Captura de la misma tabla con status DELIVERED tras la recuperación.
- Respuesta HTTP 409 ante un retry con el mismo `X-Idempotency-Key`.
- Valor de `item_inventario.cantidad` antes y después de la reconciliación: debe bajar exactamente N unidades (una por cada venta creada en degradación).

Adjunte también:

- Los prompts utilizados (si usó IA).
- Los scripts adicionales de carga (si aplica).

### 7.7 Formato de entrega

Un informe en PDF o Word con los numerales de resultados, análisis de resultados, conclusión, decisión arquitectónica, respuestas a las preguntas orientadoras y evidencias.

> [!IMPORTANT]
> **¿A dónde se suben los entregables?**
> A la Actividad correspondiente en el aula de Bloque Neón de su sección.

## Nota final (créditos AWS)

Cuando termine el laboratorio, elimine todos los recursos para evitar consumo innecesario de créditos:

```bash
aws cloudformation delete-stack --stack-name Cheapest-lab5 --region us-east-1
```

Verifique en la consola que el stack pase a estado `DELETE_COMPLETE` y que no queden recursos huérfanos (especialmente instancias RDS e imágenes en ECR).
