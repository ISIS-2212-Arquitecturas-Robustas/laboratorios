# Lab 2 — Pruebas de Carga al Monolito de Cheapest

## Índice
- [Etapas del laboratorio](#etapas-del-laboratorio)
- [Objetivos](#objetivos)
- [Descripción del Experimento](#descripción-del-experimento)
- [ASRs evaluados](#asrs-evaluados)
- [Diagrama de despliegue](#diagrama-de-despliegue)
- [Estilos de arquitectura](#estilos-de-arquitectura)
- [Tecnologías asociadas](#tecnologías-asociadas)
- [Preparación del entorno](#preparación-del-entorno)
- [Diseño de la prueba de carga](#diseño-de-la-prueba-de-carga)
- [Pruebas de carga](#pruebas-de-carga)
- [Entregables](#entregables)

## Etapas del laboratorio

| Etapa                           | Resumen                                                                                | Uso de IA generativa                                                                          |
| ------------------------------- | -------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| 1. Contexto experimental y ASRs | Definición del experimento, criterios de éxito y marco de evaluación del monolito.     | Uso acotado para entender ASRs; el análisis de impacto debe ser propio.                     |
| 2. Preparación del entorno      | Levantamiento de base de datos, backend y verificación inicial del entorno de pruebas. | Recomendado para resolver bloqueos técnicos de instalación y configuración.                   |
| 3. Diseño de pruebas            | Definición de distribución de datos, matriz de carga e hipótesis de degradación.       | Puede ayudar a proponer diseños, pero se debe justificar con el contexto de Cheapest. |
| 4. Ejecución de pruebas         | Ejecución con JMeter y opción de script en Python para cargas altas.                   | Recomendado en cargas altas para generar o ajustar scripts de prueba y análisis.              |
| 5. Entregables y conclusiones   | Reporte de resultados, punto de inflexion y propuestas de mejora arquitectónica.       | No recomendado para redactar conclusiones sin evidencia del experimento.                      |

## Objetivos

- Ejecutar **pruebas de carga locales** sobre el backend monolítico de Cheapest.
- Encontrar el **punto de inflexión** del sistema (máximo de usuarios/hilos antes de incumplir un ASRs).
- Analizar el comportamiento del monolito bajo carga: latencia, throughput, errores y cuellos de botella.
- Proponer mejoras de arquitectura y tácticas para mejorar desempeño y disponibilidad.

## Descripción del Experimento

| **Título del experimento**    | Prueba de carga al backend monolítico de Cheapest                                                                                                                                                                                                                                      |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Propósito**                 | Determinar el punto de inflexión del sistema bajo carga concurrente de dos endpoints críticos <br><br>- Servicio GET de consulta con múltiples JOINs<br>- Servicio POST de escritura de una entidad extensa                                                                          |
| **Sistema bajo prueba**       | Backend monolítico Cheapest (NestJS + PostgreSQL)                                                                                                                                                                                                                                      |
| **Resultados esperados**      | - Obtener el punto de inflexión (número máximo de usuarios en que los requerimientos no funcionales, e.g., ASR1 y ASR2, se dejan de respetar) de los servicios REST del sistema. |
| **Infraestructura requerida** | Local (Node.js + PostgreSQL en Docker opcional)<br><br>Cliente local pruebas (JMeter o script propio) |

## ASRs evaluados

| ID    | Descripción                                                                                                                                                                                                                                                           | Medidas de respuesta a satisfacer |
| ----- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------- |
| ASR 1 | Como tendero, quiero consultar los productos que alguna vez he pedido, que actualmente estén en promoción y disponibles en el catálogo de mi zona, con una latencia p99 de **1000 ms** en operación normal (500 req/min).                                                       | Latencia p99 < 1000ms |
| ASR 2 | Como director de operaciones de Cheapest, durante eventos con promociones en donde múltiples tiendas están comprando, quiero que al menos el **98% de los pedidos** sean creados exitosamente, aun cuando un alto número de tenderos realicen pedidos simultáneamente, se estiman (5000 req/min). | Error % ≤ 2%          |


> **Criterio de punto de inflexión:** *basta con que se incumpla **al menos uno** de los dos ASRs.*



Los dos endpoints evaluados en este laboratorio corresponden directamente a los ASRs definidos. Ambos forman parte del módulo `logistica` del backend monolítico de Cheapest.

---

### ASR 1 — GET `/logistics/tenderos/productos-disponibles`

**Método:** `GET`  
**Ruta:** `/logistics/tenderos/productos-disponibles`

**Query params:**

| Parámetro  | Tipo   | Validación        | Descripción                                |
| ---------- | ------ | ----------------- | ------------------------------------------ |
| `tiendaId` | string | UUID, requerido   | Identificador de la tienda del tendero     |
| `zona`     | string | string, requerido | Zona geográfica sobre la que se consulta   |

**Ejemplo de request:**
```
GET /logistics/tenderos/productos-disponibles?tiendaId=9a2f2e7b-40c4-4c5f-a37c-baf722e18ab9&zona=Zona+Norte
```

**Respuesta exitosa (200):** arreglo de productos con campos `id`, `nombre`, `marca`, `categoria`, `presentacion`, `precioBase`, entre otros.

**Lógica interna (múltiples consultas secuenciales a la base de datos):**
1. Recupera todos los pedidos históricos de la tienda y extrae sus `productoId`.
2. Filtra las promociones activas (fecha vigente + tienda incluida) y extrae sus `productoId`.
3. Obtiene los catálogos de la zona y consulta disponibilidad > 0 para cada uno.
4. Calcula la intersección de los tres conjuntos y resuelve el detalle de cada producto.

> Este endpoint realiza varios JOINs sobre tablas con una cantidad considerable de datos

---

### ASR 2 — POST `/logistics/pedidos`

**Método:** `POST`  
**Ruta:** `/logistics/pedidos`  
**Content-Type:** `application/json`

**Body (ejemplo con 10 ítems):**
```json
{
  "identificador": "PED-20260601-001",
  "tiendaId": "9a2f2e7b-40c4-4c5f-a37c-baf722e18ab9",
  "fechaHoraCreacion": "2026-06-01T10:00:00.000Z",
  "montoTotal": 150000,
  "monedaId": "<uuid-moneda>",
  "estado": "PENDIENTE",
  "items": [
    { "productoId": "<uuid>", "cantidad": 5, "precioUnitario": 12000, "descuento": 0,   "monedaId": "<uuid-moneda>" },
    { "productoId": "<uuid>", "cantidad": 3, "precioUnitario": 8500,  "descuento": 500, "monedaId": "<uuid-moneda>" }
  ]
}
```

**Campos requeridos del body:**

| Campo               | Tipo             | Descripción                               |
| ------------------- | ---------------- | ----------------------------------------- |
| `identificador`     | string (max 100) | Código único del pedido                   |
| `tiendaId`          | UUID             | Tienda que realiza el pedido              |
| `fechaHoraCreacion` | ISO 8601         | Fecha y hora de creación                  |
| `montoTotal`        | number > 0       | Valor total del pedido                    |
| `monedaId`          | UUID             | Moneda en que se expresa el monto         |
| `estado`            | enum (opcional)  | Estado inicial del pedido                 |
| `items`             | array (mín. 1)   | Productos con `productoId`, `cantidad`, `precioUnitario`, `descuento` y `monedaId` |

**Respuesta exitosa (201):** objeto pedido creado con su `id` y lista de ítems.

> Este endpoint realiza escritura transaccional en la base de datos. Bajo alta concurrencia puede generar contención de locks y saturación del pool de conexiones.

---


> [!IMPORTANT]
> **Pregunta 1:**
> En el contexto de Cheapest, el endpoint GET evaluado combina lectura histórica, promociones y disponibilidad por zona, mientras el POST confirma pedidos en eventos de alta demanda.
> Si solo pudiera optimizar **uno** antes de un pico comercial, ¿cuál priorizaría y por qué?
>
> Argumente su decisión en términos de:
> - impacto en negocio,
> - riesgo de incumplimiento de ASRs,
> - tipo de carga,
> - y costo/tiempo de implementación de mejoras.

## Diagrama de despliegue

<img src="recursos/Pasted image 20260304160111.png"/>

*Figura 1. Despliegue de los componentes del backend monolítico de Cheapest (API, base de datos) sobre un único nodo de ejecución local.*

Note que todos los componentes están desplegados en un único nodo de ejecución, en este caso su máquina local, de igual forma note que la comunicación entre componentes sigue los mismos protocolos que seguiría si se ejecutaran en nodos distintos.

## Estilos de arquitectura

| Estilos de Arquitectura asociados | Análisis |
| --------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| Monolito                          | - Favorece latencia y testeabilidad.<br>- Desfavorece escalabilidad y disponibilidad.                                     |
| Cliente-servidor                  | - Favorece seguridad (el control de acceso a los datos es centralizado).<br>- Puede introducir un cuello de botella o punto único de falla en el servidor si este no se replica; esto no descarta que el servidor pueda escalarse horizontalmente. |
| Capas                             | - Favorece la mantenibilidad y la flexibilidad del sistema.<br>- Desfavorece latencia y aumenta la complejidad.           |

## Tecnologías asociadas

| Tecnologías asociadas         | Selección y Justificación                                                                                                                                                                          |
| ----------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Frameworks**                | - **NestJS:** Framework backend para Node.js basado en TypeScript que promueve arquitectura modular, inyección de dependencias y separación por capas, facilitando mantenibilidad y escalabilidad. |
| **Lenguajes de programación** | - **TypeScript:** Lenguaje principal del backend, aporta tipado estático y mayor robustez en el desarrollo.                                                                                        |
| **Plataforma de ejecución**   | - **Node.js:** Entorno de ejecución basado en event loop, adecuado para aplicaciones I/O intensivas como APIs REST.                                                                                |
| **Bases de datos**            | - **PostgreSQL:** Base de datos relacional robusta que soporta transacciones ACID, índices avanzados y optimización de consultas complejas (JOINs).                                                |
| **Herramientas de análisis**  | - **Apache JMeter:** Herramienta de pruebas de carga utilizada para simular concurrencia y medir latencia, throughput y porcentaje de error.                                                      |
| **Contenedores (opcional)**   | - **Docker:** Permite levantar servicios en entornos aislados para facilitar reproducibilidad del experimento.                                                                                     |
| **Librerías**                 | - **TypeORM:** ORM utilizado por NestJS para mapear entidades a tablas y manejar consultas, relaciones y transacciones.                                                                            |


## Preparación del entorno
En el repo del backend ([Cheapest-api](https://github.com/ISIS-2212-Arquitecturas-Robustas/Cheapest-api)) diríjase a la rama `load_tests`:

```bash
git checkout load_tests
```

### Levantar PostgreSQL con Docker (recomendado)

Ejecute el siguiente comando **desde el directorio base del repositorio** (donde se encuentra el archivo `docker-compose.yml`); si lo ejecuta desde otro directorio, Docker no encontrará el archivo y fallará. El flag `up` crea (si no existe) y levanta el contenedor definido en el `docker-compose.yml` para el servicio `postgres`, dejándolo corriendo en segundo plano (`-d`):

```bash
docker compose up postgres -d
```

> [!WARNING]
> Si en un laboratorio anterior levantó una base de datos con el mismo nombre de contenedor (`cheapest-postgres`) y no va a reutilizarla, es muy probable que el puerto `5432` siga ocupado y el comando anterior falle con un error similar a:
> ```
> Error response from daemon: failed to set up container networking: driver failed programming external connectivity on endpoint cheapest-postgres (5d86a48a3d107d38bfa708e8f6a067bf9cf5210839d04ff07a5e176bd25d855e): Bind for 0.0.0.0:5432 failed: port is already allocated
> ```
> Antes de levantar el nuevo entorno, limpie el contenedor del laboratorio anterior:
> ```bash
> docker stop cheapest-postgres
> docker rm cheapest-postgres
> ```
> o alternativamente detenga el `docker-compose` del laboratorio previo desde su propio directorio.

### Levantar el backend monolítico

```bash
npm install
npm run start:dev
```

Verifique que la aplicación está corriendo:
- http://localhost:3000/health

Usted debería ver algo así:

<img src="recursos/Pasted image 20260305024253.png"/>

## Diseño de la prueba de carga

Hay dos escenarios de carga importantes para este laboratorio (tomados de los ASRs):
- **Operación normal:** 500 req/min (≈ 8.3 req/s).
- **Evento de promociones (pico):** 5000 req/min (≈ 83.3 req/s).

El objetivo de las pruebas en un primer momento es **simular los escenarios** basados en las necesidades de negocio. Note también que las pruebas de carga no tendrán los mismos resultados para un diferente número de datos, por esa razón en el proyecto base se agrega un script (como provider de Nest) para agregar un número de datos. El script se encuentra en la siguiente ruta `src/datasources/database-seeder.service.ts` puede configurar el número de entidades, el número de tiendas y zonas, y la distribución modificando `src/datasources/load-seed.yaml`

> [!WARNING]
> Su tarea es diseñar el número y la distribución de datos en las tablas para que las pruebas tengan sentido. Para mayor facilidad el script lee un archivo `yaml` en donde usted puede definir el número de datos por cada prueba. **En los entregables tiene que justificar el número de datos y distribución para cada prueba y la justificación de los mismos**
> Dado que debe modificar múltiples veces el número de datos. Puede eliminar el volumen de docker (datos persistentes) para cada prueba usando los siguientes comandos:
> ```bash
> docker compose stop postgres
> docker compose rm -f -v postgres
> ```
> De igual forma en el archivo `src/datasources/seed.sql` va a encontrar IDs de ejemplo que serán creados cada vez que ejecute el script. Dado que el resto de datos (y por ende IDs) son aleatorios, le serán de ayuda para el cuerpo de las peticiones al momento de ejecutar las pruebas. Por ejemplo: `tiendaId = bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb`, `zona = Zona Norte`, `monedaId = cccccccc-cccc-4ccc-8ccc-cccccccccccc` y `productoId = aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa`.

Las pruebas en JMeter se definen con los siguientes parámetros
#### Threads:
Indica el número de threads que se lanzarán en 1 Loop (Iteración).
#### Ramp-Up Period:
Tiempo en segundos en los cuales se deben lanzar los threads. Para el primer caso de prueba será de 5 segundos, lo cual indica que 5 threads se crearan y enviaran peticiones en 5 segundos. Cada petición creada se enviará cada segundo:
#### Loop Count (Iteraciones):
Indica el número de iteraciones que se van a hacer del escenario de prueba. En cada iteración se van a ejecutar el no. de threads indicados en el primer parámetro (i.e., number of threads). 
### Matriz mínima de pruebas (mínimo recomendado)
Haga al menos **8 ejecuciones** de los escenarios de operación normal y estrés fuerte, para las otras ejecute al menos 4 veces (más si el quiebre no es claro):

| Test                 | Ramp-Up | Threads | Loops | Throughput objetivo (req/s)     |
| -------------------- | ------- | ------- | ----- | -------------------------------- |
| **Smoke test**       | 5s      | 5       | 1     | 1                               |
| **Baja carga**       | 10s     | 30      | 1     | 3                               |
| **Carga media**      | 20s     | 100     | 1     | 5                               |
| **Operación normal** | 50s     | 450     | 1     | 9                               |
| **Alta carga**       | 75s     | 1500    | N/A   | 20                              |
| **Muy alta carga**   | 100s    | 3000    | N/A   | 30                              |
| **Estrés**           | 150s    | 7500    | N/A   | 50                              |
| **Estrés fuerte**    | 200s    | 18000   | N/A   | 90                              |

## Pruebas de carga

A continuación, descargue Apache JMeter en su máquina personal y realice las pruebas de carga indicados en la sección anterior (Matriz mínima de pruebas).

Descargue el archivo [`load_test.jmx`](recursos/load_test.jmx) el cual contiene las pruebas GET y POST.

El siguiente [recurso](https://testertina.medium.com/a-beginners-guide-to-performance-testing-with-apache-jmeter-be7a7eb0a6ad) contiene información de que componentes tiene JMeter, apréndalos para modificar los argumentos necesarios en el test que le proveemos.

Si no tiene JMeter instalado, descárguelo desde la [página oficial de descarga](https://jmeter.apache.org/download_jmeter.cgi). Requisito previo: JMeter necesita una versión de **Java (JDK) 8 o superior** instalada y configurada en el `PATH` (verifique con `java -version`); una instalación de Java faltante o incorrecta es una causa frecuente de errores confusos al intentar arrancar JMeter. Pasos generales de instalación:
- **Windows:** descargue el `.zip` (binario) desde la página oficial, descomprímalo en una carpeta de su preferencia y ejecute `bin\jmeter.bat`.
- **macOS:** descargue el `.tgz` desde la página oficial (o instale con `brew install jmeter`), descomprímalo y ejecute `bin/jmeter.sh`. También puede requerir que Java esté instalado (`brew install openjdk`).
- **Linux:** descargue el `.tgz`, descomprímalo (`tar -xzf apache-jmeter-x.x.tgz`) y ejecute `bin/jmeter.sh`. Asegúrese de tener el JDK instalado (por ejemplo `sudo apt install default-jdk`).

#### Ejecución de pruebas de carga alta

> [!NOTE]
> JMeter se usa en este laboratorio para los escenarios de carga baja, media y de operación normal (hasta **450 threads**), ya que permite visualizar y aprender de forma gráfica los componentes de una prueba de carga (ese es su valor pedagógico). Para escenarios de **más de 450 threads**, JMeter deja de ser una herramienta confiable en este entorno, por lo que el uso de un script propio en Python **es obligatorio** (no una alternativa opcional) para esos escenarios.

Para escenarios de alta carga > 450 threads, dado que JMeter empieza a tener limitaciones de performance, **debe usar copilot o el agente de IA de su preferencia para generar un script para la ejecución de pruebas**, este script debe tener las siguientes características:
- Las peticiones deben ser http a los endpoints a los cuales se busca hacer la prueba
- El script debe permitir configurar Ramp-Up y Threads para cada prueba
- Para POST, usar un body JSON realista de “pedido grande” con > 20 ítems (productoId y cantidad)
- Debe registrar por request: timestamp, método, endpoint, status_code, latency_ms, error (si aplica).
- Debe calcular al final:  
	- total requests por tipo (GET/POST)  
	- throughput (req/s)  
	- latencia promedio, p95 y p99 por tipo  
	- Error % por tipo (status >= 400 + timeouts + connection errors)
- Idealmente debería generar la tabla y gráficos para **SU** análisis

Les dejamos un prompt de ejemplo, note que debe cambiar algunos valores para ajustarlo al laboratorio
```
Vamos a realizar pruebas de performance. Necesito un script en Python para ejecutar pruebas de carga ligeras contra un backend NestJS usando HTTP.

Contexto:
- Base URL: http://localhost:3000
- Endpoints a probar:
  - Endpoint GET (lectura pesada): `/logistics/tenderos/productos-disponibles?tiendaId=<uuid>&zona=<zona>`
  - Endpoint POST (escritura): `/logistics/pedidos`

Requerimientos del script:
* Debe permitir configurar por argumentos CLI o variables:
   - --endpoint (endpoint a testear)
   - --users (concurrencia máxima)
   - --ramp-up (segundos)
   - --duration (segundos)
   - --body (para POST, un JSON con > 20 ítems)

* Para POST, usar un body JSON realista de “pedido grande” con > 20 ítems (productoId y cantidad).

* Debe registrar por request: timestamp, método, endpoint, status_code, latency_ms, error (si aplica).
* Debe calcular al final:
   - total requests por tipo (GET/POST)
   - throughput (req/s)
   - latencia promedio, p95 y p99 por tipo
   - Error % por tipo (status >= 400 + timeouts + connection errors)
* Debe exportar resultados a CSV: results_get.csv y results_post.csv con columnas:
   timestamp_iso,status_code,latency_ms,error
* Debe imprimir un resumen final claro en consola. Opcionalmente, generar gráficos de latencia y throughput usando matplotlib o seaborn.

Restricciones:
- Usa solo librerías estándar o, si necesitas, sugiere instalar exactamente UNA librería: httpx o aiohttp. Prefiero async/await.
- Maneja timeouts y errores de conexión, debes registrarlos.
- Incluye instrucciones de ejecución y ejemplo:
  python load_test.py --users 100 --ramp-up 50 --duration 60 --endpoint POST --body sample_body.json
```

Como estudiante usted tiene acceso a Github copilot para generación de código, este [tutorial](../tutoriales/como_usar_github_copilot.md) le explicará como usarlo

## Entregables

> [!WARNING]
> - Todos los entregables deben estar bien organizados y 
> documentados en un archivo de Word o PDF.
> - Las capturas de pantalla mostrando la ejecución del laboratorio son tan importantes como los resultados
> - Incluir los prompts utilizados para la generación de pruebas

1. Complete la siguiente tabla con los resultados que obtuvo en las pruebas del laboratorio. En el documento deben ir las capturas de pantalla como evidencia de las pruebas realizadas. Estas capturas incluyen el "Summary report", las configuraciones de JMeter.

> [!IMPORTANT]
> No es suficiente con reportar únicamente los escenarios de operación normal y evento de promociones; se espera que documente el incremento progresivo de carga y las repeticiones indicadas en la [matriz mínima de pruebas](#matriz-mínima-de-pruebas-mínimo-recomendado), con el fin de ubicar con precisión el punto de inflexión. Como mínimo debe reportar **8 corridas** para los escenarios de **operación normal** y **estrés fuerte**, y al menos **4 corridas** para cada uno de los demás escenarios (smoke test, baja carga, carga media, alta carga, muy alta carga y estrés).

| Test / Escenario     | Corrida | Threads | Ramp-up | p99 (ms) | p95 (ms) | Throughput | Error % |
| --------------------- | ------- | ------- | ------- | -------- | -------- | ---------- | ------- |
| Smoke test             | 1       | &nbsp;  | &nbsp;  | &nbsp;   | &nbsp;   | &nbsp;     | &nbsp;  |
| Smoke test             | 2       | &nbsp;  | &nbsp;  | &nbsp;   | &nbsp;   | &nbsp;     | &nbsp;  |
| Smoke test             | 3       | &nbsp;  | &nbsp;  | &nbsp;   | &nbsp;   | &nbsp;     | &nbsp;  |
| Smoke test             | 4       | &nbsp;  | &nbsp;  | &nbsp;   | &nbsp;   | &nbsp;     | &nbsp;  |
| Baja carga             | 1       | &nbsp;  | &nbsp;  | &nbsp;   | &nbsp;   | &nbsp;     | &nbsp;  |
| Baja carga             | 2       | &nbsp;  | &nbsp;  | &nbsp;   | &nbsp;   | &nbsp;     | &nbsp;  |
| Baja carga             | 3       | &nbsp;  | &nbsp;  | &nbsp;   | &nbsp;   | &nbsp;     | &nbsp;  |
| Baja carga             | 4       | &nbsp;  | &nbsp;  | &nbsp;   | &nbsp;   | &nbsp;     | &nbsp;  |
| Carga media            | 1       | &nbsp;  | &nbsp;  | &nbsp;   | &nbsp;   | &nbsp;     | &nbsp;  |
| Carga media            | 2       | &nbsp;  | &nbsp;  | &nbsp;   | &nbsp;   | &nbsp;     | &nbsp;  |
| Carga media            | 3       | &nbsp;  | &nbsp;  | &nbsp;   | &nbsp;   | &nbsp;     | &nbsp;  |
| Carga media            | 4       | &nbsp;  | &nbsp;  | &nbsp;   | &nbsp;   | &nbsp;     | &nbsp;  |
| Operación normal       | 1       | &nbsp;  | &nbsp;  | &nbsp;   | &nbsp;   | &nbsp;     | &nbsp;  |
| Operación normal       | 2       | &nbsp;  | &nbsp;  | &nbsp;   | &nbsp;   | &nbsp;     | &nbsp;  |
| Operación normal       | 3       | &nbsp;  | &nbsp;  | &nbsp;   | &nbsp;   | &nbsp;     | &nbsp;  |
| Operación normal       | 4       | &nbsp;  | &nbsp;  | &nbsp;   | &nbsp;   | &nbsp;     | &nbsp;  |
| Operación normal       | 5       | &nbsp;  | &nbsp;  | &nbsp;   | &nbsp;   | &nbsp;     | &nbsp;  |
| Operación normal       | 6       | &nbsp;  | &nbsp;  | &nbsp;   | &nbsp;   | &nbsp;     | &nbsp;  |
| Operación normal       | 7       | &nbsp;  | &nbsp;  | &nbsp;   | &nbsp;   | &nbsp;     | &nbsp;  |
| Operación normal       | 8       | &nbsp;  | &nbsp;  | &nbsp;   | &nbsp;   | &nbsp;     | &nbsp;  |
| Alta carga             | 1       | &nbsp;  | &nbsp;  | &nbsp;   | &nbsp;   | &nbsp;     | &nbsp;  |
| Alta carga             | 2       | &nbsp;  | &nbsp;  | &nbsp;   | &nbsp;   | &nbsp;     | &nbsp;  |
| Alta carga             | 3       | &nbsp;  | &nbsp;  | &nbsp;   | &nbsp;   | &nbsp;     | &nbsp;  |
| Alta carga             | 4       | &nbsp;  | &nbsp;  | &nbsp;   | &nbsp;   | &nbsp;     | &nbsp;  |
| Muy alta carga         | 1       | &nbsp;  | &nbsp;  | &nbsp;   | &nbsp;   | &nbsp;     | &nbsp;  |
| Muy alta carga         | 2       | &nbsp;  | &nbsp;  | &nbsp;   | &nbsp;   | &nbsp;     | &nbsp;  |
| Muy alta carga         | 3       | &nbsp;  | &nbsp;  | &nbsp;   | &nbsp;   | &nbsp;     | &nbsp;  |
| Muy alta carga         | 4       | &nbsp;  | &nbsp;  | &nbsp;   | &nbsp;   | &nbsp;     | &nbsp;  |
| Estrés                 | 1       | &nbsp;  | &nbsp;  | &nbsp;   | &nbsp;   | &nbsp;     | &nbsp;  |
| Estrés                 | 2       | &nbsp;  | &nbsp;  | &nbsp;   | &nbsp;   | &nbsp;     | &nbsp;  |
| Estrés                 | 3       | &nbsp;  | &nbsp;  | &nbsp;   | &nbsp;   | &nbsp;     | &nbsp;  |
| Estrés                 | 4       | &nbsp;  | &nbsp;  | &nbsp;   | &nbsp;   | &nbsp;     | &nbsp;  |
| Estrés fuerte          | 1       | &nbsp;  | &nbsp;  | &nbsp;   | &nbsp;   | &nbsp;     | &nbsp;  |
| Estrés fuerte          | 2       | &nbsp;  | &nbsp;  | &nbsp;   | &nbsp;   | &nbsp;     | &nbsp;  |
| Estrés fuerte          | 3       | &nbsp;  | &nbsp;  | &nbsp;   | &nbsp;   | &nbsp;     | &nbsp;  |
| Estrés fuerte          | 4       | &nbsp;  | &nbsp;  | &nbsp;   | &nbsp;   | &nbsp;     | &nbsp;  |
| Estrés fuerte          | 5       | &nbsp;  | &nbsp;  | &nbsp;   | &nbsp;   | &nbsp;     | &nbsp;  |
| Estrés fuerte          | 6       | &nbsp;  | &nbsp;  | &nbsp;   | &nbsp;   | &nbsp;     | &nbsp;  |
| Estrés fuerte          | 7       | &nbsp;  | &nbsp;  | &nbsp;   | &nbsp;   | &nbsp;     | &nbsp;  |
| Estrés fuerte          | 8       | &nbsp;  | &nbsp;  | &nbsp;   | &nbsp;   | &nbsp;     | &nbsp;  |


Responder con evidencia:
1. Describa la distribución de los datos y la razón de los mismos para cada prueba basado en el contexto de Cheapest
2. ¿Cuál fue el punto de inflexión y cuál ASR se rompió primero?
3. Teniendo en cuenta los resultados registrados, ¿el diseño monolítico de arquitectura propuesto en este experimento beneficia el cumplimiento de los ASRs involucrados?
4. En caso afirmativo, explique cómo se beneficiaron los ASRs. De lo contrario, explique qué modificaciones podría hacer a la arquitectura (estilos o tácticas) para cumplir con los ASRs.
5. ¿El patrón de degradación fue gradual o abrupto? ¿En donde se encuentra el cuello de botella de la aplicación?
6. ¿Qué endpoint degradó primero y por qué ocurrió?
