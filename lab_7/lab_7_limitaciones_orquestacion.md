# Lab 7 — Limitaciones de los Microservicios Orientados a Conexión: Fan-out y Latencia compuesta

## Etapas del laboratorio

| Etapa | Resumen | Uso de IA generativa |
| --- | --- | --- |
| 1. Experimento y ASRs | Definición del escenario de orquestación síncrona y criterios de quiebre. | Uso acotado para ordenar hipótesis; la priorización de ASRs debe ser propia. |
| 2. Análisis arquitectónico | Evaluación del patrón de orquestación síncrona, fan-out y compounding de latencia. | Recomendado para contrastar trade-offs y construir los modelos cuantitativos. |
| 3. Despliegue en AWS | Publicación de imágenes desde la rama `microservices-2`, configuración de ECS y API Gateway. | Recomendado para asistencia operativa con verificación manual en AWS. |
| 4. Pruebas de carga en tres fases | Baseline individual → orquestado bajo carga → orquestado con servicio dependiente degradado. | Recomendado para automatizar experimentos y documentar métricas por fase. |
| 5. Interpretación y entregables | Análisis de fan-out, compounding y quiebre de ASRs. | No recomendado para generar conclusiones sin evidencia cuantitativa propia. |

## Objetivos

- Identificar el punto de quiebre de un endpoint que orquesta múltiples microservicios síncronamente.
- Cuantificar el efecto de **latencia compuesta** y **amplificación de carga (fan-out)** producidos por el patrón de orquestación síncrona por HTTP.
- Comparar el comportamiento bajo carga del endpoint orquestado frente a los servicios individuales y evidenciar la diferencia entre la suma de p99 individuales y el p99 real del orquestador.
- Reflexionar sobre las limitaciones estructurales del patrón de orquestación síncrona y su impacto en los ASRs de Chiper.

## Índice

- [1. Experimento](#1-experimento)
- [2. Arquitectura](#2-arquitectura)
- [3. Tecnologías](#3-tecnologías)
- [4. Despliegue (AWS)](#4-despliegue-aws)
- [5. Pruebas de carga](#5-pruebas-de-carga)
- [6. Interpretación de resultados](#6-interpretación-de-resultados)
- [7. Entregables](#7-entregables)

---

## 1. Experimento

### 1.1 Descripción

| Elemento | Detalle |
| --- | --- |
| Título | Punto de quiebre del orquestador síncrono en la arquitectura de microservicios de Chiper |
| Propósito | Evidenciar cómo el patrón de orquestación síncrona por HTTP viola los ASRs de latencia y error sin necesidad de inyectar fallos artificiales — la arquitectura lo produce sola bajo carga |
| Resultados esperados | El endpoint orquestado viola ASR-1 a cargas donde los servicios individuales funcionan correctamente; al degradar un servicio dependiente, el error % del orquestador sube al 100% |
| Infraestructura | API Gateway + ECS/Fargate + ECR + RDS + computador personal para JMeter |

### 1.2 Contexto de negocio

Los tenderos de Chiper necesitan una vista consolidada del estado de su tienda para tomar decisiones de reabastecimiento: qué hay en catálogo (Logística), cuánto stock tienen (Inventario) y cuánto han vendido recientemente (Ventas). En un diseño de microservicios orientado a conexión, la forma más directa de entregar esta vista es que el servicio de Ventas llame síncronamente a Logística y a Inventario, consolide los datos y responda.

Este patrón —conocido como **orquestación síncrona**— parece simple y funciona bien a escala baja. El problema emerge bajo carga: la latencia del endpoint consolidado no es el promedio de los tiempos individuales sino su suma. A medida que los servicios dependientes se saturan, cada cola se acumula independientemente, haciendo que el p99 del orquestador se dispare mucho más rápido que el de cualquier servicio individual.

El endpoint nuevo `GET /ventas/resumen-operativo` implementa este patrón: llama secuencialmente a Logística y a Inventario con un **timeout de 8 segundos por llamada**, luego consulta su propia base de datos. El timeout alto es intencional: en microservicios reales, los timeouts generosos son una práctica común para evitar rechazar peticiones válidas en momentos de carga pico. Este laboratorio demuestra que esa configuración, combinada con orquestación síncrona, puede llevar al sistema a un punto de quiebre sin que ningún servicio falle individualmente.

### 1.3 ASRs involucrados

| ID | Descripción | Métrica a satisfacer |
| --- | --- | --- |
| ASR-1 | Como tendero, quiero consultar el resumen operativo de mi tienda en un tiempo razonable para tomar decisiones de reabastecimiento. | p99 < 2000 ms durante operación normal (500 req/min) |
| ASR-2 | Como COO, quiero mantener una baja tasa de error incluso durante eventos de alta demanda para no perder operaciones de tenderos. | Error % ≤ 10% durante pico (5000 req/min) |
| ASR-3 | Como tendero, quiero que si uno de los servicios de Chiper está lento, mi consulta del resumen de tienda siga respondiendo sin fallar por completo. | Con 1 servicio dependiente degradado (desired count reducido a 1 tarea ECS), error % del endpoint orquestado ≤ 30% |

> [!IMPORTANT]
> **Pregunta 1:**
> Antes de ejecutar las pruebas, estime numéricamente (usando la fórmula de la sección 1.4) a qué carga en req/s espera que se viole ASR-1.
> Para su estimación use los p99 individuales medidos en la Fase 1 de las pruebas.
> Compare luego su estimación con el resultado real y explique la diferencia.

### 1.4 Fan-out y latencia compuesta

El **fan-out** describe cuántas peticiones a servicios dependientes genera cada petición al orquestador. La **latencia compuesta** describe cómo las distribuciones de tiempo de respuesta se acumulan en una cadena síncrona. Estas dos propiedades son las razones estructurales por las que el patrón de orquestación síncrona tiene un límite de escalabilidad más bajo que la suma de sus partes.

#### Fan-out de carga

Sea $L$ la tasa de peticiones al orquestador (req/s) y $N$ el número de servicios dependientes que llama síncronamente:

$$F = L \times N$$

Donde $F$ es la carga total adicional generada sobre los servicios dependientes. Si el orquestador recibe 100 req/s y llama a 2 servicios dependientes, cada uno recibe 100 req/s adicionales **por cada** unidad de carga del orquestador.

> Si los servicios dependientes también reciben tráfico directo de otros clientes, la carga efectiva sobre ellos es $L_{\text{dep}} = L_{\text{directo}} + L_{\text{orquestador}}$.

#### Latencia secuencial esperada

Para llamadas secuenciales, la latencia total mínima del orquestador es:

$$T_{\text{orquestado}} \geq \sum_{i=1}^{N} T_i + (N-1) \cdot \delta_{\text{red}}$$

Donde $T_i$ es el tiempo de respuesta del servicio $i$ y $\delta_{\text{red}}$ es el overhead de red por salto (generalmente 1–5 ms en AWS dentro de la misma VPC).

#### Efecto del fan-out sobre la latencia bajo carga

Cuando el orquestador genera carga adicional sobre los servicios dependientes, la latencia de cada uno aumenta por efecto de cola.

$$T_{i,\text{cargado}} \approx \frac{T_{i,\text{baseline}}}{1 - \rho_i}$$

Donde $\rho_i = \lambda_i / \mu_i$ es la utilización del servicio $i$ ($\lambda_i$ = tasa de llegada, $\mu_i$ = capacidad de servicio). Cuando $\rho_i \to 1$, la latencia crece de forma no lineal hacia el infinito.

Como el orquestador incrementa $\lambda_i$ para cada servicio dependiente, **acelera el aumento de $\rho_i$** y, con él, la degradación de latencia.

#### Compounding de percentiles de latencia

El p99 del orquestador bajo carga es **siempre mayor** que la suma de los p99 individuales, ya que las distribuciones de cola no se suman linealmente:

$$p99_{\text{orquestado}} \geq \sum_{i=1}^{N} p99_i$$

En la práctica, bajo carga sostenida, la brecha entre el p99 orquestado y la suma de p99 individuales crece porque las colas en cada servicio se correlacionan temporalmente: cuando el orquestador está bajo pico, todos sus servicios dependientes lo están simultáneamente.

> **Resumen práctico:** con $N=2$ servicios dependientes y $p99_{\text{individual}} = 200\,\text{ms}$ en baseline, el p99 orquestado en baseline es $\geq 400\,\text{ms}$. Bajo carga donde $\rho \approx 0.7$ en cada servicio dependiente, $T_{\text{cargado}} \approx \frac{200}{1-0.7} = 667\,\text{ms}$ por servicio, y el p99 orquestado supera los $1334\,\text{ms}$ — violando ASR-1 antes de llegar a estrés fuerte.

### 1.5 Qué se va a probar

El experimento tiene tres fases progresivas:

**Fase 1 — Baseline por servicio individual**
Medir p99, p95, throughput y error % de cada servicio de forma aislada con la misma matriz de carga. Esto establece la referencia para verificar la fórmula de fan-out.

**Fase 2 — Carga sobre el endpoint orquestado**
Aplicar la misma matriz de carga sobre `GET /ventas/resumen-operativo`. Comparar el p99 real del orquestador con la predicción de la fórmula. Identificar en qué escenario de carga se viola ASR-1.

**Fase 3 — Servicio dependiente degradado**
Reducir el `desired count` de Inventario a 1 tarea en ECS (sin apagarlo, sin inyectar fallos). Observar cómo esta reducción de capacidad impacta el error % del endpoint orquestado. Verificar si ASR-3 se cumple.

> [!IMPORTANT]
> **Pregunta 2:**
> ¿Por qué reducir el `desired count` de Inventario a 1 tarea (sin apagarlo) es un experimento más representativo de una situación real que apagar el servicio por completo?
> Relacione su respuesta con el concepto de **saturación** en la fórmula de fan-out y con escenarios reales de Chiper .

---

## 2. Arquitectura

### 2.1 Diagrama de despliegue

![Diagrama de despliegue](./recursos/diagrama_componentes.png)

La arquitectura de despliegue es idéntica a la del Lab 4. El único cambio visible en tiempo de ejecución es que el servicio de **Ventas** ahora expone un endpoint adicional (`GET /ventas/resumen-operativo`) que, internamente, genera llamadas HTTP síncronas hacia Logística e Inventario antes de responder.

Este cambio no requiere nuevos contenedores ni nuevas rutas de red: el fan-out ocurre dentro del flujo de una petición existente, lo que lo hace difícil de detectar solo con el diagrama de despliegue — y fácil de subestimar en revisiones de arquitectura.

### 2.2 Estilos de arquitectura asociados

| Estilo | Análisis |
| --- | --- |
| Microservicios | Favorece desacoplamiento operativo y escalamiento independiente.<br>Sin embargo, la comunicación HTTP síncrona entre servicios introduce acoplamiento temporal: la disponibilidad del orquestador depende de la disponibilidad **simultánea** de todos sus servicios dependientes. |
| API Gateway | Actúa como punto de entrada centralizado y permite observar el tráfico agregado.<br>No puede distinguir el tráfico de fan-out generado por el orquestador del tráfico directo; esto dificulta el diagnóstico de saturación. |
| Orquestación síncrona | Favorece consistencia de la respuesta al momento de la petición (los datos son actuales).<br>Desfavorece latencia, throughput y resiliencia: el orquestador hereda el p99 más alto de todos sus servicios dependientes y cualquier fallo en cascada. |

### 2.3 Tácticas y sus limitaciones en este escenario

| Táctica | ¿Por qué no resuelve el problema estructural? |
| --- | --- |
| Escalamiento horizontal de ECS (servicios dependientes) | Reduce $\rho_i$ y mejora latencia individual, pero el fan-out sigue multiplicando la carga: escalar los servicios dependientes no elimina el compounding de p99. |
| Timeouts más cortos en el orquestador | Reduce la latencia máxima pero aumenta el error %: cambiar el síntoma no corrige la causa. |
| Retry en el orquestador | Amplifica el fan-out: con 1 reintento, $F = L \times N \times 2$. Empeora la saturación de los servicios dependientes. |
| Cacheo de respuestas de servicios dependientes | Mitiga el fan-out para datos que toleran staleness, pero los datos de stock e inventario requieren consistencia reciente en Chiper. |
| Circuit breaker (sidecar, Lab 5) | Protege al orquestador de un servicio dependiente caído, pero no reduce la latencia compuesta cuando todos funcionan. Solo mueve el problema de latencia a graceful degradation. |

> [!IMPORTANT]
> **Pregunta 3:**
> Proponga **una alternativa arquitectónica** al patrón de orquestación síncrona que permita entregar el resumen operativo a los tenderos con p99 < 500 ms, sin necesidad de que Ventas llame síncronamente a Logística e Inventario en el momento de la petición.
> Analice los trade-offs de su propuesta en términos de consistencia de datos, complejidad operativa y costo de implementación para Chiper.

---

## 3. Tecnologías

| Categoría | Tecnologías |
| --- | --- |
| Gateway de entrada | Amazon API Gateway |
| Orquestación de contenedores | Amazon ECS (Fargate) |
| Registro de imágenes | Amazon ECR |
| Base de datos relacional | Amazon RDS (PostgreSQL) |
| Framework backend | NestJS |
| Lenguaje | TypeScript |
| ORM | TypeORM |
| Pruebas de carga | Apache JMeter |

---

## 4. Despliegue (AWS)

El despliegue de este laboratorio sigue **exactamente los mismos pasos del Lab 4** (ECR + RDS + ECS + API Gateway), con dos diferencias:

1. **Código fuente**: use la rama `microservices-2` del repositorio `chiper-api-microservices`.
2. **Tag de imágenes**: use `3.0.0` para distinguirlas de las versiones anteriores.

Consulte el Lab 4 para el detalle completo de cada paso. A continuación se resume lo que cambia.

### 4.1 Obtener el código de la rama `microservices-2`

```bash
# Desde el directorio del proyecto
git clone <url-repositorio> chiper-api-ms2
cd chiper-api-ms2
git checkout microservices-2
```


### 4.2 Publicar imágenes en ECR

Los tres repositorios son los mismos del Lab 4. Use el tag `3.0.0`.

| Servicio | Nombre repositorio | Tag imagen |
| --- | --- | --- |
| Logística | `chiper-logistica` | `3.0.0` |
| Inventario | `chiper-inventario` | `3.0.0` |
| Ventas | `chiper-ventas` | `3.0.0` |


Tutoriales de apoyo del Lab 4:
- [Subir imágenes Docker a Amazon ECR](../tutoriales/subir_imagenes%20_a_ecr.md)

### 4.3 Configurar RDS, ECS y API Gateway

Siga los pasos 4.2, 4.3 y 4.4 del Lab 4 sin modificaciones.

La única diferencia en ECS es que la Task Definition de **Ventas** requiere dos variables de entorno adicionales para los clientes HTTP del nuevo endpoint:

| Variable | Valor | Descripción |
| --- | --- | --- |
| `INVENTARIO_BASE_URL` | URL interna del ALB de Inventario | Para que Ventas llame a Inventario |
| `INVENTARIO_TIMEOUT_MS` | `8000` | Timeout de 8 s por llamada a Inventario |
| `LOGISTICA_TIMEOUT_MS` | `8000` | Timeout de 8 s por llamada a Logística (sobreescribe el default de 3 s) |

### 4.4 Verificación rápida

```bash
# Nuevo endpoint orquestado
GET https://<API_ID>.execute-api.<REGION>.amazonaws.com/lab/ventas/resumen-operativo
```

El endpoint orquestado debe responder con un JSON que incluya secciones `catalogos`, `inventario` y `ventas`. Verifique que las tres secciones tengan datos antes de iniciar las pruebas de carga.

---

## 5. Pruebas de carga

### 5.1 Fase 1 — Baseline individual

Ejecute la matriz sobre los endpoints individuales **de forma aislada** (un Thread Group a la vez):

- `GET /logistica/logistics/catalogos`
- `GET /inventario/inventory/items`
- `GET /ventas/ventas/ventas`

El objetivo es medir el p99 de cada servicio por separado para alimentar la fórmula de la sección 1.4 y establecer la línea base de comparación.

### 5.2 Fase 2 — Carga sobre el endpoint orquestado

Ejecute la misma matriz sobre `GET /ventas/resumen-operativo`. **No modifique la infraestructura respecto a la Fase 1**: el fan-out ya está incorporado en el endpoint.

### 5.3 Fase 3 — Servicio dependiente degradado

Antes de esta fase:
1. Vaya a ECS → Servicio de Inventario → actualice `desired count` a **1 tarea**.
2. Espere a que ECS rebalancee (puede tardar 1-2 minutos).
3. Ejecute la carga media y alta de la matriz sobre `GET /ventas/resumen-operativo`.

Observe: ¿a partir de qué nivel de carga el error % del endpoint orquestado supera el umbral de ASR-3?

### 5.4 Matriz de pruebas

Use la misma configuración de JMeter de los labs anteriores.

| Test | Ramp-Up | Threads | Loops | Carga aproximada (req/s) |
| --- | --- | --- | --- | --- |
| Smoke test | 5 s | 10 | 1 | 1 |
| Baja carga | 10 s | 40 | 1 | 3 |
| Carga media | 20 s | 200 | 1 | 5 |
| Operación normal | 50 s | 900 | 1 | 9 |
| Alta carga | 75 s | 3 000 | N/A | 20 |
| Estrés | 150 s | 12 000 | N/A | 50 |

> Ejecute al menos **6 repeticiones** para operación normal y estrés para obtener resultados estadísticamente estables.

> [!IMPORTANT]
> **Pregunta 4:**
> Calcule el fan-out real generado sobre Logística e Inventario durante el escenario de "operación normal" (9 req/s al orquestador).
> ¿En qué punto de la Fase 2 el fan-out hace que la utilización $\rho$ de alguno de los servicios dependientes supere 0.7? Use los datos de capacidad medidos en la Fase 1 para estimarlo.
> Muestre el cálculo y compárelo con el comportamiento observado en las métricas de CloudWatch.

---

## 6. Interpretación de resultados

Analice con enfoque en las limitaciones del patrón:

- p99 del endpoint orquestado vs. suma de p99 individuales (Fase 1 vs. Fase 2).
- Fan-out real sobre servicios dependientes medido en CloudWatch (RequestCount del Target Group de Inventario y Logística durante Fase 2 vs. Fase 1).
- Error % del orquestador durante la Fase 3 (servicio dependiente degradado).
- Punto de carga donde se viola cada ASR.

### 6.1 Umbrales por ASR

- **ASR-1**: p99 del endpoint orquestado < 2000 ms. Se verifica en Fase 2 durante "operación normal".
- **ASR-2**: Error % ≤ 10% durante "estrés". Se verifica en Fase 2.
- **ASR-3**: Con Inventario degradado (1 tarea), error % ≤ 30% en "carga media". Se verifica en Fase 3.

### 6.2 Punto de quiebre

Reporte:

- En qué escenario de carga (threads / req/s) se viola ASR-1 por primera vez.
- Si el quiebre fue gradual (p99 subiendo progresivamente) o abrupto (salto repentino).
- Si el patrón de quiebre coincide con la predicción del modelo de fan-out de la sección 1.4.

> [!IMPORTANT]
> **Pregunta 5:**
> Compare el patrón de degradación del endpoint orquestado (Fase 2) con el patrón de degradación de Ventas en el Lab 5 (baseline sin sidecar, con Inventario inyectado con `FAULT_DELAY_MS=5000`).
> ¿Cuál de los dos escenarios llega al quiebre de ASR-1 primero y por qué?
> ¿Qué implicación tiene esto para el diseño de alertas en un sistema de monitoreo real de Chiper?

---

## 7. Entregables

### 7.1 Tablas de resultados

Entregue tres tablas — una por fase:

**Tabla A — Baseline individual (Fase 1)**

| Servicio | # threads | Ramp-up (s) | p99 (ms) | p95 (ms) | Throughput (req/s) | Error % |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Logística | 10 | 5 | | | | |
| Inventario | 10 | 5 | | | | |
| Ventas | 10 | 5 | | | | |
| ... | | | | | | |

**Tabla B — Endpoint orquestado (Fase 2)**

| # threads | Ramp-up (s) | p99 (ms) | p95 (ms) | Throughput (req/s) | Error % | p99 predicho (fórmula) |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 10 | 5 | | | | | |
| ... | | | | | | |

Marque en rojo la fila donde se viola ASR-1 por primera vez.

**Tabla C — Servicio dependiente degradado (Fase 3)**

| # threads | Ramp-up (s) | p99 (ms) | Error % | ASR-3 cumplido |
| ---: | ---: | ---: | ---: | --- |
| 200 | 20 | | | Sí / No |
| 3 000 | 75 | | | Sí / No |

### 7.2 Evidencias

Adjunte capturas de:

- Configuración de API Gateway y la ruta `/ventas/*` apuntando al ALB de Ventas.
- Servicios ECS en estado RUNNING (Logística, Inventario, Ventas).
- RDS en estado disponible.
- CloudWatch: `RequestCount` del Target Group de Inventario durante Fase 1 vs. Fase 2 (en el mismo período de carga), mostrando el efecto de fan-out.
- Configuración de JMeter para cada fase.
- Summary Report por fase.
- Fila donde se viola ASR-1 por primera vez (resaltada en el Summary Report).
- ECS — servicio Inventario con `desired count = 1` durante la Fase 3.

### 7.3 Evidencias y prompts

Adjunte:

- Prompts utilizados (si usó IA).
- Scripts adicionales de carga (si aplica).

### 7.4 Análisis breve

Incluya un análisis de 1 a 2 páginas que responda:

1. ¿En qué nivel de carga se violó ASR-1 y qué tanto difirió el p99 real del predicho por la fórmula? ¿A qué se atribuye la diferencia?
2. ¿Cuál fue el factor de amplificación de carga (fan-out) observado en CloudWatch sobre Inventario y Logística? ¿Coincide con la fórmula $F = L \times N$?
3. ¿El patrón de degradación fue gradual o abrupto? ¿Qué dice esto sobre la robustez del sistema ante variaciones de carga?
4. En la Fase 3, ¿por qué reducir Inventario a 1 tarea provocó errores en el endpoint orquestado aunque Inventario no estuviera "caído"? Explique en términos de $\rho$ y tiempo de respuesta.
5. ¿Qué alternativa arquitectónica propondría para entregar el resumen operativo a los tenderos con p99 < 500 ms? ¿Qué trade-offs introduce esa alternativa en el contexto de Chiper (consistencia, complejidad, costo)?
6. Compare este laboratorio con el Lab 5: ¿qué es más peligroso para Chiper — un fallo explícito de un servicio (que dispara alertas inmediatas) o una degradación silenciosa por saturación de fan-out (que puede pasar desapercibida)? Justifique.
7. Si el equipo de Chiper decidiera implementar las tácticas del Lab 5 (circuit breaker + graceful degradation) sobre el endpoint de este laboratorio, ¿resolvería el problema de compounding de latencia? ¿Qué problema sí resolvería y cuál quedaría abierto?

---

## Nota final (créditos AWS)

Cuando termine:

- Detenga o elimine los servicios ECS, la instancia RDS, el API Gateway y los artefactos en ECR que no sean necesarios.
