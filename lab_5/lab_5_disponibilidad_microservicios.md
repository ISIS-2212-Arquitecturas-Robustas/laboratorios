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
| 3. Fase local: ambiente y sidecar          | Ambiente completo en su computador con Docker Compose, configuración del sidecar (el proxy Envoy) en Ventas y reconocimiento de las herramientas para inyectar fallos. | Recomendado para soporte de implementación, revisión de parámetros y pruebas; validar manualmente resultados. |
| 4. Fase local: experimentos de caos        | Ejecución de los tres experimentos en local, con todas las configuraciones: estado estable, tormenta de reintentos y caída de Inventario, comparadas contra un grupo de control sin protecciones, más la demostración de Outbox e idempotencia. | No recomendado para redactar conclusiones sin evidencia empírica del laboratorio.                         |
| 5. Fase AWS: infraestructura con IaC       | Despliegue reproducible en AWS a partir de un archivo que describe toda la infraestructura (infraestructura como código, con CloudFormation) y verificación del despliegue. | Recomendado para asistir en comandos y troubleshooting de despliegue.                                     |
| 6. Fase AWS: confirmación de los experimentos | Repetición de los experimentos en AWS con las configuraciones que solo existen allí (throttling de API Gateway, reemplazo de tareas de ECS), medición del tiempo de recuperación y comparación de los resultados con la fase local. | No recomendado para redactar conclusiones sin evidencia empírica del laboratorio.                         |

## 3. Objetivos

- Entender que **no todo experimento de arquitectura es una prueba de carga**: para el atributo de disponibilidad, la variable que se manipula es el **fallo**, no la carga.
- Diseñar y ejecutar **experimentos de ingeniería del caos**: definir el estado estable del sistema, formular una hipótesis, inyectar un fallo controlado, limitar su radio de impacto y observar si el sistema se desvía y cómo se recupera.
- Medir los **tiempos de detección y de recuperación** (TTD, TTR y MTTR) de cada mecanismo de resiliencia: circuit breaker, reemplazo automático de tareas de ECS y reconciliación del Outbox.
- Implementar tres tácticas de resiliencia a nivel de infraestructura: reintentos con espera creciente entre intentos (*retry* con *backoff* exponencial), corte de llamadas a un servicio caído con *graceful degradation* (*circuit breaker*) y límite de peticiones por segundo (*rate limiting*).
- Ensayar los experimentos en un ambiente local antes de llevarlos a la nube, y distinguir qué resultados se sostienen en AWS y cuáles dependen del ambiente.
- Desplegar la infraestructura del laboratorio usando Infraestructura como Código (describir la infraestructura en un archivo, en lugar de crearla a mano) con AWS CloudFormation.
- Demostrar que la resiliencia de infraestructura (circuit breaker, retry) no garantiza consistencia de datos, y verificar que los patrones **Outbox** e **Idempotencia** cierran esa brecha.
- Identificar los puntos de fallo que ninguna de estas tácticas cubre (el propio sidecar y la base de datos compartida), diseñar el experimento que los probaría y reflexionar sobre las limitaciones de las tácticas locales frente a enfoques de resiliencia distribuida centralizada.

## 4. Planeación del laboratorio

En el Lab 4 usted desplegó Cheapest como tres microservicios (Logística, Inventario y Ventas) y midió su escalabilidad con pruebas de carga: la pregunta era *¿cuánta carga aguanta?*. En este laboratorio la pregunta es otra: **¿qué pasa cuando algo falla?** Los servicios fallan aunque la carga sea baja: una tarea se reinicia, una dependencia se pone lenta, la base de datos se reinicia por mantenimiento. Para estudiar eso no sirve subir la carga; hay que **provocar el fallo de forma controlada** y observar al sistema mientras lo sufre.

Para eso se introduce explícitamente una dependencia HTTP entre servicios: **Ventas llama a Inventario** para verificar que hay stock antes de registrar una venta. Esta dependencia es el punto de fallo que se va a explorar: **si Inventario se degrada, sin protecciones Ventas también falla.**

**Contexto de negocio.**

Los lunes por la mañana, los tenderos de Cheapest realizan sus reabastecimientos semanales. En estos picos, el servicio de **Inventario**, que valida disponibilidad de stock antes de confirmar un pedido, recibe una carga muy superior a la normal y se degrada. Sin protecciones, el servicio de **Ventas** (que depende de Inventario) empieza a fallar en cadena: los tenderos no pueden confirmar pedidos, la app de los tenderos reintenta automáticamente, y ese volumen de reintentos amplifica la carga sobre un servicio ya degradado. El resultado: un sistema que se colapsa a sí mismo.

Este escenario es conocido en la industria como **retry storm** (tormenta de reintentos) y es uno de los patrones de fallo descritos en el artículo [Failure Mitigation for Microservices: An Intro to Aperture](https://careersatdoordash.com/blog/failure-mitigation-for-microservices-an-intro-to-aperture/) de DoorDash. Uno de los experimentos de este laboratorio la reproduce a propósito: pone lento a Inventario mientras un grupo de instancias de la app reintenta sus pedidos sin esperar entre un intento y otro, y mide si las tácticas logran apagar la tormenta.

El equipo de Cheapest no quiere esperar al próximo lunes para saber si sus tácticas funcionan. Va a hacer lo que hacen los equipos que operan sistemas en producción: un ***game day***, una sesión planeada en la que se le inyectan fallos al sistema a propósito, con tráfico bajo y controlado, para comprobar que se comporta como se diseñó **antes** de que el fallo ocurra de verdad. Esa práctica se llama **ingeniería del caos** (*chaos engineering*), y la popularizó Netflix con Chaos Monkey, una herramienta que apagaba al azar servidores de producción para obligar a los equipos a diseñar servicios que toleraran esas caídas.

Como hacen esos equipos, el *game day* se ensaya primero en un ambiente que no cuesta nada romper: **usted corre todos los experimentos primero en su computador, con Docker Compose**, y solo después los confirma en AWS. La fase local es donde se prueban las configuraciones, se afinan las fichas y se cometen los errores; la fase AWS mide lo que solo existe en la nube (el reemplazo automático de tareas de ECS, el límite de peticiones de API Gateway, la latencia real de red) y consume créditos solo el tiempo necesario.

> [!IMPORTANT]
> **Pregunta 1:**
> En Cheapest, ¿qué decisión de producto y operación debería tomarse primero cuando aparece un retry storm: proteger disponibilidad percibida (graceful degradation) o proteger consistencia estricta (rechazar operaciones)?
> Argumente su respuesta considerando impacto en tenderos, riesgo financiero y costo de reconciliación posterior.

Un aspecto crítico de este escenario es que el fallo suele ser **transitorio**: un servicio degradado por un pico de memoria, un pool de conexiones agotado o un spike de CPU puede recuperarse por sí solo en segundos o minutos, y los orquestadores como ECS reemplazan automáticamente las tareas que dejan de responder. Por eso en este laboratorio los fallos de Inventario se inyectan con una **duración**: al cumplirse, el fallo se retira solo. Esto hace que el estado **HALF-OPEN** del circuit breaker no sea solo teórico: cuando Inventario se recupera, el circuit breaker lo detecta y vuelve al estado CLOSED, restaurando el flujo normal sin intervención humana. Medir **cuánto tarda** cada mecanismo en detectar el fallo y en volver a la normalidad es una de las metas del laboratorio.

**Conceptos nuevos de este laboratorio.** Se usan desde las hipótesis y los escenarios de calidad; los patrones de resiliencia se explican con más detalle, y con su aplicación en Cheapest, en la parte de tácticas y patrones.

| Concepto | Qué es |
| --- | --- |
| Ingeniería del caos y *game day* | Experimentar sobre un sistema inyectándole fallos controlados para ganar confianza en su capacidad de soportar condiciones adversas. Un *game day* es la sesión planeada en la que un equipo ejecuta esos experimentos; este laboratorio es uno. |
| Radio de impacto (*blast radius*) | Qué partes del sistema (servicios, endpoints, usuarios) resultan afectadas por un fallo. Se predice antes del experimento y se mide durante. |
| Condición de aborto | Criterio, definido antes de empezar, que obliga a detener el experimento y revertir el fallo (por ejemplo, "si la disponibilidad de las ventas cae por debajo de X durante más de Y segundos"). En producción es lo que impide que un experimento se convierta en un incidente. |
| TTD, TTR y MTTR | *Time to detect*: tiempo entre la inyección del fallo y el momento en que un mecanismo lo detecta. *Time to recover*: tiempo hasta que el sistema vuelve al estado estable. El MTTR (*mean time to recover*) es el promedio de varios TTR. |
| *Backoff* exponencial y *jitter* | Esperar cada vez más entre un reintento y el siguiente (por ejemplo 0,1 s, 0,2 s, 0,4 s...), sumándole una variación aleatoria (*jitter*) para que los clientes no reintenten todos en el mismo instante. Reintentar sin backoff es lo que forma una tormenta de reintentos. |
| *Circuit breaker* | Mecanismo que, al detectar que un servicio falla repetidamente, deja de enviarle peticiones por un tiempo y responde de inmediato con un error. Tiene tres estados: CLOSED (el tráfico pasa), OPEN (el tráfico se corta) y HALF-OPEN (deja pasar tráfico de prueba para ver si el servicio se recuperó). |
| *Graceful degradation* | Cuando una dependencia no está disponible, responder algo útil aunque incompleto en lugar de un error. Aquí, Ventas registra el pedido sin verificar el stock y lo marca como pendiente. |
| *Rate limiting* (o *throttling*) | Limitar cuántas peticiones por segundo se aceptan; las que exceden el límite se rechazan con HTTP 429. Se configura con un *rate* (peticiones por segundo sostenidas) y un *burst* (cuántas se aceptan de golpe por encima de ese ritmo, para absorber picos cortos). |
| Sidecar (Envoy) | Contenedor auxiliar que se despliega junto al de un servicio, en la misma tarea de ECS, y se encarga de asuntos transversales sin tocar el código del servicio. Aquí es Envoy, un proxy de código abierto que aplica los reintentos y el circuit breaker a las llamadas de Ventas a Inventario. |
| Outbox e idempotencia | **Outbox:** la operación que hay que enviarle a otro servicio se guarda primero en una tabla local, en la misma transacción que el dato de negocio, y un proceso aparte la envía hasta que logra entregarla. **Idempotencia:** una operación repetida produce el mismo resultado que una sola; se logra con una clave que le permite al receptor reconocer lo que ya procesó. |

> [!NOTE]
> **Nombres:** En el código se usan los nombres de las entidades (`OutboxHttpCall`, `ProcessedCall`) y en SQL los de las tablas (`outbox_http_calls`, `processed_calls`, `items_inventario`). Las columnas están en *camelCase* y en SQL van entre comillas dobles (`"createdAt"`).

### 4.1 Hipótesis de diseño

En este laboratorio **usted escribe las hipótesis: una por cada experimento**. El laboratorio tiene tres experimentos (la medición del estado estable, la tormenta de reintentos y la caída de Inventario, que se describen en el catálogo de experimentos más abajo), así que usted escribe tres hipótesis. Cada una va en la **ficha** de su experimento (un formato corto en el que usted documenta el diseño del experimento antes de correrlo: estado estable, hipótesis, fallo, radio de impacto, condición de aborto, métricas y reversión; sus campos se detallan en el diseño del experimento) y se redacta **antes** de ejecutarlo, sin mirar los resultados. Una hipótesis de caos afirma qué le pasa al **estado estable** (el comportamiento normal del sistema, medido aquí con la disponibilidad y la latencia de las ventas) cuando se inyecta un fallo, y por qué:

> **Si** inyectamos *[fallo concreto, dónde y por cuánto tiempo]* con *[configuración de tácticas]*, **entonces** *[métrica del estado estable]* *[se mantiene / se degrada a lo sumo hasta …]* y vuelve al estado estable en *[TTR esperado]*, **porque** *[mecanismo de la táctica que lo explica]*.

Ejemplo de **forma** (sobre un sistema distinto al del laboratorio): *"Si apagamos una de las dos réplicas del servicio de pagos durante 2 minutos, entonces la tasa de pagos exitosos se mantiene por encima del 99 % y la latencia p99 sube a lo sumo a 800 ms, porque el balanceador deja de enviar tráfico a la réplica caída tras dos health checks fallidos."*

Cada experimento se corre dos veces, primero en local y después en AWS. Por eso cada ficha tiene, además de la hipótesis, una **predicción para AWS**: después de ver el resultado local, y antes de correr el experimento en AWS, usted escribe qué espera que cambie en la nube y por qué. No es copiar el resultado local: es razonar qué tiene AWS que el local no tiene.

Una hipótesis refutada **no** es un mal resultado: es exactamente lo que un experimento de caos busca descubrir antes que los usuarios. Se califica el rigor del diseño y la honestidad del análisis, no que la hipótesis se cumpla.

### 4.2 Escenarios de calidad vinculados

Todas las medidas se toman con **tráfico de estado estable**, **no** con una prueba de carga: un script del laboratorio, el generador de tráfico, envía 2 ventas por segundo de forma constante durante todo el experimento, sin bajar la tasa aunque el sistema se ponga lento. Una respuesta **útil** es una respuesta 2xx (incluidas las 201 con `pending_stock_confirmation`, que es como Ventas marca un pedido registrado sin verificar el stock) que llega en menos de 3 s; la **disponibilidad percibida** de una ventana de 10 s es el porcentaje de respuestas útiles en esa ventana. Los ASRs se verifican con los datos de **AWS**; los de la fase local sirven para anticipar el resultado y para lo que en AWS no se puede medir (se indica en cada caso).

| ASR | Estímulo | Fuente del estímulo | Entorno | Artefacto | Respuesta | Medida de respuesta |
| ----- | -------- | ------------------- | ------- | --------- | --------- | ------------------- |
| **Degradación** | Inventario responde muy lento o deja de responder en la consulta de disponibilidad. | Servicio de Inventario, del cual depende Ventas. | Operación normal con tráfico de estado estable. | Servicio de Ventas (endpoint `POST /ventas/ventas`). | Ventas registra el pedido con graceful degradation en lugar de propagar la lentitud o el error, y vuelve a la operación normal cuando Inventario se recupera. | Pasados los primeros 30 s desde la inyección, la disponibilidad percibida de `POST /ventas/ventas` es ≥ 99 % en **cada** ventana de 10 s, con p99 < 3000 ms. El circuito vuelve a CLOSED (ventas confirmadas sin `pending`) a más tardar 60 s después de que el fallo se retira. |
| **Tormenta de reintentos** | Mientras Inventario está lento, 50 instancias de la app reintentan de inmediato, sin backoff, cada pedido que no responde en 3 s. | Una versión de la app de tenderos con un bug en su política de reintentos. | Inventario degradado, con tráfico de estado estable de los demás tenderos. | API Gateway, sidecar de Ventas, servicio de Ventas (`POST /ventas/ventas`) y servicio de Inventario. | La tormenta no se sostiene: las tácticas cortan el ciclo de reintentos, no amplifican la carga sobre Inventario y los demás tenderos siguen confirmando pedidos. | Pasados los primeros 30 s de la tormenta: las apps defectuosas necesitan en promedio ≤ 2 intentos por pedido; Inventario recibe ≤ 2 consultas de disponibilidad por cada pedido que hicieron los tenderos; y la disponibilidad percibida de las ventas del generador de tráfico cumple la medida del ASR de degradación. |
| **Consistencia** | Inventario se cae por completo y luego vuelve, después de que se registraron ventas con graceful degradation. | Caída y reemplazo de la tarea de Inventario. | Transición de graceful degradation a operación normal. | Mecanismo de Outbox (Ventas) + endpoint de idempotencia (Inventario). | Toda venta registrada con graceful degradation entrega su decremento de stock exactamente una vez, aunque Ventas se reinicie mientras hay entregas pendientes. | Contadas desde que Inventario vuelve a responder `/health` (T_rec), todas las filas de `outbox_http_calls` en PENDING pasan a DELIVERED en < 30 s; ningún `items_inventario.cantidad` refleja decrementos duplicados, y las filas PENDING sobreviven a un reinicio de Ventas (esto último se verifica en la fase local). |
| **Recuperación** | La tarea de Inventario se detiene abruptamente. | Fallo del proceso o de la máquina que lo ejecuta. | Operación normal con tráfico de estado estable. | Servicio ECS de Inventario, su balanceador y el servicio de Ventas. | ECS reemplaza la tarea sin intervención humana y, mientras tanto, Ventas sigue confirmando pedidos con graceful degradation. | MTTR ≤ 5 min, medido desde que la tarea se detiene hasta que `GET /inventario/health` vuelve a responder 200 y el target está `healthy`. Durante ese tiempo, la disponibilidad percibida de `POST /ventas/ventas` cumple la medida del ASR de degradación. Solo se mide en AWS: en local no hay un orquestador que reemplace el contenedor. |

Contexto de negocio de cada ASR (motivación, no parte de la especificación formal):

- **Degradación**: Como tendero, quiero poder confirmar un pedido incluso cuando el servicio de Inventario esté degradado. Un pedido con stock no confirmado es preferible a un error, o a una app que se queda pensando 10 segundos.
- **Tormenta de reintentos**: Como negocio, quiero que un bug en la política de reintentos de una versión de la app no convierta una degradación de Inventario en una caída total, no multiplique la carga sobre un servicio que ya está degradado, ni le quite capacidad a la confirmación de pedidos de los demás tenderos.
- **Consistencia**: Como negocio, quiero que toda venta registrada, incluso con graceful degradation (`pending_stock_confirmation`), tenga su decremento de stock entregado exactamente una vez cuando Inventario se recupere.
- **Recuperación**: Como negocio, quiero que la caída de una tarea se resuelva sola en minutos, sin que alguien de guardia tenga que intervenir un lunes a las 7 a. m.

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

**El sidecar también es un componente que puede fallar.** Al agregarlo, la tarea de Ventas pasa a tener dos contenedores, y en la configuración de AWS del laboratorio ambos están marcados como esenciales (`Essential: true`: si uno se detiene, ECS detiene la tarea completa). Qué le pasa a Ventas cuando el sidecar se cae no se prueba en los experimentos; usted lo analiza al final del laboratorio, cuando diseñe el experimento que lo probaría.

**Relación entre sidecar y graceful degradation**

El sidecar maneja la red (retry, circuit breaker). La graceful degradation —retornar `status: pending_stock_confirmation` en lugar de propagar el error— es una decisión de negocio que vive en el código de Ventas. El sidecar le comunica al servicio que Inventario está caído (mediante un 503 rápido en lugar de un timeout lento), y el servicio decide qué respuesta dar al cliente.

##### Circuit Breaker

Un **circuit breaker** es un control de fallos que corta el tráfico hacia un servicio cuando detecta errores persistentes. Evita que un servicio degradado reciba más carga y permite al cliente responder rápido con una salida controlada.

**Estados básicos**

- **CLOSED**: el circuito está cerrado y el tráfico fluye normalmente.
- **OPEN**: el circuito está abierto, el tráfico se corta inmediatamente y se devuelve un error o se aplica graceful degradation.
- **HALF-OPEN**: tras un tiempo de espera, el circuito vuelve a dejar pasar tráfico de prueba para verificar si el servicio se ha recuperado. Si ese tráfico tiene éxito, el circuito vuelve a CLOSED; si falla, vuelve a OPEN.

![Diagrama de estados del circuit breaker](./recursos/circuit_breaker.png)

**Cómo se ve en Cheapest**

- Ventas llama a Inventario a través del sidecar Envoy.
- Si Inventario empieza a fallar (timeouts o 5xx), Envoy cuenta los errores.
- Tras `consecutive_5xx` errores seguidos, abre el circuito (OPEN) y responde 503 inmediato.
- Ventas detecta el 503 y aplica graceful degradation.

**Por qué importa**

- Reduce el p99 de Ventas al evitar timeouts largos.
- Protege a Inventario de recibir más tráfico cuando ya está degradado.
- Permite detectar la recuperación automática de Inventario (HALF-OPEN) sin intervención humana.

**Riesgo si se calibra mal**

- Umbral demasiado bajo: el circuito abre con fallos transitorios y corta tráfico legítimo.
- Umbral demasiado alto: tarda en abrir y el sistema sigue colapsando en cascada.

##### Outbox e idempotencia

El circuit breaker y la graceful degradation mantienen a Ventas disponible, pero dejan un problema de datos: la venta quedó registrada y el stock de Inventario nunca se descontó. Dos patrones cierran esa brecha:

- **Outbox:** en la misma transacción en la que Ventas guarda la venta, guarda también una fila en una tabla local (`outbox_http_calls`, entidad `OutboxHttpCall`) que representa "hay que descontar este stock en Inventario". Un proceso en segundo plano lee esa tabla cada 2 segundos y envía la petición a Inventario hasta que logra entregarla. La garantía es de entrega **al menos una vez** (*at-least-once*).
- **Idempotencia:** como "al menos una vez" significa que la misma petición puede llegar repetida, Inventario recibe con cada petición una clave de idempotencia y guarda las claves que ya procesó. Si llega una clave repetida, no vuelve a descontar.

Juntos logran que cada venta descuente el stock exactamente una vez. Verá ambos patrones en detalle, sobre el código, en el experimento de caída de Inventario.

#### 4.3.2 Tácticas de arquitectura

| Táctica o patrón                            | Análisis                                                                                                                                                                                                                                                         |
| ------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Reintentos con backoff exponencial + jitter | Favorece la recuperación automática ante fallos transitorios.<br>Sin backoff ni jitter, los reintentos sincronizados pueden amplificar la carga (thundering herd), agravando el incidente en lugar de resolverlo.                                                |
| Circuit Breaker (CLOSED / OPEN / HALF-OPEN) | Favorece disponibilidad del servicio cliente al dejar de enviar requests a un servicio que ya está fallando.<br>Desfavorece consistencia inmediata: el estado OPEN implica que algunas operaciones retornan una respuesta de graceful degradation en lugar de resultados reales. |
| Graceful degradation (fallback)             | Favorece experiencia de usuario y continuidad operativa: el sistema sigue aceptando pedidos con graceful degradation en lugar de fallar completamente.<br>Introduce complejidad en la lógica de negocio para manejar el estado `pending_stock_confirmation`, y requiere acuerdos de negocio sobre qué se puede degradar sin romper la experiencia crítica del tendero. |
| Detección y recuperación automática (health checks + reemplazo de tareas de ECS) | Favorece la recuperación sin intervención humana: el balanceador deja de enviar tráfico a una tarea que no responde `/health` y ECS lanza una tarea nueva.<br>El tiempo de recuperación depende de la frecuencia de los health checks, del tiempo de arranque de la tarea y de cuántas réplicas hay; un `/health` que no revisa las dependencias (por ejemplo, la base de datos) puede reportar sana una tarea que no sirve. |
| Rate Limiting en el API Gateway (throttling) | El API Gateway es el punto de entrada de todas las peticiones, así que es el lugar natural para limitar cuántas se aceptan por segundo.<br>Favorece protección de servicios backend ante picos de tráfico y retry storms.<br>Puede afectar a usuarios legítimos si los límites no están bien calibrados o si no distinguen entre clientes o tipos de tráfico. |
| Control de recursos (*resource control*)    | Limitar concurrencia, throughput y consumo por cliente o por ruta (throttling, cuotas, aislamiento) favorece la estabilidad bajo carga.<br>Sin una buena calibración, puede rechazar tráfico legítimo y afectar temporalmente la percepción de disponibilidad. |
| Proxy sidecar (Envoy)                       | Externaliza responsabilidades transversales (aquí, retry y circuit breaker) a un proceso que corre junto al servicio, sin tocar el código de negocio.<br>El sidecar intercepta el tráfico saliente de Ventas hacia Inventario y aplica las políticas configuradas en su archivo YAML; se pueden cambiar sin redesplegar la aplicación.<br>Introduce un salto de red adicional, un componente más que puede fallar, y requiere que los parámetros del sidecar sean coherentes con los timeouts de la aplicación. |

##### Retries (reintentos)

Los **reintentos** permiten recuperar solicitudes ante fallos transitorios (timeouts cortos, reinicios, errores 5xx momentáneos). Para evitar sincronización masiva, se usan **backoff exponencial + jitter**.

**Flujo típico**

```
intento 1 -> falla
espera base_interval (+/- jitter)
intento 2 -> falla
espera min(2x, max_interval)
intento 3 -> exito o error final
```

**Cómo se ve en Cheapest**

- Envoy reintenta automáticamente cuando Inventario responde 5xx.
- El timeout total de la ruta debe cubrir el tiempo de reintentos.
- El número de reintentos debe respetar el ASR de tormenta de reintentos: Inventario no puede recibir más de 2 consultas por pedido.

**Por qué importa**

- Mejora disponibilidad cuando el fallo es breve o intermitente.
- Si el fallo es persistente, los retries solo amplifican carga y empeoran el incidente. En el experimento de tormenta de reintentos hay dos fuentes de reintentos a la vez: las del sidecar y las de la app de los tenderos.

##### Graceful Degradation

La **graceful degradation** es una decisión de negocio: el servicio devuelve una respuesta útil aunque parcial cuando un componente crítico no está disponible. No evita la falla, pero protege la experiencia del usuario.

**Cómo se ve en Cheapest**

- Si Inventario no responde, Ventas registra el pedido con `status: pending_stock_confirmation`.
- El tendero recibe confirmación de pedido, pero la verificación de stock queda diferida.

**Por qué importa**

- Mantiene la disponibilidad percibida (ASR de degradación) aun con Inventario degradado.
- Requiere reglas claras: qué significa "pendiente", cuánto tiempo puede estarlo, y cómo se reconcilia.

> [!IMPORTANT]
> **Pregunta 3 (parte A — propuesta de parámetros):**
> Retry, circuit breaker y rate limiting pueden entrar en conflicto si se calibran mal.
> Proponga un conjunto coherente de parámetros iniciales para Cheapest (timeouts, retries, umbral de apertura, reset timeout, rate y burst) y justifique cómo evitaría inestabilidad sistémica. Incluya un escenario concreto en el que usar reintentos y circuit breaker juntos sin coordinación generaría un problema.

### 4.4 Diseño del experimento

#### 4.4.1 ¿Por qué no es una prueba de carga?

En los laboratorios anteriores el experimento consistía en subir la carga y observar en qué punto el sistema dejaba de cumplir su ASR: la **variable independiente era la carga**. Para la disponibilidad, esa estrategia tiene dos problemas. Primero, los fallos que más afectan la disponibilidad (una tarea que se cae, una dependencia que se pone lenta, una base de datos que se reinicia) **no dependen de la carga**: ocurren igual a las 3 a. m. con un tendero conectado. Segundo, una prueba de carga mezcla dos causas: si el sistema falla, no se sabe si fue por el fallo o por la saturación.

Por eso en este laboratorio:

| | Prueba de carga (Labs 2-4) | Experimento de caos (este laboratorio) |
| --- | --- | --- |
| Variable que se manipula | Número de usuarios o peticiones por segundo | El fallo: qué componente falla, cómo y por cuánto tiempo |
| Carga | Creciente, hasta saturar | **Baja y constante** (2 ventas/s), igual en todos los experimentos. En el experimento de tormenta de reintentos se agrega el tráfico de la app defectuosa, pero ese tráfico es parte del fallo que se inyecta, no una carga que se sube por niveles |
| Pregunta | ¿Cuánta carga aguanta? | ¿Se mantiene el estado estable cuando algo falla? ¿Cuánto tarda en detectarlo y en recuperarse? |
| Métricas principales | Throughput, p95/p99 por nivel de carga | Disponibilidad percibida en el tiempo, TTD, TTR, radio de impacto, consistencia de los datos |
| Resultado típico | Una curva carga vs. latencia | Una **línea de tiempo** con el momento de la inyección, la desviación y la recuperación |

Un experimento de caos sigue cuatro pasos:

1. **Definir el estado estable** con una métrica de negocio medible (aquí, disponibilidad percibida y p99 de las ventas del generador de tráfico).
2. **Formular la hipótesis** de que el estado estable se mantiene (o se degrada de forma acotada) en el grupo experimental, frente al grupo de control (la misma situación sin las tácticas que se quieren evaluar).
3. **Inyectar el fallo** de forma controlada, con duración definida y con una condición de aborto. Un solo fallo a la vez, salvo cuando el escenario es justamente la combinación de dos, como en la tormenta de reintentos.
4. **Comparar** el estado estable antes, durante y después del fallo, y entre configuraciones. Lo que se busca es la diferencia.

#### 4.4.2 Catálogo de experimentos

El laboratorio tiene **tres experimentos**: el estado estable y dos fallos. El catálogo define **qué fallo** se inyecta, **qué configuraciones** se comparan y **en qué fase** se corre cada una. Las configuraciones se refieren a qué protecciones tiene Ventas: **completa** (el sidecar con reintentos y circuit breaker), **solo reintentos** (el sidecar con el circuit breaker desactivado) y **sin sidecar** (Ventas llama directamente a Inventario, sin protecciones; es el grupo de control). Cómo inyectar cada fallo y cómo preparar cada configuración se explica en la realización de pruebas. El resto del diseño (hipótesis, radio de impacto esperado, condición de aborto, duración, qué métricas confirman o refutan la hipótesis) lo define usted en la ficha de cada experimento.

| Experimento | Fallo inyectado | Cómo se inyecta | Fase local: configuraciones | Fase AWS: configuraciones | ASR |
| --- | --- | --- | --- | --- | --- |
| **Estado estable** | Ninguno: se mide el comportamiento normal | — | Completa | Completa | Los de los otros dos experimentos: mide sin fallo las métricas con las que se evalúan los ASR de degradación, tormenta de reintentos, consistencia y recuperación, para tener contra qué comparar |
| **Tormenta de reintentos** | Inventario lento (5 s por consulta) mientras 50 instancias de la app reintentan sin backoff | Endpoint de caos de Inventario (modo latencia) + script `recursos/tormenta_reintentos.sh` | Sin sidecar (control) · solo reintentos · completa · (opcional) sin sidecar con clientes que sí esperan entre intentos | Completa · sin sidecar con límite de peticiones en API Gateway | Degradación, tormenta de reintentos |
| **Caída de Inventario** | Inventario se detiene con ventas pendientes de descontar stock; en local, además, Ventas se reinicia con entregas pendientes | Local: `docker compose stop inventario`. AWS: `aws ecs stop-task` | Completa | Completa | Degradación, consistencia, recuperación |

Por qué cada fase corre lo que corre:

- **Las comparaciones entre configuraciones se hacen en local**, donde cambiar de configuración toma segundos y no cuesta créditos. Ahí se mide el efecto de cada táctica.
- **En AWS se corre la configuración completa**, para confirmar en el ambiente real lo que vio en local, y **lo que solo existe en AWS**: el límite de peticiones de API Gateway (en local no hay API Gateway) y el reemplazo automático de la tarea caída por ECS, que es lo que mide el tiempo de recuperación (en local usted hace el papel de ECS).

> [!IMPORTANT]
> **Pregunta 2:**
> Si usted fuera el líder encargado de llevar estas tácticas a producción en Cheapest, ¿las adoptaría en el mismo orden en que se presentan (reintentos, circuit breaker, rate limiting, Outbox e idempotencia), teniendo en cuenta el riesgo de cada cambio? Describa un plan de adopción que mitigue los riesgos asociados.
> El plan de adopción debe incluir: etapas, tiempo estimado por etapa y las tareas a realizar en cada una.

#### 4.4.3 Ficha de cada experimento

Antes de ejecutar cada experimento, complete su ficha. Hay una ficha por experimento (tres en total), que sirve para las dos fases. Las fichas se entregan en el informe y se califican: un experimento sin ficha previa no es un experimento, es una prueba al azar.

| Campo | Qué debe contener |
| --- | --- |
| Experimento y configuraciones | Nombre del experimento y configuraciones de tácticas de cada fase (en AWS, la revisión de la task definition de Ventas y la imagen del sidecar). |
| Estado estable | Métricas y valores que considera "normales", tomados de su medición del estado estable (disponibilidad percibida, p99, % de `pending`). Si el estado estable de local y el de AWS difieren, use el de cada ambiente para su fase. |
| Hipótesis | En el formato de las hipótesis de diseño, escrita antes de la fase local. |
| Fallo inyectado | Qué, dónde, con qué parámetros (por ejemplo, la latencia, la duración y el número de apps de la tormenta) y durante cuánto tiempo. |
| Radio de impacto esperado | Qué endpoints, servicios o datos espera que se afecten, y cuáles no. |
| Condición de aborto | Cuándo detendría el experimento y revertiría el fallo antes de tiempo. |
| Métricas y fuente | Qué va a medir para confirmar o refutar la hipótesis, y de dónde sale cada dato (generador de tráfico, endpoint de caos, logs o estadísticas del sidecar, CloudWatch, eventos de ECS). |
| Reversión | Cómo devuelve el sistema al estado inicial al terminar, en cada ambiente. |
| Predicción para AWS | Se escribe **después** de la fase local y **antes** de la fase AWS: qué espera que cambie en AWS frente a lo que vio en local (tiempos, latencias, qué se puede medir y qué no) y por qué. |

#### 4.4.4 ¿Qué componentes se van a diseñar o modificar?

| Componente | Cambio |
| --- | --- |
| Inventario | Endpoint de inyección de fallos en caliente (`/inventory/chaos`: latencia o errores, con duración) sobre la consulta de disponibilidad, y endpoint que recibe los descuentos de stock con clave de idempotencia. |
| Ventas | Graceful degradation (`pending_stock_confirmation`) cuando Inventario no está disponible, escritura transaccional de la venta junto con su fila de Outbox y endpoint de observación del Outbox (`/ventas/outbox/resumen`). |
| Sidecar Envoy (en la tarea de Ventas) | Configuración del timeout, de los reintentos con backoff y jitter, y del circuit breaker (los seis `???` que usted completa). |
| API Gateway | Rate limiting sobre el stage `lab` (solo en AWS). |

#### 4.4.5 ¿Qué métricas se van a medir?

| Métrica | Definición | ASR | Dónde se mide |
| --- | --- | --- | --- |
| Disponibilidad percibida | Respuestas útiles (2xx en < 3 s, incluidas las `pending`) ÷ total, por ventana de 10 s | Degradación, tormenta de reintentos, recuperación | CSV del generador de tráfico, resumido por ventanas con el script `ventanas.py` |
| p99 del generador de tráfico | Percentil 99 de la latencia de las ventas, por ventana de 10 s | Degradación | CSV del generador de tráfico |
| % de `pending` | Ventas registradas con graceful degradation ÷ total, por ventana | Degradación (y consistencia) | CSV del generador de tráfico |
| TTD | Desde la inyección (T_inj) hasta que el mecanismo detecta el fallo: el circuito se abre o el balanceador marca la tarea como no sana | Degradación, recuperación | Local: estadísticas del sidecar. AWS: logs del sidecar y CloudWatch |
| TTR | Desde el retiro del fallo (T_rem) o la caída hasta la vuelta al estado estable (primera ventana sin `pending` y con la disponibilidad normal) | Degradación, recuperación | CSV del generador de tráfico, eventos de ECS |
| Radio de impacto | Qué endpoints del generador de tráfico se desviaron del estado estable | Todos | CSV del generador de tráfico (además de las ventas, consulta cada 5 s la salud de Logística, un ítem de Inventario y el catálogo de productos externos) |
| Intentos por pedido | Peticiones enviadas por las apps defectuosas ÷ pedidos que querían hacer, durante la tormenta | Tormenta de reintentos | Resumen de `tormenta_reintentos.sh` |
| Consultas a Inventario por pedido | Fórmula abajo | Tormenta de reintentos | Contador del endpoint de caos, resumen de la tormenta y CSV del generador de tráfico |
| Pedidos duplicados | Ventas registradas que nadie recibió: aumento de filas del Outbox − (pedidos completados por la tormenta + ventas 201 del generador de tráfico) | Tormenta de reintentos (consistencia) | Resumen del Outbox antes y después, CSV de los dos scripts |
| Respuestas 429 | Porcentaje de las peticiones de la tormenta y del generador de tráfico rechazado por API Gateway | Tormenta de reintentos | CSV de los dos scripts (solo AWS) |
| Reconciliación del Outbox | Desde T_rec hasta que no quedan filas PENDING; decrementos duplicados | Consistencia | Resumen del Outbox, cantidad del ítem de inventario |
| MTTR | Desde que la tarea se detiene hasta que `/health` responde 200 y el target está `healthy` | Recuperación | Eventos de ECS, CloudWatch y registro de salud (solo AWS) |

**Cómo calcular las consultas a Inventario por pedido (ASR de tormenta de reintentos).** El endpoint de caos de Inventario, la herramienta con la que se inyectan los fallos, cuenta cuántas consultas de disponibilidad le llegan, reintentos incluidos (campo `llamadasDisponibilidad`). Léalo justo antes de lanzar la tormenta y justo después de que termine; la diferencia son las consultas que recibió Inventario. Divídala por los pedidos que realmente hicieron los tenderos en ese intervalo: los pedidos que quería hacer la tormenta (los imprime su resumen) más las ventas que envió el generador de tráfico.

$$\text{consultas por pedido} = \frac{\Delta\,\text{llamadasDisponibilidad}}{\text{pedidos de la tormenta} + \text{ventas enviadas por el generador de tráfico}}$$

Con el sistema sano cada pedido genera exactamente una consulta, así que el valor de referencia es 1. Ejemplo: si el contador subió 470 mientras la tormenta hizo 60 pedidos y el generador envió 240 ventas, hay 470 / 300 = 1,57 consultas por pedido, que cumple el ASR. Hay dos fuentes que lo suben: los reintentos de la app (cada reintento es una venta nueva que consulta a Inventario) y los reintentos del sidecar (como máximo `num_retries` adicionales por venta). El circuit breaker, en cambio, lo **baja**, porque con el circuito OPEN las consultas no llegan a Inventario.

### 4.5 Recursos requeridos

| Recurso | Detalle |
| --- | --- |
| Fase local | Docker con Docker Compose v2, Node.js y npm (para cargar los datos de prueba), `curl`, Python 3 y el backend de la rama `availability` |
| Fase AWS | Stack de CloudFormation (API Gateway, ECS/Fargate, RDS, balanceadores y sidecar Envoy) desplegado en su cuenta, los repositorios de ECR con las imágenes y la AWS CLI |
| Herramientas del laboratorio | En la carpeta `recursos/`: `generador_trafico.sh` (tráfico de estado estable), `ventanas.py` (resumen por ventanas de tiempo), `tormenta_reintentos.sh` (apps con reintentos defectuosos) |
| Datos de prueba | Script de seed de la rama `availability` (`npm run db:seed`) |
| Créditos AWS | Despliegue el stack solo cuando haya terminado la fase local, y elimínelo al terminar la fase AWS |

> [!NOTE]
> No se espera que llegue con experiencia previa en todas estas tecnologías. La columna **Recurso para entender qué hace** apunta a documentación oficial u otra referencia introductoria; revísela antes de tocar el template o el sidecar. Adicionalmente, se recomienda usar un asistente de IA (Claude, ChatGPT, etc.) para explorar cada servicio de AWS: pregúntele qué problema resuelve, qué recursos crea "por debajo" y qué pasaría si no existiera esa pieza en la arquitectura. Esto ayuda a construir intuición más allá de copiar comandos.

| Categoría                          | Tecnologías                                | Recurso para entender qué hace                                                                                     |
| ----------------------------------- | -------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| Ingeniería del caos                 | Principios de chaos engineering               | [Principles of Chaos Engineering](https://principlesofchaos.org/)                                                 |
| Ambiente local                      | Docker Compose                                | [Docker Compose overview](https://docs.docker.com/compose/)                                                        |
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

#### 4.5.1 Elementos de arquitectura involucrados

Servicios de Ventas e Inventario (y Logística como parte del stack), sidecar Envoy, API Gateway, balanceadores con sus health checks, el servicio ECS que reemplaza tareas, la base de datos RDS compartida (tablas `outbox_http_calls` e `items_inventario`) y el generador de tráfico de estado estable. El conector que se estudia es la llamada HTTP de Ventas a Inventario. En la fase local, Docker Compose reemplaza a ECS, a los balanceadores y a la RDS (un PostgreSQL en contenedor), y no hay API Gateway.

![Diagrama de despliegue del laboratorio](./recursos/diagrama_componentes.png)

*Figura 1. Vista de despliegue del laboratorio en AWS: API Gateway enruta hacia los servicios de Logística, Inventario y Ventas corriendo en ECS/Fargate; el sidecar Envoy corre como segundo contenedor dentro de la misma tarea de Ventas e intercepta el tráfico hacia Inventario. El generador de tráfico de estado estable y la tormenta de reintentos corren en el computador del estudiante.*

> [!NOTE]
> Note que el sidecar se despliega como un contenedor adicional dentro de la misma tarea ECS que Ventas, y el tráfico entre Ventas e Inventario pasa a través del proxy Envoy. Esto permite implementar las tácticas de resiliencia sin modificar el código de negocio de Ventas, y ajustar los parámetros de retry y circuit breaker sin necesidad de redesplegar la aplicación.

#### 4.5.2 Esfuerzo estimado

Referencia para planear; puede variar según su experiencia con Docker y AWS. Cada experimento dura entre 6 y 10 minutos por configuración, porque el fallo se inyecta y se retira en segundos. En la fase AWS buena parte del tiempo es espera: la creación del stack (la RDS sola tarda entre 10 y 15 minutos) y el despliegue de la configuración sin sidecar de Ventas (2 a 5 minutos). **Planee la fase AWS para una sola sesión**: llegue con la fase local terminada, las fichas con su predicción para AWS y el orden de los experimentos decidido, y elimine el stack al salir.

| Etapa | Esfuerzo aprox. |
| --- | --- |
| Fase local: configuración del sidecar, revisión del código y ambiente | 1 h |
| Fichas de los tres experimentos | 0,75 h |
| Fase local: estado estable, tormenta de reintentos (tres o cuatro configuraciones) y caída de Inventario | 1,5 h |
| Predicción para AWS en cada ficha | 0,25 h |
| Fase AWS: publicación de imágenes, despliegue del stack y carga de datos | 1,5 h |
| Fase AWS: los tres experimentos (la tormenta con dos configuraciones) | 1 h |
| Análisis y entregables | 1,75 h |
| **Total** | **7,75 h-persona** (de ellas, unas 2,5 h con el stack de AWS encendido) |

## 5. Ejecución del laboratorio

### 5.1 Ruta del laboratorio: primero local, después AWS

El laboratorio se hace en dos fases, en este orden:

| Fase | Qué se hace |
| --- | --- |
| **1. Local** (obligatoria, sin costo) | Completar el sidecar y revisar el código, levantar el ambiente con Docker Compose, conocer las herramientas para inyectar fallos, escribir las fichas y correr los tres experimentos con todas sus configuraciones locales (ver la realización de pruebas). |
| **2. AWS** (confirmación) | Escribir la predicción para AWS de cada ficha, desplegar el stack con CloudFormation, correr los tres experimentos con las configuraciones de AWS, comparar con local y eliminar el stack. |

Los comandos de los experimentos son los mismos en los dos ambientes. Lo que cambia son las URLs: en local los servicios se llaman directamente en su computador, y en AWS a través de API Gateway. Para no tener que reescribir los comandos, todos usan unas pocas variables de entorno, que usted define pegando uno de estos dos bloques en la terminal:

**Fase local:**

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

**Fase AWS** (`<API_ID>` sale de la URL de API Gateway que obtendrá al desplegar el stack):

```bash
# Variables del ambiente AWS: todo pasa por API Gateway
export AMBIENTE=aws
export BASE_URL=https://<API_ID>.execute-api.us-east-1.amazonaws.com/lab
export ITEM=11111111-1111-4111-8111-111111111111
export INV=$BASE_URL/inventario
export INV_HEALTH=$BASE_URL/inventario/health
export VEN=$BASE_URL/ventas
# URLs que leen generador_trafico.sh y tormenta_reintentos.sh
export VENTA_URL=$VEN/ventas
export LOGISTICA_URL=$BASE_URL/logistica/health
export INVENTARIO_URL=$INV/items/$ITEM
export CATALOGO_URL=$VEN/productos-externos
```

Ambos definen `INV` (base de Inventario), `INV_HEALTH` (salud de Inventario), `VEN` (base de Ventas), `ITEM` (el ítem de inventario de los datos de prueba) y `AMBIENTE` (para nombrar los archivos de salida). Por ejemplo, `$INV/chaos` es `http://localhost:3002/inventory/chaos` en local y `$BASE_URL/inventario/chaos` en AWS. Las variables solo viven en la terminal donde las define: pegue el bloque en **cada** terminal que abra (el generador de tráfico y la tormenta corren en terminales aparte).

> [!TIP]
> Use una carpeta de trabajo por fase (por ejemplo `trabajo/local/` y `trabajo/aws/`), cada una con su `venta.json` y sus CSV. El cuerpo de la venta es distinto en cada ambiente, y así no mezcla los resultados.

### 5.2 Completar el sidecar y revisar el código

Antes de levantar nada hay que preparar el código. Esta parte tiene dos tareas: **completar la configuración del sidecar** (usted escribe seis valores) y **leer el ajuste de graceful degradation** de Ventas (ya está escrito; usted lo revisa para entender qué pasa cuando Inventario falla).

#### El sidecar Envoy: archivos y flujo

El directorio `apps/ventas/sidecar/` de la rama `availability` contiene tres archivos:

| Archivo            | Rol                                                                              |
| ------------------ | -------------------------------------------------------------------------------- |
| `Dockerfile`       | Imagen base `envoyproxy/envoy:v1.31` + `gettext-base` para la sustitución de variables |
| `entrypoint.sh`    | Al arrancar, sustituye `${INVENTARIO_UPSTREAM_HOST}` y `${INVENTARIO_UPSTREAM_PORT}` en el template y lanza Envoy |
| `envoy.yaml.tmpl`  | Configuración de Envoy con los parámetros de retry y circuit breaker — **usted debe completar los valores marcados con `???`** |

**Variables de entorno del sidecar** (le dicen a Envoy dónde está Inventario):

| Variable                   | Docker Compose (local) | ECS                       | Quién lo llena |
| -------------------------- | ---------------------- | ------------------------- | --- |
| `INVENTARIO_UPSTREAM_HOST` | `inventario`           | DNS del balanceador de Inventario | `docker-compose.yml` en local; el template de CloudFormation en ECS (`!GetAtt InventarioALB.DNSName`). No lo escriba a mano. |
| `INVENTARIO_UPSTREAM_PORT` | `3002`                 | `80`                      | Igual que la anterior. |

**Variables de entorno del contenedor ventas** (le dicen a Ventas que llame al sidecar y no a Inventario):

| Variable              | Docker Compose (local) | ECS | Por qué |
| --------------------- | --------------------- | --- | ---------------------------------------------------- |
| `INVENTARIO_BASE_URL` | `http://ventas-sidecar:10000` | `http://localhost:10000` | Ventas llama al sidecar, no a Inventario. En ECS los contenedores de la misma tarea comparten la red; en Docker Compose el sidecar es otro contenedor de la misma red |
| `INVENTARIO_TIMEOUT_MS` | `9000` | `9000` | Debe ser mayor que el timeout total del sidecar para no abortar antes de que Envoy resuelva los reintentos |

Ya están en `docker-compose.yml` y en el template de CloudFormation; no tiene que escribirlas. Solo cambian en la configuración sin sidecar, que se explica en la realización de pruebas.

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
- `1 + num_retries` ≤ 2. Cada venta genera como máximo una llamada original más `num_retries` reintentos. Si ese número pasara de 2, el sidecar solo, aunque la app se comportara bien, ya podría hacer que Inventario reciba más de 2 consultas por pedido, que es el límite del ASR de tormenta de reintentos.
- `base_ejection_time` < duración del fallo inyectado, para que el estado HALF-OPEN alcance a probar varias veces mientras dura el fallo y detecte pronto la recuperación. En el experimento de tormenta de reintentos, Inventario queda lento durante 150 s. Tenga en cuenta que Envoy **multiplica** `base_ejection_time` por el número de veces que el host ha sido eyectado seguidas: cada reapertura deja el circuito OPEN más tiempo.
- El ASR de degradación exige p99 < 3000 ms: una petición de prueba en HALF-OPEN que espera el `timeout` completo de la ruta también cuenta en ese p99.

> [!IMPORTANT]
> **Pregunta 3 (parte B — valores implementados; es la continuación de la parte A, en la que propuso un conjunto inicial de parámetros):**
> Documente en su entregable los valores que eligió para cada `TODO`, la justificación cuantitativa de cada uno y cómo garantiza que no violan el ASR de tormenta de reintentos (Inventario recibe ≤ 2 consultas por pedido). Para `base_ejection_time` justifique el valor configurado; el análisis de cuándo pasó realmente a HALF-OPEN, con sus mediciones, va en el análisis de resultados.

La configuración se verifica en el paso siguiente, al levantar el ambiente local: si un valor es inválido, el sidecar no arranca.

#### Ajuste de código: graceful degradation en Ventas

El sidecar maneja la capa de red. La decisión de negocio —qué responder al cliente cuando Inventario está caído— debe estar en el código de Ventas.

Cuando el circuito está OPEN, el sidecar devuelve HTTP 503 a Ventas. El cliente HTTP (`InventarioDisponibilidadClient`) convierte ese 503 en una excepción `ServiceUnavailableException`. Sin manejo explícito, esa excepción se propaga y Ventas retorna 503 al tendero.

Ese manejo está en `libs/ventas/src/services/venta.service.ts` y ya está aplicado en la rama `availability`; no tiene que escribirlo. Léalo para entender el flujo. Este es el fragmento relevante del método `create()`:

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

// ... la venta y su fila de Outbox se guardan en una misma transacción ...

if (isDegraded) {
  return {
    ...this.mapToResponse(venta),
    status: 'pending_stock_confirmation',
    message: 'Pedido registrado. La disponibilidad de stock será confirmada próximamente.',
  };
}
return this.mapToResponse(venta);
```

La variable `isDegraded` es la que conecta la graceful degradation con el Outbox: el `catch` no retorna de inmediato, sino que marca la venta para graceful degradation, deja que la venta se guarde junto con su fila de Outbox y solo al final responde `pending_stock_confirmation`. Volverá sobre esto en el experimento de caída de Inventario.

> [!NOTE]
> NestJS responde `POST` con **HTTP 201**, tanto para una venta normal como para una con graceful degradation. Lo que distingue la graceful degradation es el campo `status: pending_stock_confirmation` en el cuerpo. El generador de tráfico lo registra en la columna `pending` de su CSV.

### 5.3 Levantar el ambiente local con Docker Compose

Use **`docker compose`** (con espacio, el plugin de Docker Compose v2). Si su instalación solo tiene el binario antiguo `docker-compose` (con guion), reemplácelo en todos los comandos.

> [!WARNING]
> **Si ya usó Docker Compose en laboratorios anteriores con este mismo repositorio**, el volumen de la base local (`cheapest-api_postgres_data`) conserva el esquema de esas ramas y `npm run db:seed` falla (por ejemplo, con `column "tiendaIds" of relation "promociones" contains null values`). Empiece con una base limpia: `docker compose down -v` borra los contenedores **y la base local** de Docker Compose; después siga con `docker compose up -d --build`.

```bash
git checkout availability
docker compose up -d --build        # postgres, logística, inventario, sidecar y ventas
# Espere ~30 s a que los servicios creen las tablas y luego cargue los datos de prueba:
npm install
npm run db:seed                     # por defecto apunta a la base de Docker Compose (127.0.0.1:5432, base cheapest)
```

Verifique que los servicios y el sidecar responden:

```bash
curl -i http://localhost:3001/health      # logística
curl -i http://localhost:3002/health      # inventario
curl -i http://localhost:3003/health      # ventas
curl -s http://localhost:9901/ready       # sidecar Envoy: debe responder LIVE
```

Si el sidecar no responde `LIVE`, revise `docker compose logs ventas-sidecar`: lo más probable es un `???` sin reemplazar o un valor inválido en `envoy.yaml.tmpl`. Corríjalo y reconstruya solo el sidecar con `docker compose up -d --build ventas-sidecar`. Esta es la misma imagen que publicará en AWS: si funciona en local, funciona en ECS.

Los servicios se llaman **directamente**, sin API Gateway, así que en local se usan las rutas internas en inglés (`/inventory/...`). Pegue el bloque de variables del ambiente local (está en la ruta del laboratorio, al comienzo de la ejecución) y prepare los datos de las ventas, desde su carpeta de trabajo local.

Los datos de prueba tienen IDs fijos (los mismos de los laboratorios anteriores: tienda `bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb`, producto `aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa`, moneda `cccccccc-cccc-4ccc-8ccc-cccccccccccc`). El ítem de inventario de ese producto en esa tienda es `11111111-1111-4111-8111-111111111111` (la variable `$ITEM`).

Los datos de prueba no traen productos externos (los productos que cada tienda vende por fuera del catálogo de Cheapest), y la venta necesita uno. Cree uno y anote el `id` que retorna:

```bash
curl -s -X POST $VEN/productos-externos -H 'Content-Type: application/json' -d '{
  "tiendaId": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
  "codigoBarras": "7700000000001",
  "nombre": "Arroz 500 g",
  "categoria": "Granos",
  "precioBase": 25.5,
  "monedaId": "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
  "cantidad": 100
}'
```

Guarde el cuerpo de la venta en un archivo `venta.json`, que es el que usarán los scripts y los comandos `curl` del laboratorio:

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
curl -i -X POST $VEN/ventas -H 'Content-Type: application/json' -d @venta.json
```

Equivalencias entre los dos ambientes, para cuando un paso es distinto:

| En AWS | En local |
| --- | --- |
| `aws ecs stop-task` (Inventario) | `docker compose stop inventario` y luego `docker compose start inventario`: en local no hay un orquestador que reemplace el contenedor solo, así que usted hace el papel de ECS |
| Reinicio de la tarea de Ventas | `docker compose restart ventas` |
| Logs del sidecar en CloudWatch | `docker compose logs ventas-sidecar` y las estadísticas de `http://localhost:9901/stats` |
| Consultas SQL | `docker compose exec -T postgres psql -U postgres -d cheapest -c "<SQL>"` |
| Límite de peticiones de API Gateway | No existe en local |

Al terminar la fase local, apague el ambiente con `docker compose down`.

### 5.4 Herramientas para inyectar fallos y observar el sistema

Un experimento de caos necesita poder **encender y apagar un fallo en segundos**, sin redesplegar, y ver qué está pasando adentro mientras dura. El código base trae esas herramientas; **no tiene que modificarlas, pero sí debe probar cada una una vez ahora**, con el ambiente local arriba, para saber usarlas durante los experimentos. Al terminar esta parte debe haber inyectado y retirado un fallo, haber visto una venta con `pending_stock_confirmation` y haber leído el contador de consultas y el resumen del Outbox.

**1. Endpoint de caos de Inventario** (`apps/inventario/src/chaos.controller.ts` y `fault.middleware.ts`). Inyecta un fallo en la consulta de disponibilidad que hace Ventas (`GET /inventory/items/disponibilidad/:productoId`); el resto de Inventario sigue sano, lo que acota el radio de impacto. Pruébelo así:

```bash
# Inyectar latencia: cada consulta de disponibilidad tarda 5 s, durante 60 s
curl -s -X POST $INV/chaos -H 'Content-Type: application/json' \
  -d '{"mode": "latency", "delayMs": 5000, "durationMs": 60000}'

# Con el fallo activo, una venta tarda y (con el sidecar completo) termina como pending_stock_confirmation
curl -s -X POST $VEN/ventas -H 'Content-Type: application/json' -d @venta.json

# Ver el estado: modo, si está activo, hasta cuándo, y el contador llamadasDisponibilidad
curl -s $INV/chaos

# Retirar el fallo de inmediato (es lo que usará como reversión o ante una condición de aborto)
curl -s -X POST $INV/chaos -H 'Content-Type: application/json' -d '{"mode": "off"}'
```

También acepta errores en lugar de latencia: `{"mode": "error", "errorRate": 1}` hace que todas las consultas de disponibilidad respondan HTTP 500 (con `0.3`, el 30 %). Si omite `durationMs`, el fallo queda activo hasta que lo apague. Las respuestas incluyen `injectedAt` y `until` en UTC: úselas como hora de inyección (T_inj) y de retiro (T_rem) en sus experimentos. El contador `llamadasDisponibilidad` cuenta todas las consultas de disponibilidad que recibió Inventario desde que arrancó, reintentos incluidos; con él se calculan las consultas por pedido.

> [!NOTE]
> El estado del fallo vive en la memoria del proceso de Inventario: si el contenedor o la tarea se reinicia, arranca sin fallo y el contador vuelve a 0. El fallo solo afecta la consulta de disponibilidad, no el endpoint que recibe los descuentos de stock del Outbox.

**2. Endpoint de observación del Outbox.** `GET $VEN/outbox/resumen` retorna cuántas filas de `outbox_http_calls` hay en PENDING, DELIVERED y FAILED, la más antigua pendiente y la última entregada. Con él sigue la reconciliación sin abrir la base de datos. Consúltelo ahora: después de la venta de prueba debería ver al menos una fila DELIVERED.

**3. Estadísticas del sidecar (solo en local).** El puerto de administración de Envoy muestra si el circuito está abierto (`ejections_active` en 1) y cuántos reintentos ha hecho (`upstream_rq_retry`):

```bash
curl -s http://localhost:9901/stats | grep -E 'outlier_detection.ejections_active:|upstream_rq_retry:'
```

En AWS ese puerto no es accesible desde su computador; allí el estado del circuito se lee en los logs del sidecar en CloudWatch, como se explica en la fase AWS.

**4. Caídas de infraestructura.** En local se usan `docker compose stop`, `start` y `restart`; en AWS, `aws ecs stop-task` detiene una tarea como si su proceso hubiera muerto. No las pruebe todavía: los comandos exactos están en el experimento de caída de Inventario.

> [!NOTE]
> El código trae también `POST $VEN/chaos/sidecar`, que apaga el sidecar Envoy (le envía `/quitquitquit` a su puerto de administración). No hace parte de los experimentos; puede usarlo al diseñar el experimento del sidecar que se pide al final del laboratorio.

Con las herramientas probadas, **haga la fase local de la realización de pruebas** (los tres experimentos) antes de seguir con la fase AWS.

### 5.5 Fase AWS: Infraestructura como Código y el template del laboratorio

> [!IMPORTANT]
> Empiece esta parte solo cuando haya terminado la fase local y haya escrito la predicción para AWS de cada ficha. Desde el despliegue del stack hasta su eliminación, el laboratorio consume créditos.

En los labs anteriores, la infraestructura se creó paso a paso desde la consola de AWS: security groups, instancias EC2, RDS, ECS, API Gateway. Este enfoque manual tiene un problema: es propenso a errores, difícil de reproducir y no deja registro de qué se configuró exactamente.

**Infraestructura como Código (IaC)** resuelve esto declarando la infraestructura en un archivo de texto (código), que puede versionarse, revisarse y ejecutarse de forma reproducible. **AWS CloudFormation** es el servicio nativo de AWS para esto: usted define un *template* YAML o JSON que describe los recursos, y CloudFormation se encarga de crearlos, actualizarlos o eliminarlos.

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
> Los prefijos de ruta de API Gateway en este laboratorio son **`logistica`/`inventario`**, a diferencia de `logistics`/`inventory` usados en el Lab 4. La lista completa de rutas está en la verificación del despliegue, más abajo.

### 5.6 Publicar las imágenes en ECR

Publique las imágenes Docker en ECR y anote los URIs. En este laboratorio hay **cuatro imágenes**: las tres del monorepo más la del sidecar Envoy, con los seis `???` ya completados y verificados en la fase local.

| Servicio          | Repositorio sugerido     | Tag     | Dockerfile                          |
| ----------------- | ------------------------ | ------- | ----------------------------------- |
| Logística         | `cheapest-logistica`       | `2.0.0` | `apps/logistica/Dockerfile`         |
| Inventario        | `cheapest-inventario`      | `2.0.0` | `apps/inventario/Dockerfile`        |
| Ventas            | `cheapest-ventas`          | `2.0.0` | `apps/ventas/Dockerfile`            |
| Ventas sidecar    | `cheapest-ventas-sidecar`  | `1.0.0` | `apps/ventas/sidecar/Dockerfile`    |

Tutorial de apoyo:
- [Subir imágenes Docker a Amazon ECR](../tutoriales/subir_imagenes%20_a_ecr.md)

> Use el tag `2.0.0` para distinguir las imágenes con las modificaciones de este lab de las del Lab 4. La rama de trabajo para este laboratorio es **`availability`**.
> Recuerde que debe construir el sidecar como una imagen Docker aparte, usando el Dockerfile en `apps/ventas/sidecar/`, y subirla a ECR también. Construya todas las imágenes con `--platform linux/amd64` si su computador tiene un procesador ARM (por ejemplo, un Mac con chip Apple).

> [!IMPORTANT]
> Verifique que `envoy.yaml.tmpl` tiene la configuración **completa** (`enforcing_consecutive_5xx: 100`) antes de construir la imagen del sidecar. Si en la fase local lo dejó en `0` para la configuración *solo reintentos*, el circuito nunca se abrirá en AWS.

### 5.7 Desplegar el stack

```bash
aws cloudformation deploy  --template-file lab_5/recursos/cloudformation_template.yaml  --stack-name Cheapest-lab5  --parameter-overrides LogisticaImageUri=<URI_ECR_LOGISTICA>:2.0.0 InventarioImageUri=<URI_ECR_INVENTARIO>:2.0.0 VentasImageUri=<URI_ECR_VENTAS>:2.0.0  VentasSidecarImageUri=<URI_ECR_SIDECAR>:1.0.0 DBPassword=<SU_CONTRASEÑA>  --region us-east-1
```

Monitoree el progreso en la consola de AWS → CloudFormation → Stack `Cheapest-lab5` → pestaña **Events**.

El template ya configura todas las variables de entorno de las tareas: `INVENTARIO_BASE_URL=http://localhost:10000` e `INVENTARIO_TIMEOUT_MS=9000` en Ventas, `INVENTARIO_UPSTREAM_HOST` (el DNS del balanceador de Inventario, que el template obtiene solo) e `INVENTARIO_UPSTREAM_PORT=80` en el sidecar, `SIDECAR_ADMIN_URL=http://localhost:9901` y `OUTBOX_MAX_ATTEMPTS=600` también en Ventas, y `FAULT_DELAY_MS=0` en Inventario (arranca sano; los fallos se inyectan después, en caliente). No tiene que escribir ninguno de esos valores a mano.

> [!IMPORTANT]
> **Ejecute `aws cloudformation deploy` una sola vez.** El único cambio de configuración posterior (quitar el sidecar para una de las corridas de la tormenta de reintentos, y volver a ponerlo) se hace **en la consola de ECS**, como se explica en la realización de pruebas. Los fallos **no** se inyectan cambiando la infraestructura: se inyectan en caliente con el endpoint de caos y con la AWS CLI. Si vuelve a ejecutar `aws cloudformation deploy` con otros parámetros, CloudFormation puede devolver los servicios a la configuración que él creó y perder sus cambios.

### 5.8 Verificar el despliegue

Una vez el stack esté en estado `CREATE_COMPLETE`:

```bash
# Obtener la URL del API Gateway
aws cloudformation describe-stacks --stack-name Cheapest-lab5 --query "Stacks[0].Outputs[?OutputKey=='ApiGatewayUrl'].OutputValue" --output text
```

El valor que retorna es la **`BASE_URL`** que se usa en la fase AWS. Desde su carpeta de trabajo de AWS, pegue el bloque de variables del ambiente AWS con esa URL:

```bash
# Variables del ambiente AWS: todo pasa por API Gateway
export AMBIENTE=aws
export BASE_URL=https://<API_ID>.execute-api.us-east-1.amazonaws.com/lab
export ITEM=11111111-1111-4111-8111-111111111111
export INV=$BASE_URL/inventario
export INV_HEALTH=$BASE_URL/inventario/health
export VEN=$BASE_URL/ventas
# URLs que leen generador_trafico.sh y tormenta_reintentos.sh
export VENTA_URL=$VEN/ventas
export LOGISTICA_URL=$BASE_URL/logistica/health
export INVENTARIO_URL=$INV/items/$ITEM
export CATALOGO_URL=$VEN/productos-externos
```

Todas las peticiones que haga desde su computador (`curl` y los scripts del laboratorio) contra AWS pasan por API Gateway y usan estas rutas:

| Para qué | Método y ruta completa | Variable |
| --- | --- | --- |
| Salud de cada servicio | `GET {BASE_URL}/logistica/health`, `GET {BASE_URL}/inventario/health`, `GET {BASE_URL}/ventas/health` | `$INV_HEALTH` (Inventario) |
| **Crear una venta (endpoint bajo prueba)** | `POST {BASE_URL}/ventas/ventas` | `$VEN/ventas` |
| Crear y listar productos externos (para armar el cuerpo de la venta) | `POST` y `GET {BASE_URL}/ventas/productos-externos` | `$VEN/productos-externos` |
| Consultar un ítem de inventario y su `cantidad` | `GET {BASE_URL}/inventario/items/{itemInventarioId}` | `$INV/items/$ITEM` |
| Disponibilidad de un producto (la que consulta Ventas) | `GET {BASE_URL}/inventario/items/disponibilidad/{productoId}` | |
| Reponer stock de un ítem | `PATCH {BASE_URL}/inventario/items/{itemInventarioId}` | `$INV/items/$ITEM` |
| Inyectar o retirar un fallo en Inventario, y leer el contador de consultas | `POST` y `GET {BASE_URL}/inventario/chaos` | `$INV/chaos` |
| Estado del Outbox (conteo de filas por estado) | `GET {BASE_URL}/ventas/outbox/resumen` | `$VEN/outbox/resumen` |

> [!NOTE]
> El primer segmento de la ruta (`/ventas`, `/inventario`, `/logistica`) es el prefijo de API Gateway; el resto es la ruta del controlador. Por eso crear una venta es `/ventas/ventas`. API Gateway traduce `/inventario/...` a la ruta interna `/inventory/...` y `/logistica/...` a `/logistics/...`. Si usa los prefijos en inglés contra `BASE_URL` obtendrá 404. Las rutas en inglés (`/inventory/...`) solo se usan cuando se llama a un servicio **directamente**, sin API Gateway, como en la fase local. Con las variables `$INV` y `$VEN` no tiene que recordarlo.

Desde su computador verifique que los tres servicios responden:

```bash
curl -i $BASE_URL/logistica/health
curl -i $BASE_URL/inventario/health
curl -i $BASE_URL/ventas/health
```

Los tres deben retornar HTTP 200 antes de continuar.

### 5.9 Cargar datos base

La base de datos RDS de este stack se crea con `PubliclyAccessible: false`, por lo que no es alcanzable desde su computador. El procedimiento es el mismo que usó en el Lab 4: hágala temporalmente pública y abra el puerto 5432 **solo para su IP**, cargue los datos de prueba desde su máquina apuntando a la RDS real, y luego revierta ambos cambios.

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

# 6. Cargue los datos de prueba desde su computador (rama availability) apuntando a la RDS real
git checkout availability
DB_HOST=<RDS_ENDPOINT_DEL_STACK> DB_PORT=5432 DB_USER=postgres DB_PASSWORD=<SU_CONTRASEÑA> DB_NAME=Cheapest npm run db:seed
```

Al terminar, **revierta ambos cambios** para no dejar la base expuesta:

```bash
aws rds modify-db-instance --db-instance-identifier Cheapest-lab5-db --no-publicly-accessible --apply-immediately
aws ec2 revoke-security-group-ingress --group-id $SG_RDS_ID --protocol tcp --port 5432 --cidr ${MY_IP}/32
```

Cree el producto externo y el `venta.json` de AWS igual que en la fase local, ahora con `$VEN` apuntando a AWS y en su carpeta de trabajo de AWS. Pruebe la venta una vez; debe responder HTTP 201.

### 5.10 Explorar lo que se desplegó

> [!IMPORTANT]
> Antes de seguir con los experimentos, tómese unos minutos para explorar en la consola de AWS lo que CloudFormation acaba de crear. El objetivo es que el stack no sea una "caja negra": usted debe poder señalar, para cada recurso relevante, con qué parte del template se corresponde y qué rol cumple en la arquitectura. Compárelo también con su `docker-compose.yml`: ¿qué pieza de AWS reemplaza a cada servicio de Compose, y qué piezas no tienen equivalente local?

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

### 5.11 Cómo ver métricas en CloudWatch

> [!NOTE]
> **Amazon CloudWatch** es el servicio de observabilidad de AWS para ver métricas (series de tiempo), registros (logs) y alarmas. En la fase AWS cumple el papel que en local cumplían las estadísticas del sidecar y `docker compose logs`: lo usará para observar **cuántas peticiones llegan a Inventario**, **cuántos errores 5xx** se producen, **cuándo el balanceador marca una tarea como no sana** y **cuándo cambia el estado del circuito**.

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
  - `HealthyHostCount` y `UnHealthyHostCount` (statistic `Maximum`): cuántas tareas considera sanas el balanceador. Son la fuente del TTD y del TTR del experimento de caída de Inventario.
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

En Fargate no hay forma directa de abrir el puerto de administración de Envoy (9901) desde su computador, así que en AWS el estado del circuito se observa en los **registros de acceso** del sidecar, que Envoy escribe en CloudWatch Logs (grupo `/ecs/Cheapest-ventas-sidecar`). Cada línea corresponde a una petición de Ventas hacia Inventario y tiene esta forma:

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

La consulta separa de cada línea el código HTTP y las *response flags*, y cuenta cuántas peticiones hubo de cada combinación en intervalos de 10 s. El intervalo en que aparece `UH` es el tiempo con el circuito OPEN. El primer intervalo después de ese en que vuelven las respuestas `200 -` marca el regreso a CLOSED. Para contar reintentos use el contador `llamadasDisponibilidad` del endpoint de caos: este log registra una línea por petición de Ventas, no por intento. En local, las mismas líneas salen en `docker compose logs ventas-sidecar`.

## 6. Realización de pruebas

Aquí se explica cómo preparar cada configuración, cómo correr un experimento de caos (el protocolo es el mismo para todos y en los dos ambientes) y qué fallo inyectar en cada experimento del catálogo. Lo que **no** encontrará aquí son las hipótesis ni los resultados esperados: esos los escribe usted en las fichas.

### 6.1 Qué se corre en cada fase

| Experimento | Fase local | Fase AWS |
| --- | --- | --- |
| Estado estable | Completa | Completa |
| Tormenta de reintentos | Sin sidecar · solo reintentos · completa · (opcional) sin sidecar con clientes que esperan entre intentos | Completa · sin sidecar con límite de peticiones en API Gateway |
| Caída de Inventario | Idempotencia, caída y reinicio de Ventas con entregas pendientes, con la configuración completa | Caída, con el tiempo de recuperación real de ECS, con la configuración completa |

Orden sugerido en AWS, para cambiar la configuración de Ventas una sola vez: estado estable, tormenta con la configuración completa y caída de Inventario, todos con la configuración que creó CloudFormation; al final, la tormenta sin sidecar con límite de peticiones. Después elimine el stack.

### 6.2 Puntos de sensibilidad y configuraciones de Ventas

Un punto de sensibilidad es un parámetro que cambia el resultado de un experimento. Esta tabla los reúne para dos cosas: saber **qué debe mantener igual** entre una corrida y otra, para que la única diferencia sea la que quiere medir (por ejemplo, entre *solo reintentos* y *completa* solo cambia el circuit breaker), y saber **qué anotar en cada ficha**, para que otra persona pueda repetir su experimento. En este laboratorio usted solo varía la presencia del sidecar, el circuit breaker y el límite de peticiones; el resto lo fija una vez y no lo toca.

| Punto de sensibilidad | Dónde se modifica | Efecto esperado |
| --- | --- | --- |
| **Fallo de Inventario** (`mode`, `delayMs`, `durationMs`) | Endpoint de caos `POST $INV/chaos`. Efecto inmediato, sin redespliegues. | Define qué tan grave es el fallo y cuánto dura. `durationMs` es lo que permite observar la recuperación. |
| **Tormenta** (`CLIENTES`, `DURACION`, `TIMEOUT_CLIENTE`, `BACKOFF`) | Variables de `recursos/tormenta_reintentos.sh`. | Cuántas apps defectuosas hay y qué tan agresivamente reintentan. |
| **Presencia del sidecar** | Local: variable `VENTAS_INVENTARIO_BASE_URL` de Docker Compose. AWS: task definition `td-Cheapest-ventas` (procedimientos más abajo). | Sin sidecar no hay timeout corto, ni reintentos, ni circuit breaker. |
| **Reintentos** (`num_retries`, `base_interval`, `max_interval`) | Archivo `apps/ventas/sidecar/envoy.yaml.tmpl`. En local, cada cambio exige reconstruir el sidecar (`docker compose up -d --build ventas-sidecar`). | Más reintentos recuperan más fallos transitorios, pero multiplican las peticiones que recibe Inventario. |
| **Timeout de la ruta** (`timeout`) | El mismo archivo `envoy.yaml.tmpl`. | Un timeout corto libera rápido a Ventas, pero puede cortar peticiones que habrían respondido. |
| **Umbral de apertura del circuito** (`consecutive_5xx`) | El mismo archivo `envoy.yaml.tmpl`, sección `outlier_detection`. | Bajo: el circuito abre rápido, incluso por fallos pasajeros. Alto: tarda en abrir y el fallo se propaga más tiempo. |
| **Tiempo que el circuito permanece abierto** (`base_ejection_time`) | El mismo archivo `envoy.yaml.tmpl`, sección `outlier_detection`. | Corto: prueba con frecuencia si Inventario se recuperó. Largo: Ventas tarda en notar la recuperación. |
| **Timeout de Ventas hacia el sidecar** (`INVENTARIO_TIMEOUT_MS`) | Variable de entorno del contenedor `ventas`. Queda en `9000` en los dos ambientes. | Debe ser mayor que el timeout total del sidecar; si es menor, Ventas aborta antes de que Envoy termine sus reintentos. |
| **Límite de peticiones** (*Rate* y *Burst*) | API Gateway → `Cheapest-ms-api` → stage `lab` (solo AWS, en la tormenta de reintentos). | Un límite bajo protege a los servicios, pero rechaza peticiones legítimas; un límite de stage no distingue clientes ni tipos de tráfico. |
| **Detección del balanceador** (`HealthCheckIntervalSeconds`, umbrales de sano/no sano) y **número de tareas** (`DesiredCount`) | Template de CloudFormation (target groups y servicios ECS). **No los modifique** durante el laboratorio: son lo que mide en la caída de Inventario. | Determinan cuánto tarda el sistema en notar una tarea caída y si hay otra que atienda mientras tanto. Úselos en su decisión arquitectónica. |

#### Configuraciones en local

| Configuración | Cómo se obtiene |
| --- | --- |
| **Completa** (reintentos + circuit breaker) | La que levanta `docker compose up`. Para volver a ella desde las otras: `docker compose up -d ventas` (sin la variable) y, si cambió el sidecar, devuelva `enforcing_consecutive_5xx` a `100` y `docker compose up -d --build ventas-sidecar`. |
| **Solo reintentos** | En `apps/ventas/sidecar/envoy.yaml.tmpl` cambie temporalmente `enforcing_consecutive_5xx: 100` por `enforcing_consecutive_5xx: 0` (Envoy sigue contando errores, pero no eyecta el host, es decir, el circuito nunca se abre) y reconstruya el sidecar: `docker compose up -d --build ventas-sidecar`. |
| **Sin sidecar** (grupo de control) | Recree Ventas apuntando directamente a Inventario: `VENTAS_INVENTARIO_BASE_URL=http://inventario:3002 docker compose up -d ventas`. El sidecar sigue corriendo, pero Ventas ya no pasa por él. |

Verifique cada cambio antes de experimentar: `docker compose exec ventas printenv INVENTARIO_BASE_URL` muestra a dónde llama Ventas. Para *solo reintentos*, confirme que el archivo dice `0` y que el sidecar se reconstruyó después del cambio (`docker compose ps ventas-sidecar` muestra cuándo se creó el contenedor).

#### Configuraciones en AWS

La tormenta de reintentos en AWS usa dos configuraciones de Ventas: la **completa**, que es la que creó CloudFormation, y la **sin sidecar**. En local quitar el sidecar es cambiar una variable; en ECS no se puede editar una tarea que ya existe. Lo que define una tarea (qué contenedores tiene, con qué imagen y con qué variables) es su **task definition**, y una task definition no se modifica: cada cambio crea una **revisión** nueva con un número consecutivo, y después se le indica al servicio que use esa revisión. Por eso quitar el sidecar en AWS toma dos pasos: crear la revisión sin sidecar (procedimiento B, que usa el A) y desplegarla. Anote el número de la revisión completa antes de empezar, para poder volver a ella.

**Procedimiento A — Crear una nueva revisión de una task definition y desplegarla**

1. Consola de AWS → **ECS → Task definitions** → elija la familia `td-Cheapest-ventas` → seleccione la revisión **más reciente** → **Create new revision** → **Create new revision with JSON**.
2. Haga en el JSON el cambio que pide el paso (variables en `environment`, contenedores en `containerDefinitions`) y haga clic en **Create**.
3. Vaya a **ECS → Clusters → `Cheapest-lab5-cluster` → Services**, seleccione el servicio `svc-Cheapest-ventas` → **Update service**, elija la revisión que acaba de crear en **Revision** y haga clic en **Update**.
4. Espere a que en la pestaña **Tasks** quede una sola tarea en `RUNNING` con la revisión nueva (la anterior pasa a `STOPPED`). Tarda entre 2 y 5 minutos.

Para volver a la configuración completa, repita los pasos 3 y 4 eligiendo la revisión completa.

**Procedimiento B — Revisión sin sidecar.** Con el procedimiento A, parta de la revisión **completa** y en el JSON:

- borre completo el objeto del contenedor `ventas-sidecar` dentro de `containerDefinitions` (desde su `{` hasta su `}`, incluida la coma que lo separa del contenedor `ventas`);
- en el contenedor `ventas`, cambie `INVENTARIO_BASE_URL` para que apunte directamente al balanceador de Inventario. El DNS está en las salidas del stack (`aws cloudformation describe-stacks --stack-name Cheapest-lab5 --query "Stacks[0].Outputs[?OutputKey=='InventarioALBDns'].OutputValue" --output text`):
  ```json
  { "name": "INVENTARIO_BASE_URL", "value": "http://<InventarioALBDns>" }
  ```

Al desplegarla, verifique que la tarea de Ventas tiene un solo contenedor (pestaña **Tasks** → la tarea → **Containers**) y que `curl $BASE_URL/ventas/health` responde 200.

### 6.3 Protocolo común y generador de tráfico de estado estable

Todos los experimentos siguen el mismo protocolo, en los dos ambientes. Antes de empezar, pegue el bloque de variables del ambiente en el que va a trabajar en **cada** terminal que abra.

**1. Prepare el sistema.**

```bash
# Reponer stock: el generador de tráfico vende 2 unidades por segundo y la tormenta muchas más,
# y los datos de prueba solo traen 100. Sin este paso, en menos de un minuto las ventas empiezan
# a fallar por falta de stock y contaminan el experimento.
curl -s -X PATCH $INV/items/$ITEM -H 'Content-Type: application/json' -d '{"cantidad": 100000}'

# Confirmar que no hay un fallo activo y anotar el contador de consultas
curl -s -X POST $INV/chaos -H 'Content-Type: application/json' -d '{"mode": "off"}'
curl -s $INV/chaos

# Confirmar que una venta se confirma normalmente (sin pending_stock_confirmation)
curl -s -X POST $VEN/ventas -H 'Content-Type: application/json' -d @venta.json
```

**2. Arranque el generador de tráfico** en una terminal aparte, desde su carpeta de trabajo, con un archivo de salida por experimento, configuración y ambiente:

```bash
./lab_5/recursos/generador_trafico.sh tormenta_local_completa.csv
```

El generador de tráfico envía 2 ventas por segundo a `POST .../ventas/ventas` y, cada 5 s, una petición a la salud de Logística, al ítem de Inventario y al catálogo de productos externos, para medir el radio de impacto. Cada petición sale en segundo plano, de modo que **la tasa no baja aunque el sistema se ponga lento** (lazo abierto). Toma las URLs de las variables del ambiente. Déjelo corriendo durante todo el experimento y deténgalo con `Ctrl+C` al final.

**3. En local, registre el estado del circuito** en otra terminal, con las estadísticas del sidecar que probó al conocer las herramientas (en AWS se usa la consulta de Logs Insights de CloudWatch):

```bash
while true; do
  printf "%s %s\n" "$(date -u +%H:%M:%S)" \
    "$(curl -s http://localhost:9901/stats | grep -E 'outlier_detection.ejections_active:|upstream_rq_retry:' | tr '\n' ' ')"
  sleep 1
done | tee tormenta_local_completa_circuito.log
```

Cada segundo escribe la hora y los dos contadores. `ejections_active` en 1 significa circuito OPEN; en 0, CLOSED (o HALF-OPEN mientras pasa el tráfico de prueba). `upstream_rq_retry` cuenta los reintentos que ha hecho el sidecar.

**4. Siga el cronograma.** Anote cada hora en UTC (`date -u +%H:%M:%S`), que es la zona horaria del CSV del generador de tráfico y de los logs de CloudWatch.

| Momento | Qué hacer |
| --- | --- |
| T−2 min | Arranque el generador de tráfico: dos minutos de estado estable antes del fallo. |
| T_inj | Inyecte el fallo del experimento. Anote la hora (el endpoint de caos la retorna en `injectedAt`). |
| T_inj → T_rem | Observe. Si se cumple su condición de aborto, retire el fallo de inmediato y anótelo. |
| T_rem | El fallo se retira (solo, al cumplirse `durationMs`, o porque usted lo retiró). En las caídas, T_rem es cuando el componente vuelve a estar disponible. |
| T_rem → T_rem + 3 min | Siga observando: es el período de recuperación. |
| Fin | Detenga el generador de tráfico. |

**5. Resuma el CSV por ventanas de 10 s:**

```bash
python3 lab_5/recursos/ventanas.py tormenta_local_completa.csv
```

El script imprime, por ventana y por endpoint, el número de peticiones, la disponibilidad percibida (2xx en menos de 3 s), el % de `pending` y el p99, y guarda la tabla en `tormenta_local_completa_ventanas.csv` para graficar la línea de tiempo en una hoja de cálculo. Identificar el estado estable, el TTD y el TTR a partir de esa tabla es parte de su análisis.

> [!IMPORTANT]
> **Un fallo a la vez** (la tormenta de reintentos combina dos a propósito). Antes de empezar un experimento, verifique que el anterior terminó: fallo apagado, circuito cerrado (una venta sin `pending`), servicios arriba y sin filas PENDING en `GET $VEN/outbox/resumen`. Si mezcla dos fallos, no podrá atribuirle el resultado a ninguno.

### 6.4 Experimento de estado estable

**Configuración:** completa, en local y en AWS. No se inyecta ningún fallo.

Siga el protocolo durante 5 minutos sin inyectar nada. Con la tabla de `ventanas.py`, defina el estado estable que usará en las fichas: disponibilidad percibida, p99 y % de `pending` de las ventas, y el comportamiento de los otros tres endpoints. Lea también el contador `llamadasDisponibilidad` al principio y al final, y calcule las consultas por venta en estado estable.

**Qué observar:**

- ¿Qué tanto varían la disponibilidad y el p99 de una ventana a otra sin ningún fallo? Esa variación natural es la que debe tener en cuenta al decidir si un experimento "se desvió" del estado estable.
- ¿Hay respuestas `pending` sin fallo? Si las hay, resuelva la causa antes de seguir.
- En AWS: ¿cuánto cambió el estado estable frente al local, y por qué? Use el estado estable de cada ambiente para su fase.

### 6.5 Experimento de tormenta de reintentos (*retry storm*)

**Configuraciones:** en local, sin sidecar (grupo de control), solo reintentos y completa; opcional, sin sidecar con clientes que sí esperan entre intentos. En AWS, completa y sin sidecar con límite de peticiones en API Gateway.

Este experimento reproduce el escenario del lunes por la mañana. Combina dos fallos inyectados a la vez: **Inventario lento** y una **versión defectuosa de la app** que reintenta de inmediato cada pedido que no le responde en 3 s. Es el único experimento con dos fallos simultáneos, porque la tormenta solo existe cuando se juntan los dos. El script `recursos/tormenta_reintentos.sh` simula esas apps: cada una envía un pedido y, si no recibe un 2xx a tiempo, **abandona la petición y la reenvía**; después de un pedido exitoso espera 5 s antes del siguiente. Con el sistema sano es tráfico normal. Mientras tanto, el generador de tráfico representa a los demás tenderos, los que tienen la app sana.

> [!IMPORTANT]
> Una petición que el cliente abandona **no se cancela en el servidor**: Ventas la sigue procesando y, si termina, registra la venta. Mida cuántas ventas se registraron (filas totales del Outbox) frente a cuántos pedidos pidieron realmente los tenderos.

**Para cada configuración:**

1. Prepare el sistema (paso 1 del protocolo), arranque el generador de tráfico y, en local, el registro del circuito. Anote el total de filas del Outbox (`PENDING + DELIVERED + FAILED` de `GET $VEN/outbox/resumen`) y el contador `llamadasDisponibilidad`.
2. Pasados 2 minutos, inyecte la latencia en Inventario y, de inmediato, lance la tormenta en otra terminal (T_inj):
   ```bash
   curl -s -X POST $INV/chaos -H 'Content-Type: application/json' \
     -d '{"mode": "latency", "delayMs": 5000, "durationMs": 150000}'
   CLIENTES=50 DURACION=120 ./lab_5/recursos/tormenta_reintentos.sh tormenta_local_sin_sidecar_apps.csv
   ```
   `CLIENTES` es el número de apps defectuosas y `DURACION` los segundos que dura la tormenta. Para la configuración opcional con clientes que esperan entre intentos, agregue `BACKOFF=1` al comando de la tormenta.
3. La tormenta termina sola a los 120 s e imprime un resumen (pedidos, intentos por pedido, peticiones abandonadas, 429). Anote el contador `llamadasDisponibilidad` en ese momento. El fallo de Inventario se retira a los 150 s (T_rem). Observe 3 minutos más.
4. Vuelva a leer el total de filas del Outbox y detenga el generador de tráfico.
5. Antes de la siguiente configuración, espere a que `GET $VEN/outbox/resumen` muestre 0 filas PENDING. Sin protecciones, la tormenta registra miles de ventas duplicadas, y el Outbox tarda alrededor de un minuto en entregarlas a Inventario; si empieza antes, esas entregas se mezclan con el experimento siguiente.

> [!NOTE]
> Sin sidecar, Ventas espera a Inventario hasta `INVENTARIO_TIMEOUT_MS` (9 s), así que cada venta tarda lo que tarde Inventario. Que la respuesta termine siendo un 201 no significa que el tendero la haya recibido a tiempo: por eso la disponibilidad percibida solo cuenta las respuestas que llegan en menos de 3 s.

**Límite de peticiones en API Gateway (solo en AWS, con la configuración sin sidecar).** Configúrelo antes de esa corrida y retírelo al terminarla. Puede hacerlo en la consola (**API Gateway → `Cheapest-ms-api` → Protect → Throttling**, stage `lab`) o con la AWS CLI:

```bash
aws apigatewayv2 update-stage --api-id <API_ID> --stage-name lab \
  --default-route-settings ThrottlingRateLimit=10,ThrottlingBurstLimit=20
# Al terminar:
aws apigatewayv2 update-stage --api-id <API_ID> --stage-name lab \
  --default-route-settings ThrottlingRateLimit=1000,ThrottlingBurstLimit=5000
```

Qué hace cada parte del comando:

| Parte | Significado |
| --- | --- |
| `aws apigatewayv2 update-stage` | Modifica la configuración de un *stage* (una versión publicada de la API; la del laboratorio se llama `lab`) de una HTTP API. |
| `--api-id <API_ID>` | Identificador de la API: es la primera parte de su `BASE_URL` (lo que va antes de `.execute-api`). |
| `--stage-name lab` | El stage al que se le aplica el límite. Como todas las rutas del laboratorio pasan por ese stage, el límite afecta a todas por igual. |
| `--default-route-settings` | Configuración que se aplica a todas las rutas del stage que no tengan una propia. |
| `ThrottlingRateLimit=10` | Peticiones por segundo que API Gateway acepta de forma sostenida. Las que pasan del límite reciben 429 sin llegar a los servicios. |
| `ThrottlingBurstLimit=20` | Cuántas peticiones puede aceptar de golpe, por encima del ritmo sostenido, antes de empezar a rechazar (absorbe picos cortos). |
| El segundo comando (`1000` / `5000`) | Devuelve el stage a límites tan altos que, con el tráfico del laboratorio, no tienen efecto. |

Los valores 10 y 20 son un punto de partida: si en su propuesta de parámetros iniciales (la pregunta sobre calibración de retry, circuit breaker y rate limiting) llegó a otros, use los suyos y justifíquelos frente al tráfico que generó la tormenta en su fase local.

**Qué observar:**

- ¿Cuántos intentos por pedido necesitaron las apps defectuosas en cada configuración, y cuántos pedidos lograron completar?
- ¿Cuántas consultas recibió Inventario por cada pedido? ¿Qué parte viene de los reintentos de la app y qué parte de los del sidecar? Compare *sin sidecar* con *solo reintentos*: ¿los reintentos del sidecar agregaron consultas ante un Inventario lento? ¿Por qué? (Revise `upstream_rq_retry` y el flag `UT` en los logs del sidecar.)
- ¿Cuántas ventas se registraron frente a los pedidos que realmente se hicieron? ¿De dónde salen las ventas sobrantes y qué significan para un tendero?
- ¿Qué le pasó a la disponibilidad de las ventas del generador de tráfico, los otros tenderos, en cada configuración? En AWS con límite de peticiones, ¿recibieron 429?
- Con la configuración completa: ¿cuánto tardó el circuito en abrir (TTD), cada cuánto volvió a HALF-OPEN y cuánto tardó en volver a CLOSED después de T_rem (TTR)? ¿Por qué la tormenta se apaga sola? ¿Qué táctica rompe el ciclo de reintentos? Compare *solo reintentos* con *completa*.
- Con límite de peticiones, ¿qué hicieron las apps defectuosas al recibir 429? ¿El límite apagó la tormenta o solo la contuvo en la entrada?
- Entre local y AWS con la configuración completa: ¿se sostuvo el resultado? ¿Qué cambió (tiempos, p99, TTD) y por qué?

### 6.6 Experimento de caída de Inventario

**Configuración:** completa, en local y en AWS.

Este experimento mide dos cosas: si las ventas registradas mientras Inventario está caído descuentan su stock exactamente una vez cuando vuelve (ASR de consistencia), y cuánto tarda la infraestructura en reemplazar una tarea caída (ASR de recuperación). La primera se estudia a fondo en local; la segunda solo se puede medir en AWS, donde ECS reemplaza la tarea sin que usted intervenga. Tiene tres partes: idempotencia, la caída y un reinicio de Ventas con entregas pendientes.

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
2. ¿Por qué el `OutboxHttpCall` se crea incluso en el camino de graceful degradation (`isDegraded = true`, el fragmento que leyó al revisar el código)?
3. ¿Qué payload lleva el `OutboxHttpCall`? Verifique que incluye todos los campos que `POST /inventory/ventas/desde-outbox` necesita.

#### Revisar el endpoint con idempotencia en Inventario

Archivo: `libs/inventario/src/services/registro-venta.service.ts` → método `createDesdeOutbox()`

Analice el flujo implementado y responda:
1. ¿Qué ocurre si el proceso de Inventario muere entre `decrementCantidad()` y el `save(ProcessedCall)`? ¿Puede producirse un decremento sin `ProcessedCall`?
2. ¿Por qué se usa el `id` del `OutboxHttpCall` como clave de idempotencia en lugar del `ventaId`?

#### Parte 1 — Idempotencia (solo en local)

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
curl -s $INV/items/$ITEM | grep -o '"cantidad":[0-9]*'
curl -s -X POST $INV/ventas -H 'Content-Type: application/json' -d @registro.json; echo
curl -s -X POST $INV/ventas -H 'Content-Type: application/json' -d @registro.json; echo
curl -s $INV/items/$ITEM | grep -o '"cantidad":[0-9]*'

# Con clave de idempotencia: la misma petición dos veces con la misma clave
KEY=$(uuidgen | tr 'A-Z' 'a-z')
curl -i -X POST $INV/ventas/desde-outbox -H 'Content-Type: application/json' \
  -H "X-Idempotency-Key: $KEY" -d @registro.json
curl -i -X POST $INV/ventas/desde-outbox -H 'Content-Type: application/json' \
  -H "X-Idempotency-Key: $KEY" -d @registro.json
curl -s $INV/items/$ITEM | grep -o '"cantidad":[0-9]*'
```

Haga esta parte **sin el generador de tráfico corriendo**, para que la cantidad solo cambie por sus peticiones. Compare cuánto bajó la cantidad en cada caso y qué código HTTP respondió la segunda petición con clave.

#### Parte 2 — Caída de Inventario (local y AWS)

1. Prepare el sistema (paso 1 del protocolo), anote la cantidad del ítem y arranque el generador de tráfico.
2. En otra terminal, registre el estado del Outbox y la salud de Inventario cada 5 s durante todo el experimento:
   ```bash
   while true; do
     printf "%s health=%s %s\n" "$(date -u +%H:%M:%S)" \
       "$(curl -s -o /dev/null -w '%{http_code}' --max-time 4 $INV_HEALTH)" \
       "$(curl -s --max-time 4 $VEN/outbox/resumen)"
     sleep 5
   done | tee caida_${AMBIENTE}_outbox.log
   ```
3. Pasados 2 minutos de estado estable, detenga Inventario. Anote la hora: es T_inj.
   - **En local:**
     ```bash
     date -u +%H:%M:%S; docker compose stop inventario
     ```
     Espere 60 s y vuelva a arrancarlo usted mismo (aquí usted hace el papel de ECS): `docker compose start inventario`.
   - **En AWS:**
     ```bash
     TASK=$(aws ecs list-tasks --cluster Cheapest-lab5-cluster --service-name svc-Cheapest-inventario --query "taskArns[0]" --output text)
     date -u +%H:%M:%S; aws ecs stop-task --cluster Cheapest-lab5-cluster --task $TASK --reason "experimento de caos"
     ```
     El primer comando busca el identificador de la tarea de Inventario que está corriendo; el segundo la detiene. No haga nada más: ECS debe lanzar una tarea nueva solo.
4. Observe hasta 3 minutos después de que `health` vuelva a 200 (ese momento es **T_rec**) y las filas PENDING lleguen a 0.
5. Detenga el generador de tráfico y el registro. Consulte la cantidad final del ítem y, en AWS, los eventos del servicio:
   ```bash
   curl -s $INV/items/$ITEM | grep -o '"cantidad":[0-9]*'
   # Solo en AWS:
   aws ecs describe-services --cluster Cheapest-lab5-cluster --services svc-Cheapest-inventario \
     --query "services[0].events[:10].[createdAt,message]" --output table
   ```

**Qué observar:**

- **Ventas durante la caída:** ¿qué recibió el sidecar en cada ambiente mientras Inventario no estaba (en local, el contenedor desaparece de la red; en AWS, el balanceador se queda sin tareas), con qué código y qué tan rápido? ¿Cómo reaccionó el sidecar? ¿Se mantuvo la disponibilidad percibida de las ventas?
- **Outbox:** ¿cuántas filas se acumularon en PENDING? ¿Cuánto tardaron en pasar a DELIVERED después de T_rec? ¿Quedó alguna en FAILED?
- **Exactamente una vez:** compare cuánto bajó la cantidad del ítem con el número de ventas 201 que registró el generador de tráfico (`grep -c ',venta,201,' caida_aws.csv`). ¿Coinciden?
- **Tiempo de recuperación descompuesto (solo AWS):** con los eventos de ECS, `HealthyHostCount`/`UnHealthyHostCount` del target group de Inventario y el registro de salud, ubique en el tiempo: la tarea detenida, la tarea nueva iniciada, su registro en el target group, el momento en que quedó `healthy` y el primer `health=200`. ¿Qué etapa dominó el MTTR? ¿Cuánto más tardó que los 60 s de su caída local, y qué parte de esa diferencia es trabajo que en local hizo usted?

> [!IMPORTANT]
> **Pregunta 5:**
> Describa con precisión el estado de inconsistencia que se produce en cada escenario:
> 1. Ventas registradas durante la caída de Inventario (Parte 2 de este experimento, antes de que Inventario vuelva): ¿qué diferencia hay entre lo que dice la tabla `ventas` y lo que dice `items_inventario.cantidad`?
> 2. Reintento sin idempotencia (Parte 1): ¿qué invariante de negocio se viola? ¿Cómo lo detectaría operacionalmente en Cheapest?

#### Parte 3 — Ventas se reinicia con entregas pendientes (solo en local)

1. Prepare el sistema y arranque el generador de tráfico. Detenga Inventario (`docker compose stop inventario`) para que las ventas se registren con graceful degradation y el Outbox acumule filas PENDING.
   > El endpoint de caos no sirve para esta parte: sus fallos afectan solo la consulta de disponibilidad, no el endpoint que recibe las entregas del Outbox, así que con errores inyectados las filas se seguirían entregando.
2. A los 30 s, cuando `GET $VEN/outbox/resumen` muestre varias filas PENDING, detenga el generador de tráfico, anote el resumen y reinicie Ventas:
   ```bash
   docker compose restart ventas
   ```
3. Cuando Ventas vuelva a responder `/health`, consulte el resumen otra vez (las filas deben seguir ahí) y arranque Inventario (`docker compose start inventario`). Mida cuánto tardan las filas PENDING en llegar a 0 desde que Inventario vuelve a responder `$INV_HEALTH`.

**Qué observar:** ¿se perdió alguna entrega pendiente al reiniciarse Ventas? ¿Por qué? Relacione la respuesta con la transacción de `VentaService.create()` que revisó al inicio de este experimento.

> [!IMPORTANT]
> **Pregunta 7:**
> El equipo de operaciones de Cheapest quiere repetir este experimento de caída de Inventario en producción, un lunes por la mañana, para confirmar los resultados con tráfico real. ¿Lo aprobaría? Si lo aprueba, defina las condiciones: cómo limitaría el radio de impacto (qué porcentaje de tiendas o de tráfico), qué condiciones de aborto usaría y con qué umbrales, quién debe estar presente y cómo revertiría. Si no lo aprueba, explique qué tendría que cambiar en la arquitectura (piense en el `DesiredCount` de Inventario, el número de tareas que ECS mantiene corriendo) para que fuera aceptable.

### 6.7 Lo que los experimentos no prueban

Los dos experimentos con fallo atacan la dependencia entre Ventas e Inventario. Quedan sin probar al menos dos puntos de fallo de la arquitectura:

- **El propio sidecar.** Los dos contenedores de la tarea de Ventas están marcados `Essential: true` en el template de CloudFormation. ¿Qué le pasa a Ventas si Envoy termina?
- **La base de datos compartida.** Los tres servicios usan la misma instancia RDS, que se reinicia en operaciones normales (mantenimiento, cambio de parámetros, actualización menor de versión). ¿Qué reportan los `GET /health` de los servicios cuando la base no responde? ¿La graceful degradation cubre ese fallo?

> [!IMPORTANT]
> **Pregunta 4:**
> Elija uno de los dos puntos de fallo anteriores y escriba la **ficha completa** del experimento que lo probaría en AWS, con los mismos campos de las fichas de sus experimentos: estado estable, hipótesis, cómo inyectaría el fallo (por ejemplo `POST $VEN/chaos/sidecar` o `aws rds reboot-db-instance`), radio de impacto esperado, condición de aborto, métricas con su fuente y reversión. Sustente la hipótesis con lo que puede leer en el template, en `docker-compose.yml` y en el código (por ejemplo, qué revisa el endpoint `/health`). No tiene que ejecutarlo.
> Luego, con base en esa ficha y en lo que observó en la tormenta de reintentos y en la caída de Inventario, identifique al menos dos clases de fallos que las tácticas del laboratorio no resuelven por sí solas aun si cumplen sus ASRs, y qué capacidad adicional haría falta para una operación real de Cheapest a mayor escala. Si la capacidad que propone es una capa de control de tráfico centralizada como Aperture de DoorDash, solo nómbrela aquí: la comparación con Aperture se desarrolla en la decisión arquitectónica.

### 6.8 Cómo leer los resultados

Para cada experimento, la pieza central del análisis es la **línea de tiempo**: la disponibilidad percibida y el % de `pending` de las ventas por ventana de 10 s, con T_inj y T_rem marcados. Sobre ella se leen el estado estable, la desviación, el TTD y el TTR. Compare:

- **Entre configuraciones** de la tormenta de reintentos: el efecto de una táctica es la diferencia con la configuración que no la tiene. Por ejemplo, el efecto del circuit breaker es la diferencia entre *solo reintentos* y *completa*.
- **Entre ambientes**: ¿qué conclusión de la fase local se sostuvo en AWS? ¿Qué cambió, y lo había predicho en la ficha?
- **Contra la ficha**: ¿el radio de impacto y los tiempos fueron los que predijo? Lo que no predijo es tan importante como lo que sí.
- **Contra los ASRs**: use las medidas de respuesta de los escenarios de calidad tal como están escritas (por ventana, después de los primeros 30 s, etc.).

> [!IMPORTANT]
> **Pregunta 6:**
> En los Labs 2 a 4 usted validó la arquitectura con pruebas de carga. Con base en sus resultados de este laboratorio, ¿qué demostró este experimento que una prueba de carga no habría podido demostrar? Y al revés: ¿qué riesgo de disponibilidad de Cheapest solo se descubre con una prueba de carga? Dé al menos un ejemplo concreto de cada lado, tomado de sus datos o de los laboratorios anteriores, y concluya cuándo usaría cada tipo de experimento.

## 7. Entregables

Entregue un informe organizado con los siguientes numerales.

### 7.1 Resultados

#### 7.1.1 Fichas de los experimentos

Las tres fichas (estado estable, tormenta de reintentos y caída de Inventario), con todos sus campos, **tal como las escribió antes de ejecutar cada experimento**: la hipótesis antes de la fase local y la predicción para AWS antes de la fase AWS. Si cambió algo del diseño después de ejecutarlo (por ejemplo, la duración del fallo), deje la versión original y agregue al final de la ficha qué cambió y por qué.

#### 7.1.2 ¿Qué se observó?

Describa, sin interpretar todavía, lo que observó en cada experimento, configuración y ambiente: cómo se comportó el estado estable antes, durante y después del fallo, qué endpoints se afectaron y qué mostraron el registro del circuito o los logs del sidecar, los eventos de ECS y el Outbox.

#### 7.1.3 ¿Qué métricas se obtuvieron?

**a. Línea de tiempo por experimento.** Una gráfica por experimento, configuración y ambiente con la disponibilidad percibida y el % de `pending` de las ventas del generador de tráfico por ventana de 10 s, con T_inj y T_rem marcados (a partir de los archivos `*_ventanas.csv`).

**b. Tabla resumen:**

| Experimento | Ambiente | Configuración | Disponibilidad mínima por ventana (tras 30 s) | p99 máximo por ventana (ms) | % de `pending` durante el fallo | TTD (s) | TTR (s) | Consultas a Inventario por pedido | Endpoints afectados |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| Estado estable | Local | Completa | | | | N/A | N/A | | |
| Estado estable | AWS | Completa | | | | N/A | N/A | | |
| Tormenta de reintentos | Local | Sin sidecar | | | | | | | |
| Tormenta de reintentos | Local | Solo reintentos | | | | | | | |
| Tormenta de reintentos | Local | Completa | | | | | | | |
| Tormenta de reintentos | AWS | Completa | | | | | | | |
| Tormenta de reintentos | AWS | Sin sidecar + límite de peticiones | | | | | | | |
| Caída de Inventario | Local | Completa | | | | | | | |
| Caída de Inventario | AWS | Completa | | | | | | | |

**c. Tormenta de reintentos:**

| Ambiente | Configuración | Intentos por pedido | Pedidos completados / pedidos | Consultas a Inventario por pedido | Reintentos del sidecar | Ventas registradas | Pedidos duplicados | Disponibilidad del generador de tráfico (mínima por ventana tras 30 s) | 429 (tormenta / generador) |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Local | Sin sidecar | | | | N/A | | | | N/A |
| Local | Solo reintentos | | | | | | | | N/A |
| Local | Completa | | | | | | | | N/A |
| Local | (Opcional) Sin sidecar, clientes que esperan entre intentos | | | | N/A | | | | N/A |
| AWS | Completa | | | | | | | | N/A |
| AWS | Sin sidecar + límite de peticiones (rate / burst: …) | | | | N/A | | | | |

En la fila de AWS con la configuración completa, los reintentos del sidecar se estiman con los logs de CloudWatch; escriba cómo los obtuvo.

**d. Descomposición del tiempo de recuperación en la caída de Inventario (AWS):**

| Etapa | Hora (UTC) | Segundos desde T_inj | Fuente |
| --- | --- | ---: | --- |
| Tarea detenida (T_inj) | | 0 | |
| Tarea nueva iniciada | | | |
| Target registrado en el target group | | | |
| Target `healthy` | | | |
| Primer `GET /health` 200 (T_rec) | | | |
| Ventas de vuelta al estado estable | | | |

**e. Consistencia (caída de Inventario):**

| Prueba | Ambiente | Filas PENDING máximas | Desde T_rec hasta 0 PENDING (s) | Filas FAILED | Δ cantidad del ítem | Ventas 201 del generador de tráfico | Descuentos duplicados |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Parte 1 — sin clave (2 envíos) | Local | N/A | N/A | N/A | | N/A | |
| Parte 1 — con clave (2 envíos) | Local | N/A | N/A | N/A | | N/A | |
| Parte 2 — caída de Inventario | Local | | | | | | |
| Parte 2 — caída de Inventario | AWS | | | | | | |
| Parte 3 — reinicio de Ventas | Local | | | | N/A | N/A | N/A |

**f. Local frente a AWS:** una tabla corta con las métricas que más cambiaron entre ambientes (por ejemplo, p99 del estado estable, TTD del circuito, tiempo de recuperación de Inventario), el valor en cada uno y su explicación.

Reporte también los seis valores que escogió en `envoy.yaml.tmpl`.

### 7.2 Análisis de resultados

Extensión sugerida para el análisis, la conclusión y la decisión arquitectónica juntos: 3 a 5 páginas, sin contar tablas, gráficas ni capturas. Las respuestas a las preguntas orientadoras no cuentan en ese límite. Donde un punto se cruza con una pregunta orientadora, se indica cuál; respóndalo una sola vez y en el otro lugar haga referencia.

#### 7.2.1 ¿Qué significan los datos frente al escenario de calidad?

Para cada ASR, compare lo medido en AWS con su medida de respuesta e indique si se cumple; use los datos locales para explicar el efecto de cada táctica:

- **Degradación** (con Inventario lento o caído, disponibilidad ≥ 99 % por ventana tras 30 s, p99 < 3000 ms, y CLOSED a más tardar 60 s después del retiro del fallo). Verifíquelo con las ventas del generador de tráfico en la tormenta de reintentos y en la caída de Inventario. ¿Qué diferencia operativa tiene para un tendero recibir una respuesta lenta, un error o `pending_stock_confirmation`? ¿Bajo qué condiciones la degradación es aceptable para el negocio?
- **Tormenta de reintentos** (≤ 2 intentos por pedido tras 30 s, ≤ 2 consultas a Inventario por pedido, y el generador de tráfico cumple la medida de degradación). ¿Qué configuración apaga la tormenta y cuál solo la contiene? ¿Por qué el reintento sin backoff ni jitter empeora una situación de fallo? ¿Por qué el límite de peticiones del stage protege al backend pero no a los demás tenderos? ¿Qué parte del problema solo se resuelve en el cliente (backoff, respetar un 429) y qué parte en el servidor? ¿Qué haría falta para que los pedidos que el cliente reintenta no se registren dos veces?
- **Consistencia** (reconciliación en < 30 s desde T_rec, sin duplicados, y las entregas pendientes sobreviven al reinicio de Ventas). ¿Qué mecanismo garantiza cada una de las tres partes? Si alguna fila quedó en FAILED, ¿qué significa para el negocio y quién debería atenderla?
- **Recuperación** (MTTR ≤ 5 min ante la caída de la tarea de Inventario). ¿Qué etapa dominó el MTTR? ¿Qué parámetros del template la acortarían, y a qué costo?
- **Paso de OPEN a HALF-OPEN.** Con los tiempos que midió en la tormenta de reintentos con la configuración completa (cuándo se abrió el circuito, cada cuánto volvió a HALF-OPEN y cuánto tardó en volver a CLOSED después de T_rem), ¿cuánto tiempo debería permanecer el circuito en OPEN antes de pasar a HALF-OPEN (`base_ejection_time`)? ¿Qué riesgos hay en pasar a HALF-OPEN demasiado pronto frente a demasiado tarde? Aquí se analiza lo que midió; la justificación del valor que configuró va en la respuesta sobre los valores implementados del sidecar.
- **Local frente a AWS.** ¿Qué conclusiones de la fase local se sostuvieron en AWS y cuáles no? ¿Qué no se podía medir en local, y qué habría concluido mal si solo hubiera hecho la fase local? ¿Acertó su predicción para AWS?

#### 7.2.2 ¿Se cumple la hipótesis?

Para la hipótesis de **cada ficha**, y para su predicción para AWS, indique si se cumple, se cumple parcialmente o no se cumple, y con qué dato lo sustenta. Si una hipótesis se refutó, explique qué suposición de su ficha resultó equivocada. Una hipótesis refutada con un buen análisis vale tanto como una confirmada.

### 7.3 Conclusión

#### 7.3.1 ¿Qué se aprendió del experimento?

Más allá de si cada táctica funcionó, reflexione sobre:

- ¿Cómo se complementaron los reintentos y el circuit breaker en sus datos (compare *solo reintentos* con *completa* en la tormenta de reintentos)? El escenario de conflicto entre ambos ya lo planteó en su propuesta de parámetros iniciales; aquí no lo repita.
- ¿Por qué "entrega al menos una vez" más idempotencia no equivale a una garantía distribuida de "exactamente una vez"? ¿Qué requeriría una garantía real de exactamente una vez entre dos servicios con bases de datos independientes?
- ¿Qué le aportó ensayar en local antes de ir a AWS, y qué le habría costado no hacerlo? ¿Qué ventajas concretas tuvo desplegar con CloudFormation frente a la configuración manual del Lab 4? ¿En qué escenarios del negocio de Cheapest (por ejemplo, la expansión a México o Brasil, o un incidente que obligue a reconstruir el ambiente) sería crítica esta capacidad?

La comparación entre experimentos de caos y pruebas de carga ya la respondió en la pregunta sobre caos frente a carga; aquí no la repita.

### 7.4 Decisión arquitectónica

#### 7.4.1 ¿Qué se decide?

Para cada táctica (reintentos con backoff y jitter, circuit breaker con graceful degradation, rate limiting en API Gateway, Outbox con idempotencia, y detección y recuperación automática con health checks de ECS) indique si la **adopta, la modifica o la descarta** para Cheapest, y con qué parámetros. Incluya en su decisión:

- En este laboratorio las tácticas de resiliencia se implementaron en un sidecar y no en el código de negocio. ¿Qué ventajas concretas tuvo este enfoque? Con lo que analizó en la ficha del punto de fallo que el laboratorio no prueba, ¿qué costo de disponibilidad tiene? ¿En qué escenarios el sidecar no sería suficiente y se necesitaría lógica de resiliencia dentro de la aplicación?
- Con lo que observó en la caída de Inventario y lo que analizó en esa misma ficha: ¿cuántas tareas debería tener cada servicio, qué debería revisar el endpoint `/health` y con qué frecuencia debería consultarlo el balanceador?

#### 7.4.2 ¿Qué cambios se hacen a la arquitectura?

- Describa los cambios que quedan en la arquitectura de Cheapest después del experimento: qué componentes nuevos se agregan, con qué configuración y qué reglas de negocio hay que acordar (por ejemplo, cuánto tiempo puede quedar un pedido como pendiente de confirmación de stock, o qué se hace con una venta degradada cuyo descuento queda en FAILED por falta de stock).
- Lea el artículo [Failure Mitigation for Microservices: An Intro to Aperture](https://careersatdoordash.com/blog/failure-mitigation-for-microservices-an-intro-to-aperture/) de DoorDash. ¿Qué problema específico resuelve Aperture que el sidecar Envoy de este laboratorio no resuelve? ¿En qué punto del crecimiento de Cheapest tendría sentido adoptar un enfoque centralizado como ese? Si al analizar los puntos de fallo no probados propuso una capa de este tipo como capacidad adicional, desarróllela aquí.

### 7.5 Respuestas a las preguntas orientadoras

Incluya las respuestas argumentadas a las preguntas planteadas a lo largo del laboratorio. Cada respuesta debe incluir los elementos que pide la pregunta (tablas, gráficas o diagramas) y debe ir más allá de lo superficial. Se repiten aquí para que no tenga que buscarlas:

- **Pregunta 1.** En Cheapest, ¿qué decisión de producto y operación debería tomarse primero cuando aparece una avalancha de reintentos: proteger la disponibilidad percibida (graceful degradation) o proteger la consistencia estricta (rechazar operaciones)? Argumente considerando el impacto en tenderos, el riesgo financiero y el costo de reconciliación posterior.
- **Pregunta 2.** Si usted fuera el líder encargado de llevar estas tácticas a producción en Cheapest, ¿las adoptaría en el mismo orden en que se presentan (reintentos, circuit breaker, rate limiting, Outbox e idempotencia), teniendo en cuenta el riesgo de cada cambio? Describa un plan de adopción que mitigue los riesgos, con etapas, tiempo estimado por etapa y tareas de cada una.
- **Pregunta 3 (partes A y B, se responden y califican juntas).** Parte A: los reintentos, el circuit breaker y el rate limiting pueden entrar en conflicto si se calibran mal. Proponga un conjunto coherente de parámetros iniciales para Cheapest (timeouts, reintentos, umbral de apertura, tiempo de reapertura, rate y burst) y justifique cómo evitaría inestabilidad sistémica. Incluya un escenario concreto en el que usar reintentos y circuit breaker juntos sin coordinación generaría un problema. Parte B: documente los valores que finalmente eligió para cada `TODO` de `envoy.yaml.tmpl`, la justificación cuantitativa de cada uno y cómo garantiza que no violan el ASR de tormenta de reintentos (≤ 2 consultas a Inventario por pedido) ni el p99 del ASR de degradación.
- **Pregunta 4.** Escriba la ficha completa del experimento que probaría uno de los puntos de fallo que el laboratorio no ejercita (el sidecar esencial o la base de datos compartida). Luego identifique al menos dos clases de fallos que las tácticas del laboratorio no resuelven por sí solas, sustentadas con esa ficha y con sus datos de la tormenta de reintentos y la caída de Inventario, y qué capacidad adicional haría falta a mayor escala. Si esa capacidad es una capa centralizada como Aperture, la comparación se desarrolla en la decisión arquitectónica.
- **Pregunta 5.** Describa con precisión el estado de inconsistencia que se produce en cada escenario del experimento de caída de Inventario: (1) ventas registradas durante la caída: ¿qué diferencia hay entre lo que dice la tabla `ventas` y lo que dice `items_inventario.cantidad`?; (2) reintento sin idempotencia: ¿qué invariante de negocio se viola y cómo lo detectaría operacionalmente en Cheapest?
- **Pregunta 6.** ¿Qué demostró este experimento que una prueba de carga no habría podido demostrar? Y al revés: ¿qué riesgo de disponibilidad de Cheapest solo se descubre con una prueba de carga? Dé al menos un ejemplo concreto de cada lado y concluya cuándo usaría cada tipo de experimento.
- **Pregunta 7.** ¿Aprobaría repetir el experimento de caída de Inventario en producción un lunes por la mañana? Si lo aprueba, defina cómo limitaría el radio de impacto, qué condiciones de aborto usaría y con qué umbrales, quién debe estar presente y cómo revertiría. Si no lo aprueba, explique qué tendría que cambiar en la arquitectura para que fuera aceptable.
- **Revisión de la escritura transaccional en `VentaService`.** ¿Qué ocurre si el proceso muere entre el guardado de la venta y el guardado de su fila de Outbox? ¿Por qué la fila de Outbox se crea incluso cuando la venta se registra con graceful degradation? ¿Qué datos lleva la fila de Outbox y son suficientes para lo que necesita `POST /inventory/ventas/desde-outbox`?
- **Revisión del endpoint con idempotencia en Inventario.** ¿Qué ocurre si el proceso de Inventario muere entre el descuento de stock y el guardado de la clave procesada? ¿Puede producirse un descuento sin clave registrada? ¿Por qué se usa como clave de idempotencia el `id` de la fila de Outbox y no el `ventaId`?

### 7.6 Evidencias

Adjunte capturas de:

**Fase local**

- `docker compose ps` con los cinco contenedores arriba y `curl http://localhost:9901/ready` respondiendo `LIVE`.
- `envoy.yaml.tmpl` con los valores completados por el estudiante (los seis `TODO`).
- Respuesta del endpoint de caos al inyectar un fallo (con `injectedAt` y `until`) y al leer el contador `llamadasDisponibilidad`.
- El resumen de `tormenta_reintentos.sh` de cada configuración local de la tormenta, y el registro del circuito (`*_circuito.log`) con *solo reintentos* (sin eyecciones) y con la configuración *completa* (`ejections_active` en 1 y de vuelta a 0 tras la recuperación).
- Parte 1 de la caída de Inventario: la cantidad bajando dos veces sin clave, y el HTTP 409 al repetir con la misma `X-Idempotency-Key`.
- El registro de la Parte 2 en local (`caida_local_outbox.log`) y el resumen del Outbox antes y después del reinicio de Ventas (Parte 3).

**Fase AWS**

- Stack CloudFormation en estado `CREATE_COMPLETE`.
- Actividad post-despliegue: los dos recursos del stack que eligió al explorar lo que se desplegó, con una captura de la consola por cada uno y su explicación.
- Task Definition de Ventas mostrando los **dos containers**: `ventas` y `ventas-sidecar`, y la revisión sin sidecar con un solo container.
- Servicios ECS de los tres microservicios en estado RUNNING.
- Resultado de la consulta de Logs Insights sobre el grupo `/ecs/Cheapest-ventas-sidecar` durante la tormenta con la configuración *completa* (intervalos con `503 UH`, circuito OPEN, y regreso a `200 -` tras la recuperación).
- Configuración del límite de peticiones del stage en API Gateway y el resumen de `tormenta_reintentos.sh` de las dos configuraciones de AWS (con las respuestas 429 cuando aplique).
- Eventos del servicio `svc-Cheapest-inventario` durante la caída de Inventario y gráfica de `HealthyHostCount`/`UnHealthyHostCount` de su target group.
- Registro de la caída en AWS (`caida_aws_outbox.log`) mostrando las filas PENDING acumulándose y bajando a 0 tras T_rec, y la cantidad del ítem antes y después.

Adjunte también:

- Los CSV del generador de tráfico y de la tormenta de cada experimento, configuración y ambiente (o un enlace a ellos).
- Los prompts utilizados (si usó IA).
- Los scripts adicionales que haya escrito (si aplica).

### 7.7 Formato de entrega

Un informe en PDF o Word con los numerales de resultados (incluidas las fichas), análisis de resultados, conclusión, decisión arquitectónica, respuestas a las preguntas orientadoras y evidencias.

> [!IMPORTANT]
> **¿A dónde se suben los entregables?**
> A la Actividad correspondiente en el aula de Bloque Neón de su sección.

## Nota final (créditos AWS)

Cuando termine la fase AWS, elimine todos los recursos para evitar consumo innecesario de créditos:

```bash
aws cloudformation delete-stack --stack-name Cheapest-lab5 --region us-east-1
```

Verifique en la consola que el stack pase a estado `DELETE_COMPLETE` y que no queden recursos huérfanos (especialmente instancias RDS e imágenes en ECR). Apague también el ambiente local con `docker compose down`.
