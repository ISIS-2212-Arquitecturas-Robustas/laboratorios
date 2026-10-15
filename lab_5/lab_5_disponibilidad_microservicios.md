# Lab 5 — Disponibilidad en Microservicios: experimentos de caos con Circuit Breaker, Retry, Rate Limiting, Outbox e Idempotencia

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
| 1. Contexto y diseño de los experimentos de caos | Modelado del escenario de fallo (un servicio del que dependen otros se degrada o se cae), escenarios de calidad (ASRs) y diseño de cada experimento: estado estable, hipótesis, fallo a inyectar, radio de impacto esperado y condición de aborto. | Uso acotado para comprender patrones de falla; las hipótesis y el criterio de negocio deben ser propios.   |
| 2. Arquitectura y tácticas                 | Análisis de las tácticas de disponibilidad del laboratorio: un contenedor auxiliar que intercepta las llamadas entre servicios (sidecar), graceful degradation en lugar de errores, corte de llamadas a un servicio caído (circuit breaker), recuperación automática de tareas y control de recursos. | Recomendado para comparar parámetros y riesgos de configuración.                                          |
| 3. Preparación de infraestructura con IaC  | Despliegue reproducible en AWS a partir de un archivo que describe toda la infraestructura (infraestructura como código, con CloudFormation) y verificación del despliegue. | Recomendado para asistir en comandos y troubleshooting de despliegue.                                     |
| 4. Configuración del sidecar de resiliencia | Configuración del sidecar (el proxy Envoy) en Ventas y reconocimiento de las herramientas para inyectar fallos.          | Recomendado para soporte de implementación, revisión de parámetros y pruebas; validar manualmente resultados. |
| 5. Ejecución de los experimentos de caos   | Inyección de fallos controlados con tráfico de estado estable, medición de detección y recuperación (TTD, TTR, MTTR) y comparación de cada táctica contra un grupo de control sin protecciones. | No recomendado para redactar conclusiones sin evidencia empírica del laboratorio.                         |
| 6. Consistencia bajo fallo: Outbox e Idempotencia | Demostración, dentro de los experimentos de caída, del problema de inconsistencia de datos y de su solución con dos patrones: Outbox (entrega garantizada de una operación pendiente) e idempotencia (una operación repetida no se aplica dos veces). | Recomendado para soporte de implementación; validar manualmente el experimento.                           |

## 3. Objetivos

- Entender que **no todo experimento de arquitectura es una prueba de carga**: para el atributo de disponibilidad, la variable que se manipula es el **fallo**, no la carga.
- Diseñar y ejecutar **experimentos de ingeniería del caos**: definir el estado estable del sistema, formular una hipótesis, inyectar un fallo controlado, limitar su radio de impacto y observar si el sistema se desvía y cómo se recupera.
- Medir los **tiempos de detección y de recuperación** (TTD, TTR y MTTR) de cada mecanismo de resiliencia: circuit breaker, reemplazo automático de tareas de ECS y reconciliación del Outbox.
- Implementar tres tácticas de resiliencia a nivel de infraestructura: reintentos con espera creciente entre intentos (*retry* con *backoff* exponencial), corte de llamadas a un servicio caído con *graceful degradation* (*circuit breaker*) y límite de peticiones por segundo (*rate limiting*).
- Desplegar la infraestructura del laboratorio usando Infraestructura como Código (describir la infraestructura en un archivo, en lugar de crearla a mano) con AWS CloudFormation.
- Demostrar que la resiliencia de infraestructura (circuit breaker, retry) no garantiza consistencia de datos, y verificar que los patrones **Outbox** e **Idempotencia** cierran esa brecha.
- Descubrir, con evidencia, los puntos de fallo que ninguna de estas tácticas cubre (el propio sidecar y la base de datos compartida), y reflexionar sobre las limitaciones de las tácticas locales frente a enfoques de resiliencia distribuida centralizada.

## 4. Planeación del laboratorio

En el Lab 4 usted desplegó Cheapest como tres microservicios (Logística, Inventario y Ventas) y midió su escalabilidad con pruebas de carga: la pregunta era *¿cuánta carga aguanta?*. En este laboratorio la pregunta es otra: **¿qué pasa cuando algo falla?** Los servicios fallan aunque la carga sea baja: una tarea se reinicia, una dependencia se pone lenta, la base de datos se reinicia por mantenimiento. Para estudiar eso no sirve subir la carga; hay que **provocar el fallo de forma controlada** y observar al sistema mientras lo sufre.

Para eso se introduce explícitamente una dependencia HTTP entre servicios: **Ventas llama a Inventario** para verificar que hay stock antes de registrar una venta. Esta dependencia es el punto de fallo que se va a explorar: **si Inventario se degrada, sin protecciones Ventas también falla.**

**Contexto de negocio.**

Los lunes por la mañana, los tenderos de Cheapest realizan sus reabastecimientos semanales. En estos picos, el servicio de **Inventario**, que valida disponibilidad de stock antes de confirmar un pedido, recibe una carga muy superior a la normal y se degrada. Sin protecciones, el servicio de **Ventas** (que depende de Inventario) empieza a fallar en cadena: los tenderos no pueden confirmar pedidos, las apps móviles reintentan automáticamente, y ese volumen de reintentos amplifica la carga sobre un servicio ya degradado. El resultado: un sistema que se colapsa a sí mismo.

Este escenario es conocido en la industria como **retry storm** y es uno de los patrones de fallo descritos en el artículo [Failure Mitigation for Microservices: An Intro to Aperture](https://careersatdoordash.com/blog/failure-mitigation-for-microservices-an-intro-to-aperture/) de DoorDash. En este laboratorio la tormenta se reproduce a propósito en el experimento E6: se combina un Inventario lento con un grupo de apps cliente que reintentan sin backoff, y se mide si las tácticas logran apagarla.

El equipo de Cheapest no quiere esperar al próximo lunes para saber si sus tácticas funcionan. Va a hacer lo que hacen los equipos que operan sistemas en producción: un ***game day***, una sesión planeada en la que se le inyectan fallos al sistema a propósito, con tráfico bajo y controlado, para comprobar que se comporta como se diseñó **antes** de que el fallo ocurra de verdad. Esa práctica se llama **ingeniería del caos** (*chaos engineering*), y la popularizó Netflix con Chaos Monkey, una herramienta que apagaba al azar servidores de producción para obligar a los equipos a diseñar servicios que toleraran esas caídas.

> [!IMPORTANT]
> **Pregunta 1:**
> En Cheapest, ¿qué decisión de producto y operación debería tomarse primero cuando aparece un retry storm: proteger disponibilidad percibida (graceful degradation) o proteger consistencia estricta (rechazar operaciones)?
> Argumente su respuesta considerando impacto en tenderos, riesgo financiero y costo de reconciliación posterior.

Un aspecto crítico de este escenario es que el fallo suele ser **transitorio**: un servicio degradado por un pico de memoria, un pool de conexiones agotado o un spike de CPU puede recuperarse por sí solo en segundos o minutos, y los orquestadores como ECS reemplazan automáticamente las tareas que dejan de responder. Por eso en este laboratorio los fallos de Inventario se inyectan con una **duración**: al cumplirse, el fallo se retira solo. Esto hace que el estado **HALF-OPEN** del circuit breaker no sea solo teórico: cuando Inventario se recupera, el circuit breaker lo detecta y vuelve al estado CLOSED, restaurando el flujo normal sin intervención humana. Medir **cuánto tarda** cada mecanismo en detectar el fallo y en volver a la normalidad es una de las metas del laboratorio.

**Conceptos que se presentan en este laboratorio.** Cada uno se explica con más detalle, y con su aplicación en Cheapest, en la parte de tácticas y patrones y en el diseño del experimento.

| Concepto | Qué es |
| --- | --- |
| Ingeniería del caos (*chaos engineering*) | Disciplina que consiste en experimentar sobre un sistema inyectándole fallos controlados para ganar confianza en su capacidad de soportar condiciones adversas. Un experimento de caos compara el comportamiento del sistema con y sin el fallo. |
| *Game day* | Sesión planeada en la que un equipo ejecuta experimentos de caos sobre su sistema y observa la respuesta. Este laboratorio es un *game day* de Cheapest. |
| Estado estable (*steady state*) | Comportamiento normal y medible del sistema, expresado con una métrica de negocio (aquí, la disponibilidad percibida y la latencia de las ventas con tráfico bajo y constante). La hipótesis de un experimento de caos dice si ese estado se mantiene cuando se inyecta el fallo. |
| Inyección de fallos | Provocar a propósito un fallo concreto (latencia, errores, caída de un proceso) en un punto definido del sistema, durante un tiempo definido. |
| Radio de impacto (*blast radius*) | Qué partes del sistema (servicios, endpoints, usuarios) resultan afectadas por un fallo. Se predice antes del experimento y se mide durante. |
| Condición de aborto | Criterio, definido antes de empezar, que obliga a detener el experimento y revertir el fallo (por ejemplo, "si la disponibilidad de las ventas cae por debajo de X durante más de Y segundos"). En producción es lo que impide que un experimento se convierta en un incidente. |
| Grupo de control | Configuración contra la que se compara un experimento. Aquí, el sistema sin sidecar: sin reintentos ni circuit breaker. |
| TTD (*time to detect*) | Tiempo entre la inyección del fallo y el momento en que un mecanismo lo detecta (por ejemplo, el circuito se abre o el balanceador marca el destino como no sano). |
| TTR y MTTR (*time to recover* / *mean time to recover*) | Tiempo entre el retiro (o la ocurrencia) del fallo y la vuelta al estado estable. El MTTR es el promedio de varios TTR. |
| Fallo en cascada (*cascading failure*) | Un servicio que falla hace fallar a los servicios que dependen de él, y estos a los que dependen de ellos. |
| Timeout | Tiempo máximo que un servicio espera la respuesta de otro antes de darla por fallida. |
| Reintento (*retry*) | Volver a enviar automáticamente una petición que falló. |
| *Retry storm* | Avalancha de reintentos: muchos clientes reintentan al mismo tiempo contra un servicio que ya está degradado y terminan de tumbarlo. |
| *Backoff* exponencial | Esperar cada vez más entre un reintento y el siguiente (por ejemplo 0,1 s, 0,2 s, 0,4 s...). |
| *Jitter* | Variación aleatoria que se le suma a esa espera para que los clientes no reintenten todos en el mismo instante. |
| *Circuit breaker* | Mecanismo que, al detectar que un servicio falla repetidamente, deja de enviarle peticiones por un tiempo y responde de inmediato con un error. Tiene tres estados: CLOSED (el tráfico pasa), OPEN (el tráfico se corta) y HALF-OPEN (deja pasar una petición de prueba para ver si el servicio se recuperó). |
| *Graceful degradation* | Cuando una dependencia no está disponible, responder algo útil aunque incompleto en lugar de un error. La respuesta alternativa se llama *fallback*. |
| *Rate limiting* (o *throttling*) | Limitar cuántas peticiones por segundo se aceptan. Las que exceden el límite se rechazan con el código HTTP 429 (*Too Many Requests*). |
| Proxy | Programa intermediario por el que pasan las peticiones entre dos servicios, y que puede aplicarles reglas (reintentar, cortar, registrar). |
| Sidecar | Contenedor auxiliar que se despliega junto al contenedor de un servicio, dentro de la misma tarea de ECS, y que se encarga de asuntos transversales (aquí, la resiliencia de las llamadas a Inventario) sin tocar el código del servicio. |
| Envoy | El proxy de código abierto que se usa como sidecar en este laboratorio. A su implementación del circuit breaker la llama *outlier detection*. |
| Health check | Petición periódica que el balanceador (ALB) le hace a cada tarea (`GET /health`) para decidir si le sigue enviando tráfico. ECS reemplaza las tareas que se detienen o que el balanceador marca como no sanas. |
| Infraestructura como Código (IaC) | Describir la infraestructura en un archivo de texto que se puede versionar y ejecutar, en lugar de crearla a mano en la consola. |
| CloudFormation | El servicio de AWS para infraestructura como código. El archivo que describe los recursos se llama **template** y el conjunto de recursos que crea a partir de él se llama **stack**. |
| Outbox | Patrón en el que una operación que hay que enviarle a otro servicio se guarda primero en una tabla local, en la misma transacción que el dato de negocio, y un proceso aparte la envía después hasta que logra entregarla. |
| Idempotencia | Propiedad de una operación que produce el mismo resultado aunque se ejecute varias veces. Se logra con una **clave de idempotencia**: un identificador que le permite al receptor reconocer una operación que ya procesó. |

> [!NOTE]
> **Nombres:** En el código se usan los nombres de las entidades (`OutboxHttpCall`, `ProcessedCall`) y en SQL los de las tablas (`outbox_http_calls`, `processed_calls`, `items_inventario`). Las columnas están en *camelCase* y en SQL van entre comillas dobles (`"createdAt"`).

### 4.1 Hipótesis de diseño

En este laboratorio **usted escribe las hipótesis**. Cada experimento del catálogo (sección 4.4.2) tiene la suya, y la debe redactar en su ficha **antes** de ejecutarlo, sin mirar los resultados. Una hipótesis de caos afirma qué le pasa al **estado estable** cuando se inyecta un fallo, y por qué:

> **Si** inyectamos *[fallo concreto, dónde y por cuánto tiempo]* con *[configuración de tácticas]*, **entonces** *[métrica del estado estable]* *[se mantiene / se degrada a lo sumo hasta …]* y vuelve al estado estable en *[TTR esperado]*, **porque** *[mecanismo de la táctica que lo explica]*.

Ejemplo de **forma** (sobre un sistema distinto al del laboratorio): *"Si apagamos una de las dos réplicas del servicio de pagos durante 2 minutos, entonces la tasa de pagos exitosos se mantiene por encima del 99 % y la latencia p99 sube a lo sumo a 800 ms, porque el balanceador deja de enviar tráfico a la réplica caída tras dos health checks fallidos."*

Una hipótesis refutada **no** es un mal resultado: es exactamente lo que un experimento de caos busca descubrir antes que los usuarios. Se califica el rigor del diseño y la honestidad del análisis, no que la hipótesis se cumpla.

### 4.2 Escenarios de calidad vinculados

Todas las medidas se toman con el tráfico de estado estable de la sección 6.2 (un generador de tráfico que envía 2 ventas por segundo), **no** con una prueba de carga. Una respuesta **útil** es una respuesta 2xx (incluidas las 201 con `pending_stock_confirmation`) que llega en menos de 3 s; la **disponibilidad percibida** de una ventana de 10 s es el porcentaje de respuestas útiles en esa ventana.

| ID    | Estímulo | Fuente del estímulo | Entorno | Artefacto | Respuesta | Medida de respuesta |
| ----- | -------- | ------------------- | ------- | --------- | --------- | ------------------- |
| ASR-1 | Inventario responde muy lento o con errores en la consulta de disponibilidad. | Servicio de Inventario, del cual depende Ventas. | Operación normal con tráfico de estado estable. | Servicio de Ventas (endpoint `POST /ventas/ventas`). | Ventas registra el pedido con graceful degradation en lugar de propagar la lentitud o el error, y vuelve a la operación normal cuando Inventario se recupera. | Pasados los primeros 30 s desde la inyección, la disponibilidad percibida de `POST /ventas/ventas` es ≥ 99 % en **cada** ventana de 10 s, con p99 < 3000 ms. El circuito vuelve a CLOSED (ventas confirmadas sin `pending`) a más tardar 60 s después de que el fallo se retira. |
| ASR-2 | Los reintentos automáticos se activan ante las fallas de Inventario. | Política de retry del sidecar Envoy ante errores 5xx de Inventario. | Inventario degradado, reintentos activos. | Servicio de Inventario. | Los reintentos no deben amplificar desproporcionadamente la carga recibida por Inventario. | El factor de amplificación (llamadas de disponibilidad que recibe Inventario por cada venta enviada, frente al grupo de control) es ≤ 2. La fórmula está en la sección 4.4.5. |
| ASR-3 | Mientras Inventario está lento, 50 apps cliente reintentan de inmediato, sin backoff, cada pedido que no responde en 3 s (*retry storm*). | Una versión de la app de tenderos con un bug en su política de reintentos. | Inventario degradado, con tráfico de estado estable de los demás tenderos. | API Gateway, sidecar de Ventas y servicio de Ventas (`POST /ventas/ventas`). | La tormenta no se sostiene: las tácticas cortan el ciclo de reintentos y los demás tenderos siguen confirmando pedidos. | Pasados los primeros 30 s de la tormenta, las apps defectuosas necesitan en promedio ≤ 2 intentos por pedido, y la disponibilidad percibida de las ventas del generador de tráfico cumple la medida del ASR-1. |
| ASR-4 | Inventario se cae por completo y luego vuelve, después de que se registraron ventas con graceful degradation. | Caída y reemplazo de la tarea de Inventario. | Transición de graceful degradation a operación normal. | Mecanismo de Outbox (Ventas) + endpoint de idempotencia (Inventario). | Toda venta registrada con graceful degradation entrega su decremento de stock exactamente una vez, aunque Ventas se reinicie mientras hay entregas pendientes. | Contadas desde que Inventario vuelve a responder `/health` (T_rec), todas las filas de `outbox_http_calls` en PENDING pasan a DELIVERED en < 30 s; ningún `items_inventario.cantidad` refleja decrementos duplicados, y las filas PENDING sobreviven a un reinicio de la tarea de Ventas. |
| ASR-5 | La tarea de Inventario se detiene abruptamente. | Fallo del proceso o de la máquina que lo ejecuta. | Operación normal con tráfico de estado estable. | Servicio ECS de Inventario, su balanceador y el servicio de Ventas. | ECS reemplaza la tarea sin intervención humana y, mientras tanto, Ventas sigue confirmando pedidos con graceful degradation. | MTTR ≤ 5 min, medido desde que la tarea se detiene hasta que `GET /inventario/health` vuelve a responder 200 y el target está `healthy`. Durante ese tiempo, la disponibilidad percibida de `POST /ventas/ventas` cumple la medida del ASR-1. |

Contexto de negocio de cada ASR (motivación, no parte de la especificación formal):

- **ASR-1**: Como tendero, quiero poder confirmar un pedido incluso cuando el servicio de Inventario esté degradado. Un pedido con stock no confirmado es preferible a un error, o a una app que se queda pensando 10 segundos.
- **ASR-2**: Como negocio, quiero que los reintentos automáticos ante fallos no amplifiquen la carga sobre servicios ya degradados, para evitar empeorar el incidente.
- **ASR-3**: Como negocio, quiero que un bug en la política de reintentos de una versión de la app no convierta una degradación de Inventario en una caída total, ni le quite capacidad a la confirmación de pedidos de los demás tenderos.
- **ASR-4**: Como negocio, quiero que toda venta registrada, incluso con graceful degradation (`pending_stock_confirmation`), tenga su decremento de stock entregado exactamente una vez cuando Inventario se recupere.
- **ASR-5**: Como negocio, quiero que la caída de una tarea se resuelva sola en minutos, sin que alguien de guardia tenga que intervenir un lunes a las 7 a. m.

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

**El sidecar también es un componente que puede fallar.** Al agregarlo, la tarea de Ventas pasa a tener dos contenedores, y en el template ambos están marcados como esenciales (`Essential: true`). Qué le pasa a Ventas cuando el sidecar se cae es una de las preguntas que responde el experimento E4.

**Relación entre sidecar y graceful degradation**

El sidecar maneja la red (retry, circuit breaker). La graceful degradation —retornar `status: pending_stock_confirmation` en lugar de propagar el error— es una decisión de negocio que vive en el código de Ventas. El sidecar le comunica al servicio que Inventario está caído (mediante un 503 rápido en lugar de un timeout lento), y el servicio decide qué respuesta dar al cliente.

##### Circuit Breaker

Un **circuit breaker** es un control de fallos que corta el tráfico hacia un servicio cuando detecta errores persistentes. Evita que un servicio degradado reciba más carga y permite al cliente responder rápido con una salida controlada.

**Estados básicos**

- **CLOSED**: el circuito está cerrado y el tráfico fluye normalmente.
- **OPEN**: el circuito está abierto, el tráfico se corta inmediatamente y se devuelve un error o se aplica graceful degradation.
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

El circuit breaker y la graceful degradation mantienen a Ventas disponible, pero dejan un problema de datos: la venta quedó registrada y el stock de Inventario nunca se descontó. Dos patrones cierran esa brecha:

- **Outbox:** en la misma transacción en la que Ventas guarda la venta, guarda también una fila en una tabla local (`outbox_http_calls`, entidad `OutboxHttpCall`) que representa "hay que descontar este stock en Inventario". Un proceso en segundo plano lee esa tabla cada 2 segundos y envía la petición a Inventario hasta que logra entregarla. La garantía es de entrega **al menos una vez** (*at-least-once*).
- **Idempotencia:** como "al menos una vez" significa que la misma petición puede llegar repetida, Inventario recibe con cada petición una clave de idempotencia y guarda las claves que ya procesó. Si llega una clave repetida, no vuelve a descontar.

Juntos logran que cada venta descuente el stock exactamente una vez. Verá ambos patrones en detalle, sobre el código, en el experimento E3.

#### 4.3.2 Tácticas de arquitectura

| Táctica                                     | Análisis                                                                                                                                                                                                                                                         |
| ------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Reintentos con backoff exponencial + jitter | Favorece la recuperación automática ante fallos transitorios.<br>Sin backoff ni jitter, los reintentos sincronizados pueden amplificar la carga (thundering herd), agravando el incidente en lugar de resolverlo.                                                |
| Circuit Breaker (CLOSED / OPEN / HALF-OPEN) | Favorece disponibilidad del servicio cliente al dejar de enviar requests a un servicio que ya está fallando.<br>Desfavorece consistencia inmediata: el estado OPEN implica que algunas operaciones retornan una respuesta de graceful degradation en lugar de resultados reales. |
| Graceful degradation (fallback)             | Favorece experiencia de usuario y disponibilidad percibida: el sistema sigue aceptando pedidos con graceful degradation.<br>Introduce complejidad en la lógica de negocio para manejar el estado `pending_stock_confirmation`.                                          |
| Detección y recuperación automática (health checks + reemplazo de tareas de ECS) | Favorece la recuperación sin intervención humana: el balanceador deja de enviar tráfico a una tarea que no responde `/health` y ECS lanza una tarea nueva.<br>El tiempo de recuperación depende de la frecuencia de los health checks, del tiempo de arranque de la tarea y de cuántas réplicas hay; un `/health` que no revisa las dependencias (por ejemplo, la base de datos) puede reportar sana una tarea que no sirve. |
| Rate Limiting (API Gateway throttling)      | Favorece protección de servicios backend ante picos de tráfico y retry storms.<br>Puede afectar a usuarios legítimos si los límites no están bien calibrados o si no distinguen entre clientes o tipos de tráfico.                                                             |
| Proxy sidecar (Envoy)                   | Permite implementar retry y circuit breaker en la capa de red, sin tocar el código de negocio.<br>El sidecar intercepta el tráfico saliente de Ventas hacia Inventario y aplica las políticas configuradas en su archivo YAML.<br>Introduce un salto de red adicional, un componente más que puede fallar, y requiere que los parámetros del sidecar sean coherentes con los timeouts de la aplicación. |

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

- Mejora disponibilidad cuando el fallo es breve o intermitente.
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
> Proponga un conjunto coherente de parámetros iniciales para Cheapest (timeouts, retries, umbral de apertura, reset timeout, rate y burst) y justifique cómo evitaría inestabilidad sistémica. Incluya un escenario concreto en el que usar reintentos y circuit breaker juntos sin coordinación generaría un problema.

#### 4.3.3 Estilos aplicados

| Estilo | Análisis |
| --- | --- |
| Microservicios | Favorece aislamiento de fallos por servicio y despliegue independiente.<br>Sin tácticas de resiliencia, la comunicación HTTP entre servicios introduce puntos de fallo en cadena. Los servicios que comparten una misma base de datos no están aislados frente a la caída de esa base. |
| API Gateway | Actúa como punto de control centralizado para rate limiting y throttling.<br>Protege los servicios upstream de picos de tráfico que superan su capacidad. |
| Graceful degradation | Favorece continuidad operativa durante incidentes: el sistema entrega respuestas útiles aunque parciales en lugar de fallar completamente.<br>Requiere acuerdos de negocio claros sobre qué funcionalidades pueden degradarse sin romper la experiencia crítica del tendero. |
| Control de recursos (Resource Control) | Favorece estabilidad bajo carga al limitar concurrencia, throughput y consumo por cliente/ruta (throttling, cuotas, aislamiento).<br>Sin una buena calibración, puede rechazar tráfico legítimo y afectar temporalmente la percepción de disponibilidad. |
| Sidecar | Externaliza responsabilidades transversales (resiliencia, observabilidad, seguridad) a un proceso proxy que corre junto al servicio principal.<br>Permite aplicar y cambiar políticas de resiliencia sin modificar el código de negocio ni redesplegar la aplicación. |

### 4.4 Diseño del experimento

#### 4.4.1 ¿Por qué no es una prueba de carga?

En los laboratorios anteriores el experimento consistía en subir la carga y observar en qué punto el sistema dejaba de cumplir su ASR: la **variable independiente era la carga**. Para la disponibilidad, esa estrategia tiene dos problemas. Primero, los fallos que más afectan la disponibilidad (una tarea que se cae, una dependencia que se pone lenta, una base de datos que se reinicia) **no dependen de la carga**: ocurren igual a las 3 a. m. con un tendero conectado. Segundo, una prueba de carga mezcla dos causas: si el sistema falla, no se sabe si fue por el fallo o por la saturación.

Por eso en este laboratorio:

| | Prueba de carga (Labs 2-4) | Experimento de caos (este laboratorio) |
| --- | --- | --- |
| Variable que se manipula | Número de usuarios o peticiones por segundo | El fallo: qué componente falla, cómo y por cuánto tiempo |
| Carga | Creciente, hasta saturar | **Baja y constante** (2 ventas/s), igual en todos los experimentos. En E6 se agrega tráfico, pero es el fallo inyectado (apps que reintentan mal), no una carga creciente |
| Pregunta | ¿Cuánta carga aguanta? | ¿Se mantiene el estado estable cuando algo falla? ¿Cuánto tarda en detectarlo y en recuperarse? |
| Métricas principales | Throughput, p95/p99 por nivel de carga | Disponibilidad percibida en el tiempo, TTD, TTR, radio de impacto, consistencia de los datos |
| Resultado típico | Una curva carga vs. latencia | Una **línea de tiempo** con el momento de la inyección, la desviación y la recuperación |

Un experimento de caos sigue cuatro pasos:

1. **Definir el estado estable** con una métrica de negocio medible (aquí, disponibilidad percibida y p99 de las ventas del generador de tráfico).
2. **Formular la hipótesis** de que el estado estable se mantiene (o se degrada de forma acotada) en el grupo experimental, frente al grupo de control.
3. **Inyectar el fallo** de forma controlada: un solo fallo a la vez (salvo cuando el escenario es justamente la combinación de dos, como en E6), con duración definida y con una condición de aborto.
4. **Comparar** el estado estable antes, durante y después del fallo, y entre configuraciones. Lo que se busca es la diferencia.

#### 4.4.2 Catálogo de experimentos

El catálogo define **qué fallo** se inyecta en cada experimento y **qué configuraciones** se comparan. Cómo inyectar cada fallo está en la sección 6. El resto del diseño (hipótesis, radio de impacto esperado, condición de aborto, duración, qué métricas confirman o refutan la hipótesis) lo define usted en la ficha de cada experimento.

| # | Fallo inyectado | Cómo se inyecta | Configuraciones a comparar | ASR |
| --- | --- | --- | --- | --- |
| E0 | Ninguno: medición del estado estable | — | Sidecar completo | Define el estado estable de los demás experimentos |
| E1 | Inventario lento: cada consulta de disponibilidad tarda 5 s | Endpoint de caos de Inventario (`mode: latency`) | Sin sidecar (control) · solo reintentos · reintentos + circuit breaker | ASR-1, ASR-2 |
| E2 | Inventario con errores: 500 intermitentes (30 % de las consultas) y luego totales (100 %) | Endpoint de caos de Inventario (`mode: error`) | Sin sidecar (control) · solo reintentos · reintentos + circuit breaker | ASR-1, ASR-2 |
| E3 | Caída de la tarea de Inventario | `aws ecs stop-task` | Sidecar completo | ASR-4, ASR-5 |
| E4 | Caída del sidecar de Ventas, y caída de la tarea de Ventas con entregas del Outbox pendientes | Endpoint de caos de Ventas (apaga Envoy) y `aws ecs stop-task` | Sidecar completo | Exploratorio (sin ASR): ¿qué tan grave es el sidecar como punto de fallo? ASR-4 (persistencia del Outbox) |
| E5 | Reinicio de la base de datos RDS que comparten los tres servicios | `aws rds reboot-db-instance` | Sidecar completo | Exploratorio (sin ASR): radio de impacto de un punto único de fallo |
| E6 | *Retry storm*: Inventario lento + 50 apps cliente que reintentan sin backoff | Endpoint de caos (`mode: latency`) + `recursos/tormenta_reintentos.sh` | Sin sidecar (control) · sin sidecar con throttling del stage · completa · (opcional) sin sidecar con clientes con backoff | ASR-3 |

En los experimentos **exploratorios** no hay un ASR que cumplir: el objetivo es descubrir el comportamiento del sistema. Igual debe escribir una hipótesis (qué cree que va a pasar y por qué) antes de ejecutarlos.

> [!IMPORTANT]
> **Pregunta 2:**
> Si usted fuera el líder encargado de llevar estas tácticas a producción en Cheapest, ¿las adoptaría en el mismo orden en que se presentan (reintentos, circuit breaker, rate limiting, Outbox e idempotencia), teniendo en cuenta el riesgo de cada cambio? Describa un plan de migración que mitigue los riesgos asociados.
> El plan de migración debe incluir: etapas, tiempo estimado por etapa y las tareas a realizar en cada una.

#### 4.4.3 Ficha de cada experimento

Antes de ejecutar cada experimento, complete su ficha. Las fichas se entregan en el informe (sección 7.1) y se califican: un experimento sin ficha previa no es un experimento, es una prueba al azar.

| Campo | Qué debe contener |
| --- | --- |
| Experimento y configuración | Número del catálogo y configuración de tácticas (revisión de la task definition de Ventas e imagen del sidecar). |
| Estado estable | Métricas y valores que considera "normales", tomados de su E0 (disponibilidad percibida, p99, % de `pending`). |
| Hipótesis | En el formato de la sección 4.1. |
| Fallo inyectado | Qué, dónde, con qué parámetros (por ejemplo `delayMs`, `errorRate`, `durationMs`) y durante cuánto tiempo. |
| Radio de impacto esperado | Qué endpoints, servicios o datos espera que se afecten, y cuáles no. |
| Condición de aborto | Cuándo detendría el experimento y revertiría el fallo antes de tiempo. |
| Métricas y fuente | Qué va a medir para confirmar o refutar la hipótesis, y de dónde sale cada dato (generador de tráfico, endpoint de caos, logs del sidecar, CloudWatch, eventos de ECS). |
| Reversión | Cómo devuelve el sistema al estado inicial al terminar. |

#### 4.4.4 ¿Qué componentes se van a diseñar o modificar?

| Componente | Cambio |
| --- | --- |
| Inventario | Endpoint de inyección de fallos en caliente (`/inventory/chaos`: latencia o errores, con duración) sobre la consulta de disponibilidad, y endpoint que recibe los descuentos de stock con clave de idempotencia. |
| Ventas | Graceful degradation (`pending_stock_confirmation`) cuando Inventario no está disponible, escritura transaccional de la venta junto con su fila de Outbox, endpoint de observación del Outbox (`/ventas/outbox/resumen`) y endpoint para apagar el sidecar (`/ventas/chaos/sidecar`). |
| Sidecar Envoy (en la tarea de Ventas) | Configuración del timeout, de los reintentos con backoff y jitter, y del circuit breaker (los seis `???` que usted completa). |
| API Gateway | Rate limiting sobre el stage `lab`. |

#### 4.4.5 ¿Qué métricas se van a medir?

| Métrica | Definición | ASR | Dónde se mide |
| --- | --- | --- | --- |
| Disponibilidad percibida | Respuestas útiles (2xx en < 3 s, incluidas las `pending`) ÷ total, por ventana de 10 s | ASR-1, ASR-3, ASR-5 | CSV del generador de tráfico, resumido con `ventanas.py` (sección 6.2) |
| p99 del generador de tráfico | Percentil 99 de la latencia de las ventas, por ventana de 10 s | ASR-1 | CSV del generador de tráfico |
| % de `pending` | Ventas registradas con graceful degradation ÷ total, por ventana | ASR-1 (y consistencia) | CSV del generador de tráfico |
| TTD | Desde la inyección (T_inj) hasta que el mecanismo detecta el fallo: primera respuesta `503 UH` del sidecar (circuito OPEN) o primer `UnHealthyHostCount` > 0 del balanceador | ASR-1, ASR-5 | Logs del sidecar, CloudWatch |
| TTR | Desde el retiro del fallo (T_rem) o la caída hasta la vuelta al estado estable (primera ventana sin `pending` y con la disponibilidad de E0) | ASR-1, ASR-5 | CSV del generador de tráfico, eventos de ECS |
| Radio de impacto | Qué endpoints del generador de tráfico se desviaron del estado estable | Todos | CSV del generador de tráfico (endpoints `venta`, `inventario_item`, `catalogo`, `logistica_health`) |
| Factor de amplificación | Fórmula abajo | ASR-2 | Contador `llamadasDisponibilidad` del endpoint de caos y CSV del generador de tráfico |
| Reconciliación del Outbox | Desde T_rec hasta que no quedan filas PENDING; decrementos duplicados | ASR-4 | `GET /ventas/outbox/resumen`, `GET /inventario/items/{id}` |
| Intentos por pedido | Peticiones enviadas por las apps defectuosas ÷ pedidos lógicos, durante la tormenta | ASR-3 | CSV y resumen de `tormenta_reintentos.sh` |
| Pedidos duplicados | Ventas registradas que nadie recibió: Δ filas totales del Outbox − (pedidos completados por la tormenta + ventas 201 del generador de tráfico) | ASR-3 (consistencia) | `GET /ventas/outbox/resumen` antes y después, CSV de los dos scripts |
| Respuestas 429 | Porcentaje de las peticiones de la tormenta y del generador de tráfico rechazado por API Gateway | ASR-3 | CSV de los dos scripts |

**Cómo calcular el factor de amplificación (ASR-2).** El endpoint de caos de Inventario cuenta cuántas consultas de disponibilidad le llegan, reintentos incluidos (campo `llamadasDisponibilidad` de `GET {BASE_URL}/inventario/chaos`). Léalo justo antes de inyectar el fallo y justo después de retirarlo; la diferencia son las llamadas que recibió Inventario durante el fallo. Divídala por el número de ventas que el generador de tráfico envió en ese mismo intervalo:

$$\text{llamadas por venta} = \frac{\Delta\,\text{llamadasDisponibilidad}}{\text{ventas enviadas por el generador de tráfico entre las dos lecturas}}$$

$$\text{factor} = \frac{\text{llamadas por venta con la configuración evaluada}}{\text{llamadas por venta en el grupo de control (sin sidecar)}}$$

Sin sidecar cada venta genera exactamente una consulta, así que el grupo de control da 1 llamada por venta. Ejemplo: si con reintentos el contador subió 470 mientras el generador de tráfico envió 240 ventas, hay 1,96 llamadas por venta y el factor es 1,96, que cumple el ASR-2. Como cota teórica, cada venta genera como máximo `1 + num_retries` consultas; el circuit breaker, en cambio, **reduce** el factor, porque con el circuito OPEN las consultas no llegan a Inventario.

### 4.5 Planeación del experimento

#### 4.5.1 Recursos requeridos

| Recurso | Detalle |
| --- | --- |
| Infraestructura AWS | Stack de CloudFormation (API Gateway, ECS/Fargate, RDS, balanceadores y sidecar Envoy) desplegado en su cuenta, más los repositorios de ECR con las imágenes |
| Herramientas locales | Docker, AWS CLI, `curl`, Python 3, un cliente de PostgreSQL y el backend de la rama `availability` |
| Herramientas del laboratorio | `recursos/generador_trafico.sh` (tráfico de estado estable), `recursos/ventanas.py` (resumen por ventanas de tiempo) y `recursos/tormenta_reintentos.sh` (apps cliente con reintentos defectuosos, E6) |
| Datos de prueba | Script de seed de la rama `availability` (`npm run db:seed`) |
| Créditos AWS | Elimine el stack al terminar |

> [!NOTE]
> No se espera que llegue con experiencia previa en todas estas tecnologías. La columna **Recurso para entender qué hace** apunta a documentación oficial u otra referencia introductoria; revísela antes de tocar el template o el sidecar. Adicionalmente, se recomienda usar un asistente de IA (Claude, ChatGPT, etc.) para explorar cada servicio de AWS: pregúntele qué problema resuelve, qué recursos crea "por debajo" y qué pasaría si no existiera esa pieza en la arquitectura. Esto ayuda a construir intuición más allá de copiar comandos.

| Categoría                          | Tecnologías                                | Recurso para entender qué hace                                                                                     |
| ----------------------------------- | -------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| Ingeniería del caos                 | Principios de chaos engineering               | [Principles of Chaos Engineering](https://principlesofchaos.org/)                                                 |
| Infraestructura como Código        | AWS CloudFormation                            | [¿Qué es AWS CloudFormation?](https://docs.aws.amazon.com/es_es/AWSCloudFormation/latest/UserGuide/Welcome.html)     |
| Gateway de entrada + Rate Limiting | Amazon API Gateway (throttling por stage) | [¿Qué es Amazon API Gateway?](https://docs.aws.amazon.com/es_es/apigateway/latest/developerguide/welcome.html) · [Throttling en HTTP APIs](https://docs.aws.amazon.com/es_es/apigateway/latest/developerguide/http-api-throttling.html) |
| Orquestación de contenedores       | Amazon ECS (Fargate)                          | [¿Qué es Amazon ECS?](https://docs.aws.amazon.com/es_es/AmazonECS/latest/developerguide/Welcome.html) · [AWS Fargate](https://docs.aws.amazon.com/es_es/AmazonECS/latest/userguide/what-is-fargate.html) |
| Registro de imágenes               | Amazon ECR                                    | [¿Qué es Amazon ECR?](https://docs.aws.amazon.com/es_es/AmazonECR/latest/userguide/what-is-ecr.html)                 |
| Base de datos relacional           | Amazon RDS (PostgreSQL)                       | [¿Qué es Amazon RDS?](https://docs.aws.amazon.com/es_es/AmazonRDS/latest/UserGuide/Welcome.html)                     |
| Observabilidad                     | Amazon CloudWatch                             | [¿Qué es Amazon CloudWatch?](https://docs.aws.amazon.com/es_es/AmazonCloudWatch/latest/monitoring/WhatIsCloudWatch.html) |
| Framework backend                  | NestJS                                        | [Documentación de NestJS](https://docs.nestjs.com/)                                                                   |
| Lenguaje                           | TypeScript                                    | [Handbook de TypeScript](https://www.typescriptlang.org/docs/handbook/intro.html)                                     |
| ORM                                | TypeORM                                       | [Documentación de TypeORM](https://typeorm.io/)                                                                       |
| Proxy sidecar                       | Envoy Proxy                                  | [¿Qué es Envoy?](https://www.envoyproxy.io/docs/envoy/latest/intro/what_is_envoy) · [Patrón Sidecar](https://learn.microsoft.com/es-es/azure/architecture/patterns/sidecar) |

> [!IMPORTANT]
> **Sugerencia de prompt para IA:** *"Actúo como estudiante de arquitectura de software. Explícame qué hace [servicio de AWS], qué problema arquitectónico resuelve, qué recursos concretos crea cuando lo despliego con CloudFormation, y qué riesgos de disponibilidad o costo debería tener en cuenta al usarlo en un sistema de microservicios como el de este laboratorio."* Use esto como punto de partida, no como respuesta final: valide lo que la IA le diga contra la documentación oficial y contra lo que observe en su propio despliegue.

#### 4.5.2 Elementos de arquitectura involucrados

Servicios de Ventas e Inventario (y Logística como parte del stack), sidecar Envoy, API Gateway, balanceadores con sus health checks, el servicio ECS que reemplaza tareas, la base de datos RDS compartida (tablas `outbox_http_calls` e `items_inventario`) y el generador de tráfico de estado estable. El conector que se estudia es la llamada HTTP de Ventas a Inventario.

![Diagrama de despliegue del laboratorio](./recursos/diagrama_componentes.png)

*Figura 1. Vista de despliegue del laboratorio: API Gateway enruta hacia los servicios de Logística, Inventario y Ventas corriendo en ECS/Fargate; el sidecar Envoy corre como segundo contenedor dentro de la misma tarea de Ventas e intercepta el tráfico hacia Inventario. En este laboratorio el generador de tráfico de estado estable corre en el computador del estudiante (y, en E6, también la tormenta de reintentos).*

> [!NOTE]
> Note que el sidecar se despliega como un contenedor adicional dentro de la misma tarea ECS que Ventas, y el tráfico entre Ventas e Inventario pasa a través del proxy Envoy. Esto permite implementar las tácticas de resiliencia sin modificar el código de negocio de Ventas, y ajustar los parámetros de retry y circuit breaker sin necesidad de redesplegar la aplicación.

#### 4.5.3 Esfuerzo estimado

Referencia para planear; puede variar según su experiencia con AWS. Buena parte del tiempo es espera: la creación del stack (la RDS sola tarda entre 10 y 15 minutos) y los despliegues de cada nueva revisión de ECS (2 a 5 minutos). Cada experimento dura entre 6 y 10 minutos, porque el fallo se inyecta y se retira en segundos con el endpoint de caos. **Ordene los experimentos para minimizar el número de revisiones de la task definition de Ventas**: hágalo parte de su planeación. Planee el laboratorio en al menos dos sesiones de trabajo.

| Etapa | Esfuerzo aprox. |
| --- | --- |
| Publicación de imágenes, despliegue del stack y carga de datos | 1,5 h |
| Configuración del sidecar y revisión del código | 0,5 h |
| Fichas de los siete experimentos (diseño) | 1 h |
| E0 a E2 (incluye las revisiones de Ventas sin sidecar y solo con reintentos) | 1,5 h |
| E3 a E5 (caídas, Outbox e idempotencia, reinicio de la RDS) | 1,25 h |
| E6 (tormenta de reintentos y throttling) | 0,5 h |
| Análisis y entregables | 1,75 h |
| **Total** | **8 h-persona** |

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
> Los prefijos de ruta de API Gateway en este laboratorio son **`logistica`/`inventario`**, a diferencia de `logistics`/`inventory` usados en el Lab 4. La lista completa de rutas está en la sección 5.5.

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

> [!IMPORTANT]
> **Complete el sidecar antes de publicarlo.** La imagen `cheapest-ventas-sidecar:1.0.0` debe construirse **después** de completar los seis `???` de `envoy.yaml.tmpl` y de verificarlo localmente (sección 5.8, "Completar la configuración de Envoy"). Si publica el sidecar con los `???`, Envoy no arranca, la tarea de Ventas nunca queda sana y el stack no llega a `CREATE_COMPLETE`. Las otras tres imágenes las puede publicar de una vez.

### 5.4 Desplegar el stack

```bash
aws cloudformation deploy  --template-file lab_5/recursos/cloudformation_template.yaml  --stack-name Cheapest-lab5  --parameter-overrides LogisticaImageUri=<URI_ECR_LOGISTICA>:2.0.0 InventarioImageUri=<URI_ECR_INVENTARIO>:2.0.0 VentasImageUri=<URI_ECR_VENTAS>:2.0.0  VentasSidecarImageUri=<URI_ECR_SIDECAR>:1.0.0 DBPassword=<SU_CONTRASEÑA>  --region us-east-1
```

Monitoree el progreso en la consola de AWS → CloudFormation → Stack `Cheapest-lab5` → pestaña **Events**.

El template ya configura todas las variables de entorno de las tareas: `INVENTARIO_BASE_URL=http://localhost:10000` e `INVENTARIO_TIMEOUT_MS=9000` en Ventas, `INVENTARIO_UPSTREAM_HOST` (el DNS del balanceador de Inventario, que el template obtiene solo) e `INVENTARIO_UPSTREAM_PORT=80` en el sidecar, `SIDECAR_ADMIN_URL=http://localhost:9901` y `OUTBOX_MAX_ATTEMPTS=600` también en Ventas, y `FAULT_DELAY_MS=0` en Inventario (arranca sano; los fallos se inyectan después, en caliente). No tiene que escribir ninguno de esos valores a mano.

> [!IMPORTANT]
> **Ejecute `aws cloudformation deploy` una sola vez.** Los cambios de configuración posteriores (quitar o poner el sidecar, cambiar la imagen del sidecar) se hacen **en la consola de ECS creando una nueva revisión de la task definition**, como se explica en la sección 6.1. Los fallos **no** se inyectan con revisiones: se inyectan en caliente con los endpoints de caos y con la AWS CLI (sección 5.8). Si vuelve a ejecutar `aws cloudformation deploy` con otros parámetros, CloudFormation puede devolver los servicios a las revisiones que él creó y perder sus cambios.

### 5.5 Verificar el despliegue

Una vez el stack esté en estado `CREATE_COMPLETE`:

```bash
# Obtener la URL del API Gateway
aws cloudformation describe-stacks --stack-name Cheapest-lab5 --query "Stacks[0].Outputs[?OutputKey=='ApiGatewayUrl'].OutputValue" --output text
```

El valor que retorna es la **`BASE_URL`** que se usa en el resto del laboratorio:

```bash
BASE_URL=https://<API_ID>.execute-api.us-east-1.amazonaws.com/lab
```

Todas las peticiones que haga desde su computador (`curl` y los scripts del laboratorio) contra AWS pasan por API Gateway y usan estas rutas:

| Para qué | Método y ruta completa |
| --- | --- |
| Salud de cada servicio | `GET {BASE_URL}/logistica/health`, `GET {BASE_URL}/inventario/health`, `GET {BASE_URL}/ventas/health` |
| **Crear una venta (endpoint bajo prueba)** | `POST {BASE_URL}/ventas/ventas` |
| Crear y listar productos externos (para armar el cuerpo de la venta) | `POST` y `GET {BASE_URL}/ventas/productos-externos` |
| Consultar un ítem de inventario y su `cantidad` | `GET {BASE_URL}/inventario/items/{itemInventarioId}` |
| Disponibilidad de un producto (la que consulta Ventas) | `GET {BASE_URL}/inventario/items/disponibilidad/{productoId}` |
| Reponer stock de un ítem | `PATCH {BASE_URL}/inventario/items/{itemInventarioId}` |
| Inyectar o retirar un fallo en Inventario, y leer el contador de llamadas | `POST` y `GET {BASE_URL}/inventario/chaos` |
| Estado del Outbox (conteo de filas por estado) | `GET {BASE_URL}/ventas/outbox/resumen` |
| Apagar el sidecar Envoy de Ventas | `POST {BASE_URL}/ventas/chaos/sidecar` |

> [!NOTE]
> El primer segmento de la ruta (`/ventas`, `/inventario`, `/logistica`) es el prefijo de API Gateway; el resto es la ruta del controlador. Por eso crear una venta es `/ventas/ventas`. API Gateway traduce `/inventario/...` a la ruta interna `/inventory/...` y `/logistica/...` a `/logistics/...`. Si usa los prefijos en inglés contra `BASE_URL` obtendrá 404. Las rutas en inglés (`/inventory/...`) solo se usan cuando se llama a un servicio **directamente**, sin API Gateway: dentro del código, en los logs y en el ambiente local con Docker Compose.

Desde su computador verifique que los tres servicios responden:

```bash
curl -i $BASE_URL/logistica/health
curl -i $BASE_URL/inventario/health
curl -i $BASE_URL/ventas/health
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

Con los datos sembrados, ya puede ejecutar las pruebas usando los IDs fijos de `seed.sql` (los mismos de los laboratorios anteriores: tienda `bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb`, producto `aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa`, moneda `cccccccc-cccc-4ccc-8ccc-cccccccccccc`). El ítem de inventario de ese producto en esa tienda es `11111111-1111-4111-8111-111111111111`.

El seed no crea productos externos (los productos que cada tienda vende por fuera del catálogo de Cheapest), y la venta necesita uno. Cree uno y anote el `id` que retorna:

```bash
curl -s -X POST $BASE_URL/ventas/productos-externos -H 'Content-Type: application/json' -d '{
  "tiendaId": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
  "codigoBarras": "7700000000001",
  "nombre": "Arroz 500 g",
  "categoria": "Granos",
  "precioBase": 25.5,
  "monedaId": "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
  "cantidad": 100
}'
```

Guarde el cuerpo de la venta en un archivo `venta.json`, que es el que usarán el generador de tráfico y los comandos `curl` del laboratorio:

```json
{
  "tiendaId": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
  "fechaHora": "2026-10-14T10:00:00Z",
  "monedaId": "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
  "items": [
    {
      "productoExternoId": "<ID_DE_UN_PRODUCTO_EXTERNO>",
      "productoId": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
      "cantidad": 1,
      "precioUnitario": 25.5
    }
  ]
}
```

Pruébelo una vez antes de seguir; debe responder HTTP 201:

```bash
curl -i -X POST $BASE_URL/ventas/ventas -H 'Content-Type: application/json' -d @venta.json
```

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

1. Las herramientas para inyectar fallos y observar el sistema (ya implementadas en el código base).
2. La **configuración del sidecar Envoy** en Ventas: aquí es donde usted define los parámetros de retry y circuit breaker.
3. Un ajuste mínimo en el servicio de Ventas para la graceful degradation.

#### Herramientas para inyectar fallos

Un experimento de caos necesita poder **encender y apagar un fallo en segundos**, sin redesplegar. El código base trae cuatro mecanismos; no es necesario modificarlos.

**1. Endpoint de caos de Inventario** (`apps/inventario/src/chaos.controller.ts` y `fault.middleware.ts`). El fallo afecta solo la consulta de disponibilidad que hace Ventas (`GET /inventory/items/disponibilidad/:productoId`); el resto de Inventario sigue sano, lo que acota el radio de impacto.

```bash
# Latencia: cada consulta de disponibilidad tarda delayMs; el fallo se retira solo a los durationMs
curl -s -X POST $BASE_URL/inventario/chaos -H 'Content-Type: application/json' \
  -d '{"mode": "latency", "delayMs": 5000, "durationMs": 180000}'

# Errores: una fracción errorRate de las consultas responde HTTP 500
curl -s -X POST $BASE_URL/inventario/chaos -H 'Content-Type: application/json' \
  -d '{"mode": "error", "errorRate": 0.3, "durationMs": 180000}'

# Retirar el fallo de inmediato (reversión o condición de aborto)
curl -s -X POST $BASE_URL/inventario/chaos -H 'Content-Type: application/json' -d '{"mode": "off"}'

# Estado actual: modo, si está activo, hasta cuándo, y el contador llamadasDisponibilidad
curl -s $BASE_URL/inventario/chaos
```

Si omite `durationMs`, el fallo queda activo hasta que lo apague. Las respuestas incluyen `injectedAt` y `until` en UTC: úselas como T_inj y T_rem. El contador `llamadasDisponibilidad` cuenta todas las consultas de disponibilidad que recibió la tarea desde que arrancó, reintentos incluidos (sección 4.4.5).

> [!NOTE]
> El estado del fallo vive en la memoria de la tarea de Inventario: si la tarea se reinicia, arranca sin fallo (con `FAULT_DELAY_MS=0`) y el contador vuelve a 0.

**2. Endpoint de caos de Ventas**: `POST $BASE_URL/ventas/chaos/sidecar` le pide al sidecar Envoy que termine (`/quitquitquit`, su puerto de administración, que solo es alcanzable desde dentro de la tarea). Se usa en E4.

**3. AWS CLI** para las caídas de infraestructura (E3, E4 y E5): `aws ecs stop-task` detiene una tarea como si su proceso hubiera muerto, y `aws rds reboot-db-instance` reinicia la base de datos. Los comandos exactos están en cada experimento.

**4. Endpoint de observación del Outbox**: `GET $BASE_URL/ventas/outbox/resumen` retorna cuántas filas de `outbox_http_calls` hay en PENDING, DELIVERED y FAILED, la más antigua pendiente y la última entregada. Con él sigue la reconciliación desde AWS, sin abrir la base de datos.

#### El sidecar Envoy: archivos y flujo

El directorio `apps/ventas/sidecar/` contiene tres archivos:

| Archivo            | Rol                                                                              |
| ------------------ | -------------------------------------------------------------------------------- |
| `Dockerfile`       | Imagen base `envoyproxy/envoy:v1.31` + `gettext-base` para la sustitución de variables |
| `entrypoint.sh`    | Al arrancar, sustituye `${INVENTARIO_UPSTREAM_HOST}` y `${INVENTARIO_UPSTREAM_PORT}` en el template y lanza Envoy |
| `envoy.yaml.tmpl`  | Configuración de Envoy con los parámetros de retry y circuit breaker — **usted debe completar los valores marcados con `???`** |


**Variables de entorno del sidecar:**

| Variable                   | Docker Compose (local) | ECS                       | Quién lo llena |
| -------------------------- | ---------------------- | ------------------------- | --- |
| `INVENTARIO_UPSTREAM_HOST` | `inventario`           | DNS del balanceador de Inventario | `docker-compose.yml` en local; el template de CloudFormation en ECS (`!GetAtt InventarioALB.DNSName`). No lo escriba a mano. |
| `INVENTARIO_UPSTREAM_PORT` | `3002`                 | `80`                      | Igual que la anterior. |

**Variables de entorno del contenedor ventas:**

| Variable              | Valor en ECS          | Por qué                                              |
| --------------------- | --------------------- | ---------------------------------------------------- |
| `INVENTARIO_BASE_URL` | `http://localhost:10000` | En ECS los containers del mismo task comparten la red; el sidecar escucha en ese puerto |
| `INVENTARIO_TIMEOUT_MS` | `9000`              | Debe ser mayor que el timeout total del sidecar para no abortar antes de que Envoy resuelva los reintentos |

Ambas ya están en el template. Solo cambian en el grupo de control de E1 y E2, cuando se quita el sidecar (sección 6.1, procedimiento B).

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
- `1 + num_retries` ≤ 2. Cada venta genera como máximo una llamada original más `num_retries` reintentos, así que en el peor caso (todas las llamadas fallan) el factor de amplificación es `1 + num_retries`. Es lo que exige el ASR-2: con reintentos activos, Inventario no debe recibir más del doble de las llamadas de disponibilidad que recibe sin reintentos (fórmula en la sección 4.4.5).
- `base_ejection_time` < duración del fallo inyectado (`durationMs`), para que el estado HALF-OPEN alcance a probar varias veces mientras dura el fallo y detecte pronto la recuperación. Tenga en cuenta que Envoy **multiplica** `base_ejection_time` por el número de veces que el host ha sido eyectado seguidas: cada reapertura deja el circuito OPEN más tiempo.
- El ASR-1 exige p99 < 3000 ms: una petición de prueba en HALF-OPEN que espera el `timeout` completo de la ruta también cuenta en ese p99.

> [!IMPORTANT]
> **Pregunta 3 (parte B — valores implementados; es la continuación de la parte A, en la que propuso un conjunto inicial de parámetros):**
> Documente en su entregable los valores que eligió para cada `TODO`, la justificación cuantitativa de cada uno y cómo garantiza que no violan el ASR-2 (factor de amplificación ≤ 2). Para `base_ejection_time` justifique el valor configurado; el análisis de cuándo pasó realmente a HALF-OPEN, con sus mediciones, va en la sección 7.2.1.

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

#### Ajuste de código: graceful degradation en Ventas

El sidecar maneja la capa de red. La decisión de negocio —qué responder al cliente cuando Inventario está caído— debe estar en el código de Ventas.

Cuando el circuito está OPEN, el sidecar devuelve HTTP 503 a Ventas. El cliente HTTP (`InventarioDisponibilidadClient`) convierte ese 503 en una excepción `ServiceUnavailableException`. Sin manejo explícito, esa excepción se propaga y Ventas retorna 503 al tendero.

Ese manejo está en `libs/ventas/src/services/venta.service.ts` y ya está aplicado en la rama `availability`; no tiene que escribirlo. Este es el fragmento relevante del método `create()`:

```typescript
// Verificar disponibilidad de stock para items con productoId.
let isDegraded = false;
for (const item of dto.items) {
  if (item.productoId) {
    try {
      const disponible = await this.inventarioClient.isDisponible(item.productoId);
      if (!disponible) {
        throw new BadRequestException(
          `Producto con id ${item.productoId} sin stock disponible`,
        );
      }
    } catch (error) {
      // El sidecar abrió el circuito o Inventario no está disponible:
      // marcar la venta para graceful degradation en lugar de cascadear el fallo.
      if (error instanceof ServiceUnavailableException) {
        isDegraded = true;
      } else {
        throw error; // otros errores (BadRequest, NotFound) se propagan normalmente
      }
    }
  }
}

// ... la venta y su fila de Outbox se guardan en una transacción (sección 6.7) ...

if (isDegraded) {
  return {
    ...this.mapToResponse(venta),
    status: 'pending_stock_confirmation',
    message: 'Pedido registrado. La disponibilidad de stock será confirmada próximamente.',
  };
}
return this.mapToResponse(venta);
```

La variable `isDegraded` es la que conecta la graceful degradation con el Outbox: el `catch` no retorna de inmediato, sino que marca la venta para graceful degradation, deja que la venta se guarde junto con su fila de Outbox y solo al final responde `pending_stock_confirmation`. Volverá sobre esto en el experimento E3.

> [!NOTE]
> NestJS responde `POST` con **HTTP 201**, tanto para una venta normal como para una con graceful degradation. Lo que distingue la graceful degradation es el campo `status: pending_stock_confirmation` en el cuerpo. El generador de tráfico (sección 6.2) lo registra en la columna `pending` de su CSV.

> Configure `base_ejection_time` del sidecar en un valor inferior a la duración de los fallos que va a inyectar, para que el estado HALF-OPEN pueda detectar la recuperación de Inventario.

### 5.9 Cómo ver métricas en CloudWatch

> [!NOTE]
> **Amazon CloudWatch** es el servicio de observabilidad de AWS para ver métricas (series de tiempo), registros (logs) y alarmas. En este laboratorio lo usará para observar **cuántas peticiones llegan a Inventario**, **cuántos errores 5xx** se producen, **cuándo el balanceador marca una tarea como no sana** y **cuándo cambia el estado del circuito**. Estos pasos los repetirá en cada experimento.

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
  - `TargetResponseTime` (latencia del target vista por el ALB; no reemplaza el p99 del generador de tráfico, pero ayuda a correlacionar)
  - `HealthyHostCount` y `UnHealthyHostCount` (statistic `Maximum`): cuántas tareas considera sanas el balanceador. Son la fuente del TTD y del TTR de los experimentos de caída (E3, E4).
4. En el gráfico, ajuste:
  - **Time range** al intervalo exacto de su experimento
  - **Period** a 1 minuto (recomendado) para ver cambios con claridad
  - **Statistic**: `Sum` para `RequestCount` y `HTTPCode_Target_5XX_Count`

> Para estimar *requests/s* desde CloudWatch: si su `RequestCount` es por minuto (period=60s), entonces $\text{req/s} \approx \text{RequestCount}/60$. Las métricas del ALB tienen resolución de 1 minuto: para tiempos de detección y recuperación en segundos use el CSV del generador de tráfico, los logs del sidecar y los eventos de ECS.

**Ver los eventos de ECS (reemplazo de tareas):**

En **ECS → Clusters → `Cheapest-lab5-cluster` → Services → (servicio) → pestaña Events** aparece, con hora, cada paso de la recuperación: la tarea detenida, la tarea nueva iniciada (*has started 1 tasks*), su registro en el target group (*registered 1 targets*) y el momento en que el servicio vuelve a su estado estable (*has reached a steady state*). La misma información está en la AWS CLI:

```bash
aws ecs describe-services --cluster Cheapest-lab5-cluster --services svc-Cheapest-inventario \
  --query "services[0].events[:10].[createdAt,message]" --output table
```

**Ver los reintentos y el estado del circuito en los logs del sidecar:**

En Fargate no hay forma directa de abrir el puerto de administración de Envoy (9901) desde su computador, así que el estado del circuito se observa en los **registros de acceso** del sidecar, que Envoy escribe en CloudWatch Logs (grupo `/ecs/Cheapest-ventas-sidecar`). Cada línea corresponde a una petición de Ventas hacia Inventario y tiene esta forma:

```
[2026-10-14T15:02:11.512Z] "GET /inventory/items/disponibilidad/aaaa... HTTP/1.1" 503 UH 0 19 0 - "-" ...
                                                                              ^^^ ^^
                                                                   código HTTP   response flags
```

El segundo campo después de la petición son las *response flags* de Envoy. Las que importan en este laboratorio:

| Flag | Significado | Qué le dice del circuito |
| --- | --- | --- |
| `-` | Respuesta normal de Inventario | CLOSED, Inventario respondió |
| `UT` | *Upstream timeout*: se agotó el `timeout` de la ruta | CLOSED, Inventario es lento; cuenta como 5xx para abrir el circuito |
| `UF` / `URX` | Falla de conexión / se agotaron los reintentos | CLOSED, con reintentos fallidos |
| `UH` | *No healthy upstream*: no hay ningún host de Inventario disponible | **OPEN**: Envoy rechazó la petición sin llamar a Inventario |

Para ver la evolución en el tiempo, abra **CloudWatch → Logs → Logs Insights**, seleccione el grupo `/ecs/Cheapest-ventas-sidecar`, ajuste el rango al de su prueba y ejecute:

```
parse @message /HTTP\/1\.1" (?<code>\d{3}) (?<flags>\S+) /
| filter ispresent(code)
| stats count(*) as peticiones by bin(10s), code, flags
| sort by bin(10s) asc
```

El intervalo en que aparece `UH` es el tiempo con el circuito OPEN. El primer intervalo después de ese en que vuelven las respuestas `200 -` marca el regreso a CLOSED. Para contar reintentos use el contador `llamadasDisponibilidad` del endpoint de caos (sección 4.4.5): este log registra una línea por petición de Ventas, no por intento.

> [!TIP]
> Si reproduce un experimento en su computador con Docker Compose (sección 6.3), sí puede consultar directamente el puerto de administración: `curl -s http://localhost:9901/stats | grep -E "outlier_detection.ejections_active|upstream_rq_retry"`. `ejections_active` > 0 significa circuito OPEN.

## 6. Realización de pruebas

En la sección anterior dejó desplegado el stack, configurado el sidecar y revisado el código. Aquí se explica cómo preparar cada configuración, cómo correr un experimento de caos (el protocolo es el mismo para todos) y qué fallo inyectar en cada experimento del catálogo. Lo que **no** encontrará aquí son las hipótesis ni los resultados esperados: esos los escribe usted en las fichas (sección 4.4.3).

### 6.1 Puntos de sensibilidad

| Punto de sensibilidad | Dónde se modifica | Efecto esperado |
| --- | --- | --- |
| **Fallo de Inventario** (`mode`, `delayMs`, `errorRate`, `durationMs`) | Endpoint de caos `POST {BASE_URL}/inventario/chaos` (sección 5.8). Efecto inmediato, sin revisiones. | Define qué tan grave es el fallo y cuánto dura. `durationMs` es lo que permite observar la recuperación. |
| **Presencia del sidecar** | Task definition `td-Cheapest-ventas` (procedimientos A y B): con un solo contenedor (`ventas`) e `INVENTARIO_BASE_URL` apuntando al balanceador de Inventario no hay sidecar; con el contenedor `ventas-sidecar` e `INVENTARIO_BASE_URL=http://localhost:10000`, las llamadas pasan por Envoy. | Sin sidecar no hay timeout corto, ni reintentos, ni circuit breaker. |
| **Reintentos** (`num_retries`, `base_interval`, `max_interval`) | Archivo `apps/ventas/sidecar/envoy.yaml.tmpl`. Cada cambio exige reconstruir la imagen del sidecar, publicarla en ECR con un tag nuevo y cambiar la imagen del contenedor `ventas-sidecar` (procedimiento A). | Más reintentos recuperan más fallos transitorios, pero multiplican las peticiones que recibe Inventario. |
| **Timeout de la ruta** (`timeout`) | El mismo archivo `envoy.yaml.tmpl`. | Un timeout corto libera rápido a Ventas, pero puede cortar peticiones que habrían respondido. |
| **Umbral de apertura del circuito** (`consecutive_5xx`) | El mismo archivo `envoy.yaml.tmpl`, sección `outlier_detection`. | Bajo: el circuito abre rápido, incluso por fallos pasajeros. Alto: tarda en abrir y el fallo se propaga más tiempo. |
| **Tiempo que el circuito permanece abierto** (`base_ejection_time`) | El mismo archivo `envoy.yaml.tmpl`, sección `outlier_detection`. | Corto: prueba con frecuencia si Inventario se recuperó. Largo: Ventas tarda en notar la recuperación. |
| **Timeout de Ventas hacia el sidecar** (`INVENTARIO_TIMEOUT_MS`) | Variable de entorno del contenedor `ventas` (procedimiento A). El template la deja en `9000`. | Debe ser mayor que el timeout total del sidecar; si es menor, Ventas aborta antes de que Envoy termine sus reintentos. |
| **Límite de peticiones** (*Rate* y *Burst*) | API Gateway → `Cheapest-ms-api` → stage `lab` (E6). | Un límite bajo protege a los servicios, pero rechaza peticiones legítimas; un límite de stage no distingue clientes ni tipos de tráfico. |
| **Detección del balanceador** (`HealthCheckIntervalSeconds`, umbrales de sano/no sano) y **número de tareas** (`DesiredCount`) | Template de CloudFormation (target groups y servicios ECS). **No los modifique** durante el laboratorio: son lo que mide en E3 y E4. | Determinan cuánto tarda el sistema en notar una tarea caída y si hay otra que atienda mientras tanto. Úselos en su decisión arquitectónica (sección 7.4). |

#### Procedimiento A — Crear una nueva revisión de una task definition

1. Consola de AWS → **ECS → Task definitions** → elija la familia (`td-Cheapest-inventario` o `td-Cheapest-ventas`) → seleccione la revisión **más reciente** → **Create new revision** → **Create new revision with JSON**.
2. Haga en el JSON el cambio que pide el paso (variables en `environment`, imagen en `image`, contenedores en `containerDefinitions`) y haga clic en **Create**.
3. Vaya a **ECS → Clusters → `Cheapest-lab5-cluster` → Services**, seleccione el servicio (`svc-Cheapest-inventario` o `svc-Cheapest-ventas`) → **Update service**, elija la revisión que acaba de crear en **Revision** y haga clic en **Update**.
4. Espere a que en la pestaña **Tasks** quede una sola tarea en `RUNNING` con la revisión nueva (la anterior pasa a `STOPPED`). Tarda entre 2 y 5 minutos.

#### Procedimiento B — Preparar las tres configuraciones de Ventas

E1 y E2 comparan tres configuraciones de Ventas. Prepárelas una sola vez, anote el número de revisión de cada una y, durante los experimentos, cambie de configuración actualizando `svc-Cheapest-ventas` a la revisión correspondiente (pasos 3 y 4 del procedimiento A).

| Configuración | Revisión de `td-Cheapest-ventas` | Cómo se obtiene |
| --- | --- | --- |
| **Completa** (reintentos + circuit breaker) | La que creó CloudFormation | Ya existe; anote su número. |
| **Solo reintentos** | Nueva | Ver paso 1. |
| **Sin sidecar** (grupo de control) | Nueva | Ver paso 2. |

1. **Solo reintentos.** En `apps/ventas/sidecar/envoy.yaml.tmpl` cambie temporalmente `enforcing_consecutive_5xx: 100` por `enforcing_consecutive_5xx: 0` (Envoy sigue contando errores, pero no eyecta el host, es decir, el circuito nunca se abre). Construya y publique la imagen con el tag **`1.0.0-solo-retry`**:
   ```bash
   docker build --platform linux/amd64 -t <URI_ECR_SIDECAR>:1.0.0-solo-retry apps/ventas/sidecar/
   docker push <URI_ECR_SIDECAR>:1.0.0-solo-retry
   ```
   Después **devuelva el valor a `100`** en el archivo, para que su repositorio quede con la configuración completa. Con el procedimiento A, parta de la revisión **completa** y cambie solo la imagen del contenedor `ventas-sidecar`:
   ```json
   "image": "<URI_ECR_SIDECAR>:1.0.0-solo-retry"
   ```
2. **Sin sidecar.** Con el procedimiento A, parta de la revisión **completa** y en el JSON:
   - borre completo el objeto del contenedor `ventas-sidecar` dentro de `containerDefinitions` (desde su `{` hasta su `}`, incluida la coma que lo separa del contenedor `ventas`);
   - en el contenedor `ventas`, cambie `INVENTARIO_BASE_URL` para que apunte directamente al balanceador de Inventario. El DNS está en las salidas del stack (`aws cloudformation describe-stacks --stack-name Cheapest-lab5 --query "Stacks[0].Outputs[?OutputKey=='InventarioALBDns'].OutputValue" --output text`):
     ```json
     { "name": "INVENTARIO_BASE_URL", "value": "http://<InventarioALBDns>" }
     ```
   Al desplegarla, verifique que la tarea de Ventas tiene un solo contenedor (pestaña **Tasks** → la tarea → **Containers**) y que `curl $BASE_URL/ventas/health` responde 200.

> [!NOTE]
> Cada cambio de revisión reinicia la tarea de Ventas (2 a 5 minutos). Ordene sus experimentos para cambiar de configuración el menor número de veces: por ejemplo, haga con la configuración completa todos los experimentos que la usan antes de pasar a la siguiente. Termine siempre con la configuración completa, que es la que usan E3 a E6.

### 6.2 Protocolo común y generador de tráfico de estado estable

Todos los experimentos siguen el mismo protocolo.

**1. Prepare el sistema.**

```bash
ITEM=11111111-1111-4111-8111-111111111111

# Reponer stock: el generador de tráfico vende 2 unidades por segundo y el seed solo trae 100. Sin este paso,
# en menos de un minuto las ventas empiezan a fallar por falta de stock y contaminan el experimento.
curl -s -X PATCH $BASE_URL/inventario/items/$ITEM -H 'Content-Type: application/json' -d '{"cantidad": 100000}'

# Confirmar que no hay un fallo activo y anotar el contador de llamadas
curl -s -X POST $BASE_URL/inventario/chaos -H 'Content-Type: application/json' -d '{"mode": "off"}'
curl -s $BASE_URL/inventario/chaos

# Confirmar que una venta se confirma normalmente (sin pending_stock_confirmation)
curl -s -X POST $BASE_URL/ventas/ventas -H 'Content-Type: application/json' -d @venta.json
```

**2. Arranque el generador de tráfico** en una terminal aparte, desde la carpeta donde está `venta.json`, con un archivo de salida por experimento y configuración (ajuste la ruta a donde tenga la carpeta `lab_5/recursos` de este repositorio):

```bash
BASE_URL=$BASE_URL ./lab_5/recursos/generador_trafico.sh e1_completa.csv
```

El generador de tráfico envía 2 ventas por segundo a `POST /ventas/ventas` y, cada 5 s, una petición a `GET /logistica/health`, `GET /inventario/items/{ITEM}` y `GET /ventas/productos-externos` para medir el radio de impacto. Cada petición sale en segundo plano, de modo que **la tasa no baja aunque el sistema se ponga lento** (lazo abierto). Deje el generador de tráfico corriendo durante todo el experimento y deténgala con `Ctrl+C` al final.

**3. Siga el cronograma.** Anote cada hora en UTC (`date -u +%H:%M:%S`), que es la zona horaria del CSV del generador de tráfico y de los logs de CloudWatch.

| Momento | Qué hacer |
| --- | --- |
| T−2 min | Arranque el generador de tráfico: dos minutos de estado estable antes del fallo. |
| T_inj | Inyecte el fallo del experimento. Anote la hora (el endpoint de caos la retorna en `injectedAt`). |
| T_inj → T_rem | Observe. Si se cumple su condición de aborto, retire el fallo de inmediato y anótelo. |
| T_rem | El fallo se retira (solo, al cumplirse `durationMs`, o porque usted lo retiró). En las caídas, T_rem es cuando el componente vuelve a estar disponible. |
| T_rem → T_rem + 3 min | Siga observando: es el período de recuperación. |
| Fin | Detenga el generador de tráfico. |

**4. Resuma el CSV por ventanas de 10 s:**

```bash
python3 lab_5/recursos/ventanas.py e1_completa.csv
```

El script imprime, por ventana y por endpoint, el número de peticiones, la disponibilidad percibida (2xx en menos de 3 s), el % de `pending` y el p99, y guarda la tabla en `e1_completa_ventanas.csv` para graficar la línea de tiempo en una hoja de cálculo. Identificar el estado estable, el TTD y el TTR a partir de esa tabla es parte de su análisis.

> [!IMPORTANT]
> **Un fallo a la vez** (E6 combina dos a propósito). Antes de empezar un experimento, verifique que el anterior terminó: fallo apagado, circuito cerrado (una venta sin `pending`), tareas en `RUNNING` y sin filas PENDING en `GET $BASE_URL/ventas/outbox/resumen`. Si mezcla dos fallos, no podrá atribuirle el resultado a ninguno.

### 6.3 Ambiente local (opcional)

Puede reproducir los experimentos en su computador con Docker Compose para preparar las fichas o para repetir uno sin gastar créditos: los endpoints de caos funcionan igual, y el puerto de administración de Envoy (`http://localhost:9901/stats`) sí es accesible. Los datos que entrega en el informe deben venir de AWS.

Use **`docker compose`** (con espacio, el plugin de Docker Compose v2). Si su instalación solo tiene el binario antiguo `docker-compose` (con guion), reemplácelo en todos los comandos.

```bash
git checkout availability
docker compose up -d --build        # postgres, logística, inventario, sidecar y ventas
# Espere ~30 s a que los servicios creen las tablas y luego siembre la base local:
npm install                         # si no lo hizo en la sección 5.6
npm run db:seed                     # por defecto apunta a la base de Docker Compose (127.0.0.1:5432, base cheapest)
```

Los servicios se llaman **directamente**, sin API Gateway, así que aquí se usan las rutas internas en inglés (`/inventory/...`). Cree un producto externo con `POST http://localhost:3003/ventas/productos-externos` (mismo cuerpo de la sección 5.6) y un `venta-local.json` con ese `productoExternoId`. Para el generador de tráfico, sobrescriba los endpoints:

```bash
VENTA_JSON=venta-local.json \
VENTA_URL=http://localhost:3003/ventas/ventas \
LOGISTICA_URL=http://localhost:3001/health \
INVENTARIO_URL=http://localhost:3002/inventory/items/11111111-1111-4111-8111-111111111111 \
CATALOGO_URL=http://localhost:3003/ventas/productos-externos \
./lab_5/recursos/generador_trafico.sh local_e1.csv
```

| En AWS | En local |
| --- | --- |
| `$BASE_URL/inventario/chaos` | `http://localhost:3002/inventory/chaos` |
| `$BASE_URL/ventas/chaos/sidecar`, `$BASE_URL/ventas/outbox/resumen` | `http://localhost:3003/ventas/chaos/sidecar`, `http://localhost:3003/ventas/outbox/resumen` |
| `aws ecs stop-task` (Inventario o Ventas) | `docker compose stop inventario` y luego `docker compose start inventario` (en local no hay un orquestador que reemplace el contenedor solo: usted hace el papel de ECS) |
| `aws rds reboot-db-instance` | `docker compose stop postgres` y luego `docker compose start postgres` |
| Consultas SQL | `docker compose exec -T postgres psql -U postgres -d cheapest -c "<SQL>"` |

Al terminar, apague el ambiente local con `docker compose down`.

### 6.4 E0 — Estado estable

**Configuración:** Ventas con la revisión **completa**. No se inyecta ningún fallo.

Siga el protocolo durante 5 minutos sin inyectar nada. Con la tabla de `ventanas.py`, defina el estado estable que usará en todas las fichas: disponibilidad percibida, p99 y % de `pending` de las ventas, y el comportamiento de los otros tres endpoints. Lea también el contador `llamadasDisponibilidad` al principio y al final, y calcule las llamadas por venta en estado estable.

**Qué observar:**

- ¿Qué tanto varían la disponibilidad y el p99 de una ventana a otra sin ningún fallo? Esa variación natural es la que debe tener en cuenta al decidir si un experimento "se desvió" del estado estable.
- ¿Hay respuestas `pending` sin fallo? Si las hay, resuelva la causa antes de seguir.

### 6.5 E1 — Inventario lento

**Configuraciones:** completa, solo reintentos y sin sidecar (procedimiento B). Haga el experimento una vez con cada una.

**Fallo:** latencia de 5 s en la consulta de disponibilidad, durante 3 minutos.

```bash
curl -s $BASE_URL/inventario/chaos                      # anote llamadasDisponibilidad
curl -s -X POST $BASE_URL/inventario/chaos -H 'Content-Type: application/json' \
  -d '{"mode": "latency", "delayMs": 5000, "durationMs": 180000}'
# ... al terminar el período de recuperación:
curl -s $BASE_URL/inventario/chaos                      # vuelva a anotar llamadasDisponibilidad
```

**Qué observar:**

- ¿Cómo se propaga la latencia de Inventario a las ventas en cada configuración? ¿Qué pasa con la disponibilidad percibida, el p99 y el % de `pending` por ventana?
- ¿Cuánto tardó cada configuración en reaccionar al fallo (TTD) y en volver al estado estable después de T_rem (TTR)? En la configuración completa, ubique en los logs del sidecar (consulta de Logs Insights de la sección 5.9) el primer `503 UH` (circuito OPEN), las peticiones de prueba en HALF-OPEN y el regreso a `200 -` (CLOSED).
- ¿Cuántas llamadas por venta recibió Inventario en cada configuración? Calcule el factor de amplificación (sección 4.4.5).
- ¿Los otros endpoints del generador de tráfico se vieron afectados?

> [!NOTE]
> Sin sidecar, Ventas espera a Inventario hasta `INVENTARIO_TIMEOUT_MS` (9 s), así que cada venta tarda lo que tarde Inventario. Que la respuesta termine siendo un 201 no significa que el tendero la haya recibido a tiempo: por eso la disponibilidad percibida solo cuenta las respuestas que llegan en menos de 3 s.

### 6.6 E2 — Inventario con errores

**Configuraciones:** completa, solo reintentos y sin sidecar. Haga el experimento una vez con cada una (puede hacerlo en la misma visita a cada configuración que E1).

**Fallo:** primero errores intermitentes (30 % de las consultas responde 500) durante 2 minutos e, inmediatamente después, errores totales (100 %) durante 2 minutos.

```bash
curl -s $BASE_URL/inventario/chaos                      # anote llamadasDisponibilidad
curl -s -X POST $BASE_URL/inventario/chaos -H 'Content-Type: application/json' \
  -d '{"mode": "error", "errorRate": 0.3, "durationMs": 120000}'
# al cumplirse los 2 minutos (anote el contador otra vez):
curl -s -X POST $BASE_URL/inventario/chaos -H 'Content-Type: application/json' \
  -d '{"mode": "error", "errorRate": 1, "durationMs": 120000}'
```

**Qué observar:**

- Con errores intermitentes, ¿qué fracción de las ventas terminó en `pending` en cada configuración? ¿Los reintentos lograron que más ventas se confirmaran con stock verificado?
- ¿El circuito se abrió con errores intermitentes, con errores totales o con ambos? Relacione la respuesta con su valor de `consecutive_5xx`.
- Calcule el factor de amplificación por separado para la fase intermitente y la total. ¿En cuál de las dos los reintentos son útiles y en cuál solo agregan carga?
- Compare con E1: ¿por qué el mismo sidecar se comporta distinto ante un Inventario lento y ante uno que falla rápido?

### 6.7 E3 — Caída de la tarea de Inventario

**Configuración:** completa.

Este experimento mide dos cosas: cuánto tarda la infraestructura en reemplazar una tarea caída (ASR-5) y si las ventas registradas mientras tanto descuentan su stock exactamente una vez cuando Inventario vuelve (ASR-4).

#### El problema que el circuit breaker no resuelve

El circuit breaker y la graceful degradation mantienen a Ventas *disponible*: el tendero recibe una respuesta exitosa incluso cuando Inventario está caído. Pero hay un efecto secundario silencioso: **el stock nunca se decrementó** en ese momento. Cuando Inventario se recupera, alguien tiene que recordar cuántas ventas ocurrieron mientras estaba caído.

Peor aún, si el descuento de stock se reintenta (porque un cliente o un proceso no supo si su primera petición llegó), el mismo descuento puede aplicarse dos veces.

Esto demuestra que **resiliencia de infraestructura ≠ consistencia de datos**.

#### Conceptos: Outbox e idempotencia

##### Outbox HTTP

El **patrón Outbox** resuelve la primera inconsistencia. En lugar de decrementar el stock en el mismo momento que se crea la venta (lo cual falla si Inventario está caído), Ventas escribe una fila en la tabla local `outbox_http_calls` dentro de **la misma transacción** que guarda la venta:

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
  → UPDATE SET status = 'FAILED' si Inventario la rechaza con otro 4xx (p. ej. stock insuficiente)
  → si falla por red o 5xx, la deja en PENDING y la reintenta en el siguiente ciclo
```

La garantía: **at-least-once** — si la venta se guardó, el decremento de stock se entregará eventualmente, incluso si Inventario estuvo caído un buen rato. Toda venta usa el Outbox, no solo las que se registran con graceful degradation.

##### Idempotencia

El **patrón de Idempotencia** resuelve la segunda inconsistencia. El publicador puede enviar la misma fila de `outbox_http_calls` más de una vez (si falla entre enviarla y marcarla `DELIVERED`). El endpoint `/inventory/ventas/desde-outbox` usa el `id` de esa fila como `X-Idempotency-Key`:

```
POST /inventory/ventas/desde-outbox  (Header: X-Idempotency-Key: <id de la fila de outbox_http_calls>)
  → ¿Existe en processed_calls una fila con "idempotencyKey" = <id>?
      SÍ → responder 409 (ya procesado, no hacer nada)
      NO → decrementar stock + INSERT en processed_calls en la misma transacción
```

Combinando at-least-once (Outbox) con idempotencia (`processed_calls`), el sistema efectivamente garantiza que cada venta decrementa el stock **exactamente una vez**.

#### Revisar la escritura transaccional en `VentaService`

Archivo: `libs/ventas/src/services/venta.service.ts`

El método `create()` ya implementa el Outbox. Revise el código y verifique:
1. La `Venta` y el `OutboxHttpCall` se guardan en la misma transacción. ¿Qué ocurre si el proceso muere entre el `manager.save(Venta)` y el `manager.save(OutboxHttpCall)`?
2. ¿Por qué el `OutboxHttpCall` se crea incluso en el camino de graceful degradation (`isDegraded = true`, sección 5.8)?
3. ¿Qué payload lleva el `OutboxHttpCall`? Verifique que incluye todos los campos que `POST /inventory/ventas/desde-outbox` necesita.

#### Revisar el endpoint con idempotencia en Inventario

Archivo: `libs/inventario/src/services/registro-venta.service.ts` → método `createDesdeOutbox()`

Analice el flujo implementado y responda:
1. ¿Qué ocurre si el proceso de Inventario muere entre `decrementCantidad()` y el `save(ProcessedCall)`? ¿Puede producirse un decremento sin `ProcessedCall`?
2. ¿Por qué se usa el `id` del `OutboxHttpCall` como clave de idempotencia en lugar del `ventaId`?

#### Parte 1 — Idempotencia (antes de la caída)

Inventario expone dos endpoints para registrar una venta y descontar stock: `POST /inventory/ventas`, sin clave de idempotencia, y `POST /inventory/ventas/desde-outbox`, con clave. Use los dos con **la misma petición repetida**, que representa una única venta (mismo `ventaId`):

```bash
cat > registro.json <<'JSON'
{
  "tiendaId": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
  "productoId": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
  "ventaId": "f0000000-0000-4000-8000-000000000001",
  "itemInventarioId": "11111111-1111-4111-8111-111111111111",
  "fechaVenta": "2026-10-14T10:00:00Z",
  "cantidad": 1
}
JSON

# Sin clave de idempotencia: anote la cantidad, envíe dos veces, vuelva a consultar
curl -s $BASE_URL/inventario/items/$ITEM | grep -o '"cantidad":[0-9]*'
curl -s -X POST $BASE_URL/inventario/ventas -H 'Content-Type: application/json' -d @registro.json; echo
curl -s -X POST $BASE_URL/inventario/ventas -H 'Content-Type: application/json' -d @registro.json; echo
curl -s $BASE_URL/inventario/items/$ITEM | grep -o '"cantidad":[0-9]*'

# Con clave de idempotencia: la misma petición dos veces con la misma clave
KEY=$(uuidgen | tr 'A-Z' 'a-z')
curl -i -X POST $BASE_URL/inventario/ventas/desde-outbox -H 'Content-Type: application/json' \
  -H "X-Idempotency-Key: $KEY" -d @registro.json
curl -i -X POST $BASE_URL/inventario/ventas/desde-outbox -H 'Content-Type: application/json' \
  -H "X-Idempotency-Key: $KEY" -d @registro.json
curl -s $BASE_URL/inventario/items/$ITEM | grep -o '"cantidad":[0-9]*'
```

Haga esta parte **sin el generador de tráfico corriendo**, para que la cantidad solo cambie por sus peticiones. Compare cuánto bajó la cantidad en cada caso y qué código HTTP respondió la segunda petición con clave.

> [!IMPORTANT]
> **Pregunta 5:**
> Describa con precisión el estado de inconsistencia que se produce en cada escenario:
> 1. Ventas registradas durante la caída de Inventario (Parte 2 de este experimento, antes de que Inventario vuelva): ¿qué diferencia hay entre lo que dice la tabla `ventas` y lo que dice `items_inventario.cantidad`?
> 2. Reintento sin idempotencia (Parte 1): ¿qué invariante de negocio se viola? ¿Cómo lo detectaría operacionalmente en Cheapest?

#### Parte 2 — Caída de la tarea

1. Prepare el sistema (protocolo, paso 1), anote la cantidad del ítem y arranque el generador de tráfico.
2. En otra terminal, registre el estado del Outbox y la salud de Inventario cada 5 s durante todo el experimento:
   ```bash
   while true; do
     printf "%s health=%s %s\n" "$(date -u +%H:%M:%S)" \
       "$(curl -s -o /dev/null -w '%{http_code}' --max-time 4 $BASE_URL/inventario/health)" \
       "$(curl -s --max-time 4 $BASE_URL/ventas/outbox/resumen)"
     sleep 5
   done | tee e3_outbox.log
   ```
3. Pasados 2 minutos de estado estable, detenga la tarea de Inventario. Anote la hora: es T_inj.
   ```bash
   TASK=$(aws ecs list-tasks --cluster Cheapest-lab5-cluster --service-name svc-Cheapest-inventario --query "taskArns[0]" --output text)
   date -u +%H:%M:%S; aws ecs stop-task --cluster Cheapest-lab5-cluster --task $TASK --reason "E3 caos"
   ```
4. No haga nada más: ECS debe lanzar una tarea nueva solo. Observe hasta 3 minutos después de que `health` vuelva a 200 (ese momento es **T_rec**) y las filas PENDING lleguen a 0.
5. Detenga el generador de tráfico y el registro. Consulte la cantidad final del ítem y los eventos del servicio (sección 5.9):
   ```bash
   curl -s $BASE_URL/inventario/items/$ITEM | grep -o '"cantidad":[0-9]*'
   aws ecs describe-services --cluster Cheapest-lab5-cluster --services svc-Cheapest-inventario \
     --query "services[0].events[:10].[createdAt,message]" --output table
   ```

**Qué observar:**

- **MTTR descompuesto:** con los eventos de ECS, `HealthyHostCount`/`UnHealthyHostCount` del target group de Inventario y el registro de salud, ubique en el tiempo: la tarea detenida, la tarea nueva iniciada, su registro en el target group, el momento en que quedó `healthy` y el primer `health=200`. ¿Qué etapa dominó el MTTR?
- **Ventas durante la caída:** ¿qué respondió el balanceador de Inventario mientras no tenía tareas (código y velocidad), y cómo reaccionó el sidecar? ¿Se mantuvo la disponibilidad percibida de las ventas?
- **Outbox:** ¿cuántas filas se acumularon en PENDING? ¿Cuánto tardaron en pasar a DELIVERED después de T_rec? ¿Quedó alguna en FAILED?
- **Exactamente una vez:** compare cuánto bajó la cantidad del ítem con el número de ventas 201 que registró el generador de tráfico (`grep -c ',venta,201,' e3.csv`). ¿Coinciden?

> [!IMPORTANT]
> **Pregunta 7:**
> El equipo de operaciones de Cheapest quiere repetir el E3 en producción, un lunes por la mañana, para confirmar los resultados con tráfico real. ¿Lo aprobaría? Si lo aprueba, defina las condiciones: cómo limitaría el radio de impacto (qué porcentaje de tiendas o de tráfico), qué condiciones de aborto usaría y con qué umbrales, quién debe estar presente y cómo revertiría. Si no lo aprueba, explique qué tendría que cambiar en la arquitectura (piense en el `DesiredCount` de Inventario) para que fuera aceptable.

### 6.8 E4 — Caída del sidecar y de la tarea de Ventas

**Configuración:** completa. Experimento **exploratorio**: no hay ASR que verificar en la Parte 1, pero debe escribir su hipótesis antes.

#### Parte 1 — El sidecar se cae

1. Prepare el sistema, arranque el generador de tráfico y, pasados 2 minutos, apague el sidecar (T_inj):
   ```bash
   date -u +%H:%M:%S; curl -s -X POST $BASE_URL/ventas/chaos/sidecar
   ```
2. Observe hasta 3 minutos después de que las ventas vuelvan al estado estable. Consulte los eventos de `svc-Cheapest-ventas` y `HealthyHostCount` del target group de Ventas.

**Qué observar:** ¿qué le pasó al contenedor `ventas` cuando se cayó su sidecar? (Revise `Essential` en la task definition.) ¿Qué endpoints del generador de tráfico se afectaron y cuáles no? ¿Cuánto tardó la recuperación y quién la hizo? Compare el radio de impacto con el de E3: ¿qué es más grave para Cheapest, que se caiga Inventario o que se caiga el sidecar de Ventas?

#### Parte 2 — Ventas se reinicia con entregas pendientes

1. Prepare el sistema y arranque el generador de tráfico. Inyecte errores totales en Inventario **sin duración** (quedan activos hasta que los apague), para que las ventas se registren con graceful degradation y el Outbox acumule filas PENDING:
   ```bash
   curl -s -X POST $BASE_URL/inventario/chaos -H 'Content-Type: application/json' -d '{"mode": "error", "errorRate": 1}'
   ```
2. Cuando `GET $BASE_URL/ventas/outbox/resumen` muestre varias filas PENDING, detenga el generador de tráfico, anote el resumen y detenga la tarea de Ventas:
   ```bash
   TASK=$(aws ecs list-tasks --cluster Cheapest-lab5-cluster --service-name svc-Cheapest-ventas --query "taskArns[0]" --output text)
   aws ecs stop-task --cluster Cheapest-lab5-cluster --task $TASK --reason "E4 caos"
   ```
3. Cuando la tarea nueva de Ventas esté sana, vuelva a consultar el resumen (las filas deben seguir ahí) y retire el fallo de Inventario con `{"mode": "off"}`. Mida cuánto tardan las filas PENDING en llegar a 0.

**Qué observar:** ¿se perdió alguna entrega pendiente al reiniciarse Ventas? ¿Por qué? Relacione la respuesta con la transacción de `VentaService.create()` que revisó en E3.

### 6.9 E5 — Reinicio de la base de datos compartida

**Configuración:** completa. Experimento **exploratorio**.

Los tres servicios usan la misma instancia RDS. Un reinicio es un evento de operación normal (mantenimiento, cambio de parámetros, actualización menor de versión).

1. Prepare el sistema, arranque el generador de tráfico y, pasados 2 minutos, reinicie la base (T_inj). Siga su estado:
   ```bash
   date -u +%H:%M:%S; aws rds reboot-db-instance --db-instance-identifier Cheapest-lab5-db
   while true; do
     printf "%s %s\n" "$(date -u +%H:%M:%S)" \
       "$(aws rds describe-db-instances --db-instance-identifier Cheapest-lab5-db --query 'DBInstances[0].DBInstanceStatus' --output text)"
     sleep 10
   done
   ```
   Si su cuenta no le permite el comando, use la consola: **RDS → Databases → `cheapest-lab5-db` → Actions → Reboot**.
2. Observe hasta 3 minutos después de que la base vuelva a `available`.

**Qué observar:** ¿qué endpoints del generador de tráfico fallaron y con qué código? ¿Ventas aplicó graceful degradation? ¿Por qué? ¿Qué reportaron `GET /health` y los health checks del balanceador mientras la base estaba caída, y qué consecuencia tiene eso para ECS? ¿Cuánto tardaron los servicios en volver al estado estable después de que la base volvió a `available`? ¿Alguna táctica del laboratorio cubre este fallo?

> [!IMPORTANT]
> **Pregunta 4:**
> Con base en lo que observó en E4 y E5, ¿qué riesgo residual seguiría existiendo para una operación real de Cheapest a mayor escala, aun si las tácticas del laboratorio cumplen sus ASRs?
> Responda identificando al menos dos clases de fallos que estas tácticas no resuelven por sí solas, sustentadas con sus datos, y qué capacidad adicional haría falta. Si la capacidad que propone es una capa de control de tráfico centralizada como Aperture de DoorDash, desarrolle esa comparación en la sección 7.4.2 y aquí solo refiérase a ella, sin repetirla.

### 6.10 E6 — Tormenta de reintentos (*retry storm*)

**Configuraciones:** sin sidecar (grupo de control), sin sidecar con throttling del stage, y completa. Opcional: sin sidecar con clientes que sí usan backoff.

Este experimento reproduce el escenario del lunes por la mañana. Combina dos fallos inyectados a la vez: **Inventario lento** y una **versión defectuosa de la app** que reintenta de inmediato cada pedido que no le responde en 3 s. Es el único experimento con dos fallos simultáneos, porque la tormenta solo existe cuando se juntan los dos. El script `recursos/tormenta_reintentos.sh` simula esas apps: cada una envía un pedido y, si no recibe un 2xx a tiempo, **abandona la petición y la reenvía**; después de un pedido exitoso espera 5 s antes del siguiente. Con el sistema sano es tráfico normal.

> [!IMPORTANT]
> Una petición que el cliente abandona **no se cancela en el servidor**: Ventas la sigue procesando y, si termina, registra la venta. Mida cuántas ventas se registraron (filas totales del Outbox) frente a cuántos pedidos pidieron realmente los tenderos.

**Configurar el throttling del stage** (solo para esa configuración). Use la consola (**API Gateway → `Cheapest-ms-api` → Protect → Throttling**, stage `lab`) o la CLI; el `API_ID` es la primera parte de su `BASE_URL`. Al terminar, devuelva el stage a sus valores sin efecto.

```bash
aws apigatewayv2 update-stage --api-id <API_ID> --stage-name lab \
  --default-route-settings ThrottlingRateLimit=10,ThrottlingBurstLimit=20
# Al terminar:
aws apigatewayv2 update-stage --api-id <API_ID> --stage-name lab \
  --default-route-settings ThrottlingRateLimit=1000,ThrottlingBurstLimit=5000
```

Los valores son un punto de partida: si en la Pregunta 3 propuso otros, use los suyos y justifíquelos frente al tráfico que genera la tormenta.

**Para cada configuración:**

1. Prepare el sistema, arranque el generador de tráfico y anote el total de filas del Outbox (`PENDING + DELIVERED + FAILED` de `GET $BASE_URL/ventas/outbox/resumen`) y el contador `llamadasDisponibilidad`.
2. Pasados 2 minutos, inyecte la latencia en Inventario y, de inmediato, lance la tormenta en otra terminal (T_inj):
   ```bash
   curl -s -X POST $BASE_URL/inventario/chaos -H 'Content-Type: application/json' \
     -d '{"mode": "latency", "delayMs": 5000, "durationMs": 150000}'
   BASE_URL=$BASE_URL CLIENTES=50 DURACION=120 ./lab_5/recursos/tormenta_reintentos.sh e6_sin_sidecar.csv
   ```
   Para la configuración opcional con backoff, agregue `BACKOFF=1` al comando de la tormenta.
3. La tormenta termina sola a los 120 s e imprime un resumen (pedidos, intentos por pedido, peticiones abandonadas, 429). El fallo de Inventario se retira a los 150 s (T_rem). Observe 3 minutos más.
4. Vuelva a leer el total de filas del Outbox y el contador, y detenga el generador de tráfico.

**Qué observar:**

- ¿Cuántos intentos por pedido necesitaron las apps defectuosas en cada configuración, y cuántos pedidos lograron completar?
- ¿Cuántas llamadas recibió Inventario por cada pedido lógico? Compárelo con E1, que tenía el mismo fallo pero sin tormenta.
- ¿Cuántas ventas se registraron frente a los pedidos que realmente se hicieron? ¿De dónde salen las ventas sobrantes y qué significan para un tendero?
- ¿Qué le pasó a la disponibilidad de las ventas del generador de tráfico, los otros tenderos, en cada configuración? ¿Recibieron 429?
- Con throttling, ¿qué hicieron las apps defectuosas al recibir 429? ¿El throttling apagó la tormenta o solo la contuvo en el borde?
- Con la configuración completa, ¿por qué la tormenta se apaga sola? ¿Qué táctica rompe el ciclo de reintentos?

### 6.11 Cómo leer los resultados

Para cada experimento, la pieza central del análisis es la **línea de tiempo**: la disponibilidad percibida y el % de `pending` de las ventas por ventana de 10 s, con T_inj y T_rem marcados. Sobre ella se leen el estado estable, la desviación, el TTD y el TTR. Compare:

- **Entre configuraciones** del mismo experimento (E1, E2, E6): el efecto de una táctica es la diferencia con la configuración que no la tiene. Por ejemplo, el efecto del circuit breaker es la diferencia entre *solo reintentos* y *completa*.
- **Contra la ficha**: ¿el radio de impacto y los tiempos fueron los que predijo? Lo que no predijo es tan importante como lo que sí.
- **Contra los ASRs**: use las medidas de respuesta de la sección 4.2 tal como están escritas (por ventana, después de los primeros 30 s, etc.).

> [!IMPORTANT]
> **Pregunta 6:**
> En los Labs 2 a 4 usted validó la arquitectura con pruebas de carga. Con base en sus resultados de este laboratorio, ¿qué demostró este experimento que una prueba de carga no habría podido demostrar? Y al revés: ¿qué riesgo de disponibilidad de Cheapest solo se descubre con una prueba de carga? Dé al menos un ejemplo concreto de cada lado, tomado de sus datos o de los laboratorios anteriores, y concluya cuándo usaría cada tipo de experimento.

## 7. Entregables

Entregue un informe organizado con los siguientes numerales.

### 7.1 Resultados

#### 7.1.1 Fichas de los experimentos

Las siete fichas (E0 a E6), con todos los campos de la sección 4.4.3, **tal como las escribió antes de ejecutar cada experimento**. Si cambió algo del diseño después de ejecutarlo (por ejemplo, la duración del fallo), deje la versión original y agregue al final de la ficha qué cambió y por qué.

#### 7.1.2 ¿Qué se observó?

Describa, sin interpretar todavía, lo que observó en cada experimento y configuración: cómo se comportó el estado estable antes, durante y después del fallo, qué endpoints se afectaron y qué mostraron los logs del sidecar, los eventos de ECS y el Outbox.

#### 7.1.3 ¿Qué métricas se obtuvieron?

**a. Línea de tiempo por experimento.** Una gráfica por experimento y configuración con la disponibilidad percibida y el % de `pending` de las ventas por ventana de 10 s, con T_inj y T_rem marcados (a partir de `*_ventanas.csv`).

**b. Tabla resumen de E0 a E5:**

| Experimento | Configuración | Disponibilidad mínima por ventana (tras 30 s) | p99 máximo por ventana (ms) | % de `pending` durante el fallo | TTD (s) | TTR (s) | Llamadas por venta / factor de amplificación | Endpoints afectados |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| E0 | Completa | | | | N/A | N/A | | |
| E1 | Sin sidecar | | | | | | | |
| E1 | Solo reintentos | | | | | | | |
| E1 | Completa | | | | | | | |
| E2 (30 % / 100 %) | Sin sidecar | | | | | | | |
| E2 (30 % / 100 %) | Solo reintentos | | | | | | | |
| E2 (30 % / 100 %) | Completa | | | | | | | |
| E3 | Completa | | | | | | | |
| E4 Parte 1 | Completa | | | | | | | |
| E5 | Completa | | | | | | | |

**c. Descomposición del MTTR de E3 (y de E4, Parte 1):**

| Etapa | Hora (UTC) | Segundos desde T_inj | Fuente |
| --- | --- | ---: | --- |
| Tarea detenida (T_inj) | | 0 | |
| Tarea nueva iniciada | | | |
| Target registrado en el target group | | | |
| Target `healthy` | | | |
| Primer `GET /health` 200 (T_rec) | | | |
| Ventas de vuelta al estado estable | | | |

**d. Consistencia (E3 y E4, Parte 2):**

| Prueba | Filas PENDING máximas | Desde T_rec hasta 0 PENDING (s) | Filas FAILED | Δ cantidad del ítem | Ventas 201 del generador de tráfico | Descuentos duplicados |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| E3 Parte 1 — sin clave (2 envíos) | N/A | N/A | N/A | | N/A | |
| E3 Parte 1 — con clave (2 envíos) | N/A | N/A | N/A | | N/A | |
| E3 Parte 2 — caída de Inventario | | | | | | |
| E4 Parte 2 — reinicio de Ventas | | | | N/A | N/A | N/A |

**e. E6 (tormenta de reintentos):**

| Configuración | Intentos por pedido | Pedidos completados / pedidos lógicos | Llamadas a Inventario por pedido | Ventas registradas | Pedidos duplicados | Disponibilidad del generador de tráfico (mínima por ventana tras 30 s) | 429 (tormenta / generador) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Sin sidecar | | | | | | | N/A |
| Sin sidecar + throttling del stage (rate / burst: …) | | | | | | | |
| Completa | | | | | | | N/A |
| (Opcional) Sin sidecar, clientes con backoff | | | | | | | N/A |

Reporte también los seis valores que escogió en `envoy.yaml.tmpl`.

### 7.2 Análisis de resultados

Extensión sugerida para los numerales 7.2 a 7.4 juntos: 3 a 5 páginas, sin contar tablas, gráficas ni capturas. Las respuestas a las preguntas orientadoras (7.5) no cuentan en ese límite. Donde un punto de 7.2 a 7.4 se cruza con una pregunta orientadora, se indica cuál; respóndalo una sola vez y en el otro lugar haga referencia.

#### 7.2.1 ¿Qué significan los datos frente al escenario de calidad?

Para cada ASR, compare lo medido con su medida de respuesta e indique si se cumple:

- **ASR-1** (con Inventario lento o con errores, disponibilidad ≥ 99 % por ventana tras 30 s, p99 < 3000 ms, y CLOSED a más tardar 60 s después del retiro del fallo). ¿Qué configuración lo cumple en E1 y en E2? ¿Qué diferencia operativa tiene para un tendero recibir una respuesta lenta, un error o `pending_stock_confirmation`? ¿Bajo qué condiciones la degradación es aceptable para el negocio?
- **ASR-2** (factor de amplificación ≤ 2). ¿Por qué el reintento sin backoff ni jitter puede empeorar una situación de fallo? ¿En qué fase de E2 los reintentos ayudaron y en cuál solo amplificaron? Relacione la respuesta con el escenario de Cheapest (tenderos reintentando pedidos en el pico del lunes).
- **ASR-3** (durante la tormenta, ≤ 2 intentos por pedido tras 30 s y el generador de tráfico cumple el ASR-1). ¿Qué configuración apaga la tormenta y cuál solo la contiene? ¿Por qué el throttling del stage protege al backend pero no a los demás tenderos? ¿Qué parte del problema solo se resuelve en el cliente (backoff, respetar un 429) y qué parte en el servidor? ¿Qué haría falta para que los pedidos que el cliente reintenta no se registren dos veces?
- **ASR-4** (reconciliación en < 30 s desde T_rec, sin duplicados, y las entregas pendientes sobreviven al reinicio de Ventas). ¿Qué mecanismo garantiza cada una de las tres partes? Si alguna fila quedó en FAILED, ¿qué significa para el negocio y quién debería atenderla?
- **ASR-5** (MTTR ≤ 5 min ante la caída de la tarea de Inventario). ¿Qué etapa dominó el MTTR? ¿Qué parámetros del template la acortarían, y a qué costo?
- **Paso de OPEN a HALF-OPEN.** Con los tiempos que midió en E1 y E2 (cuándo se abrió el circuito, cada cuánto hubo peticiones de prueba y cuánto tardó en volver a CLOSED después de T_rem), ¿cuánto tiempo debería permanecer el circuito en OPEN antes de pasar a HALF-OPEN (`base_ejection_time`)? ¿Qué riesgos hay en pasar a HALF-OPEN demasiado pronto frente a demasiado tarde? Aquí se analiza lo que midió; la justificación del valor que configuró va en la Pregunta 3, parte B.
- **Experimentos exploratorios (E4 y E5).** ¿Qué descubrió que no estaba en ningún ASR? Esto es insumo de la Pregunta 4; aquí describa el hallazgo y en la pregunta desarrolle la capacidad que haría falta.

#### 7.2.2 ¿Se cumple la hipótesis?

Para la hipótesis de **cada ficha** (E0 a E6) indique si se cumple, se cumple parcialmente o no se cumple, y con qué dato lo sustenta. Si una hipótesis se refutó, explique qué suposición de su ficha resultó equivocada. Una hipótesis refutada con un buen análisis vale tanto como una confirmada.

### 7.3 Conclusión

#### 7.3.1 ¿Qué se aprendió del experimento?

Más allá de si cada táctica funcionó, reflexione sobre:

- ¿Cómo se complementaron los reintentos y el circuit breaker en sus datos (compare *solo reintentos* con *completa* en E1 y E2)? El escenario de conflicto entre ambos se pide en la Pregunta 3, parte A; aquí no lo repita.
- ¿Por qué "entrega al menos una vez" más idempotencia no equivale a una garantía distribuida de "exactamente una vez"? ¿Qué requeriría una garantía real de exactamente una vez entre dos servicios con bases de datos independientes?
- ¿Qué ventajas concretas tuvo desplegar con CloudFormation frente a la configuración manual del Lab 4? ¿En qué escenarios del negocio de Cheapest (por ejemplo, la expansión a México o Brasil, o un incidente que obligue a reconstruir el ambiente) sería crítica esta capacidad?

La comparación entre experimentos de caos y pruebas de carga se pide en la Pregunta 6; aquí no la repita.

### 7.4 Decisión arquitectónica

#### 7.4.1 ¿Qué se decide?

Para cada táctica (reintentos con backoff y jitter, circuit breaker con graceful degradation, rate limiting en API Gateway, Outbox con idempotencia, y detección y recuperación automática con health checks de ECS) indique si la **adopta, la modifica o la descarta** para Cheapest, y con qué parámetros. Incluya en su decisión:

- En este laboratorio las tácticas de resiliencia se implementaron en un sidecar y no en el código de negocio. ¿Qué ventajas concretas tuvo este enfoque? Con lo que observó en E4, ¿qué costo de disponibilidad tiene? ¿En qué escenarios el sidecar no sería suficiente y se necesitaría lógica de resiliencia dentro de la aplicación?
- Con lo que observó en E3 y E5: ¿cuántas tareas debería tener cada servicio, qué debería revisar el endpoint `/health` y con qué frecuencia debería consultarlo el balanceador?

#### 7.4.2 ¿Qué cambios se hacen a la arquitectura?

- Describa los cambios que quedan en la arquitectura de Cheapest después del experimento: qué componentes nuevos se agregan, con qué configuración y qué reglas de negocio hay que acordar (por ejemplo, cuánto tiempo puede quedar un pedido como pendiente de confirmación de stock, o qué se hace con una venta degradada cuyo descuento queda en FAILED por falta de stock).
- Lea el artículo [Failure Mitigation for Microservices: An Intro to Aperture](https://careersatdoordash.com/blog/failure-mitigation-for-microservices-an-intro-to-aperture/) de DoorDash. ¿Qué problema específico resuelve Aperture que el sidecar Envoy de este laboratorio no resuelve? ¿En qué punto del crecimiento de Cheapest tendría sentido adoptar un enfoque centralizado como ese? Si en la Pregunta 4 propuso una capa de este tipo como capacidad adicional, desarróllela aquí y en la Pregunta 4 solo haga referencia.

### 7.5 Respuestas a las preguntas orientadoras

Incluya las respuestas argumentadas a las preguntas planteadas a lo largo del laboratorio. Cada respuesta debe incluir los elementos que pide la pregunta (tablas, gráficas o diagramas) y debe ir más allá de lo superficial. Se repiten aquí para que no tenga que buscarlas:

- **Pregunta 1.** En Cheapest, ¿qué decisión de producto y operación debería tomarse primero cuando aparece una avalancha de reintentos: proteger la disponibilidad percibida (graceful degradation) o proteger la consistencia estricta (rechazar operaciones)? Argumente considerando el impacto en tenderos, el riesgo financiero y el costo de reconciliación posterior.
- **Pregunta 2.** Si usted fuera el líder encargado de llevar estas tácticas a producción en Cheapest, ¿las adoptaría en el mismo orden en que se presentan (reintentos, circuit breaker, rate limiting, Outbox e idempotencia), teniendo en cuenta el riesgo de cada cambio? Describa un plan de migración que mitigue los riesgos, con etapas, tiempo estimado por etapa y tareas de cada una.
- **Pregunta 3 (partes A y B, se responden y califican juntas).** Parte A: los reintentos, el circuit breaker y el rate limiting pueden entrar en conflicto si se calibran mal. Proponga un conjunto coherente de parámetros iniciales para Cheapest (timeouts, reintentos, umbral de apertura, tiempo de reapertura, rate y burst) y justifique cómo evitaría inestabilidad sistémica. Incluya un escenario concreto en el que usar reintentos y circuit breaker juntos sin coordinación generaría un problema. Parte B: documente los valores que finalmente eligió para cada `TODO` de `envoy.yaml.tmpl`, la justificación cuantitativa de cada uno y cómo garantiza que no violan el ASR-2 (factor de amplificación ≤ 2) ni el p99 del ASR-1.
- **Pregunta 4.** Con base en lo que observó en E4 y E5, ¿qué riesgo residual seguiría existiendo para una operación real de Cheapest a mayor escala, aun si las tácticas del laboratorio cumplen sus ASRs? Identifique al menos dos clases de fallos que estas tácticas no resuelven por sí solas, sustentadas con sus datos, y qué capacidad adicional haría falta. Si esa capacidad es una capa centralizada como Aperture, la comparación se desarrolla en 7.4.2.
- **Pregunta 5.** Describa con precisión el estado de inconsistencia que se produce en cada escenario de E3: (1) ventas registradas durante la caída de Inventario: ¿qué diferencia hay entre lo que dice la tabla `ventas` y lo que dice `items_inventario.cantidad`?; (2) reintento sin idempotencia: ¿qué invariante de negocio se viola y cómo lo detectaría operacionalmente en Cheapest?
- **Pregunta 6.** ¿Qué demostró este experimento que una prueba de carga no habría podido demostrar? Y al revés: ¿qué riesgo de disponibilidad de Cheapest solo se descubre con una prueba de carga? Dé al menos un ejemplo concreto de cada lado y concluya cuándo usaría cada tipo de experimento.
- **Pregunta 7.** ¿Aprobaría repetir el E3 en producción un lunes por la mañana? Si lo aprueba, defina cómo limitaría el radio de impacto, qué condiciones de aborto usaría y con qué umbrales, quién debe estar presente y cómo revertiría. Si no lo aprueba, explique qué tendría que cambiar en la arquitectura para que fuera aceptable.
- **Revisión de la escritura transaccional en `VentaService`.** ¿Qué ocurre si el proceso muere entre el guardado de la venta y el guardado de su fila de Outbox? ¿Por qué la fila de Outbox se crea incluso cuando la venta se registra con graceful degradation? ¿Qué datos lleva la fila de Outbox y son suficientes para lo que necesita `POST /inventory/ventas/desde-outbox`?
- **Revisión del endpoint con idempotencia en Inventario.** ¿Qué ocurre si el proceso de Inventario muere entre el descuento de stock y el guardado de la clave procesada? ¿Puede producirse un descuento sin clave registrada? ¿Por qué se usa como clave de idempotencia el `id` de la fila de Outbox y no el `ventaId`?

### 7.6 Evidencias

Adjunte capturas de:

- Stack CloudFormation en estado `CREATE_COMPLETE`.
- Actividad post-despliegue: los dos recursos del stack que eligió al explorar lo que se desplegó, con una captura de la consola por cada uno y su explicación.
- Task Definition de Ventas mostrando los **dos containers**: `ventas` y `ventas-sidecar`, y la revisión sin sidecar con un solo container.
- Servicios ECS de los tres microservicios en estado RUNNING.
- `envoy.yaml.tmpl` con los valores completados por el estudiante (los seis `TODO`).
- Respuesta del endpoint de caos al inyectar un fallo (con `injectedAt` y `until`) y al leer el contador `llamadasDisponibilidad`.
- Resultado de la consulta de Logs Insights de la sección 5.9 sobre el grupo `/ecs/Cheapest-ventas-sidecar` para E1 o E2 con *solo reintentos* (respuestas `UT`/`URX`, sin `UH`) y con la configuración *completa* (intervalos con `503 UH`, circuito OPEN, y regreso a `200 -` tras la recuperación).
- Eventos del servicio `svc-Cheapest-inventario` durante E3 y gráfica de `HealthyHostCount`/`UnHealthyHostCount` de su target group.
- Registro de E3 (`e3_outbox.log`) mostrando las filas PENDING acumulándose y bajando a 0 tras T_rec, y la cantidad del ítem antes y después.
- Respuestas de E3 Parte 1: la cantidad bajando dos veces sin clave, y el HTTP 409 al repetir con la misma `X-Idempotency-Key`.
- Eventos del servicio `svc-Cheapest-ventas` durante E4 (tarea reemplazada al apagar el sidecar) y el resumen del Outbox antes y después del reinicio de Ventas.
- Estados de la instancia RDS durante E5 y la tabla de `ventanas.py` de ese experimento.
- Configuración de throttling del stage en API Gateway y el resumen de `tormenta_reintentos.sh` de cada configuración de E6 (con las respuestas 429 cuando aplique).

Adjunte también:

- Los CSV del generador de tráfico y de la tormenta de cada experimento (o un enlace a ellos).
- Los prompts utilizados (si usó IA).
- Los scripts adicionales que haya escrito (si aplica).

### 7.7 Formato de entrega

Un informe en PDF o Word con los numerales de resultados (incluidas las fichas), análisis de resultados, conclusión, decisión arquitectónica, respuestas a las preguntas orientadoras y evidencias.

> [!IMPORTANT]
> **¿A dónde se suben los entregables?**
> A la Actividad correspondiente en el aula de Bloque Neón de su sección.

## Nota final (créditos AWS)

Cuando termine el laboratorio, elimine todos los recursos para evitar consumo innecesario de créditos:

```bash
aws cloudformation delete-stack --stack-name Cheapest-lab5 --region us-east-1
```

Verifique en la consola que el stack pase a estado `DELETE_COMPLETE` y que no queden recursos huérfanos (especialmente instancias RDS e imágenes en ECR).
