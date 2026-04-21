# Lab 2 — Pruebas de Carga al Monolito de Chiper
## Objetivos

- Ejecutar **pruebas de carga locales** sobre el backend monolítico de Chiper.
- Encontrar el **punto de inflexión** del sistema (máximo de usuarios/hilos antes de incumplir ASRs).
- Analizar el comportamiento del monolito bajo carga: latencia, throughput, errores y cuellos de botella.
- Proponer mejoras de arquitectura y tácticas para mejorar desempeño y disponibilidad.

## Descripción del Experimento

| **Título del experimento**    | Prueba de carga al backend monolítico de Chiper                                                                                                                                                                                                                                      |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Propósito**                 | Determinar el punto de inflexión del sistema bajo carga concurrente de dos endpoints críticos <br><br>- Servicio GET de consulta con múltiples JOINs<br>- Servicio POST de escritura de una entidad extensa                                                                          |
| **Sistema bajo prueba**       | Backend monolítico Chiper (NestJS + PostgreSQL)                                                                                                                                                                                                                                      |
| **Resultados esperados**      | - Obtener el punto de inflexión (número máximo de usuarios en que los requerimientos no funcionales, e.g., REQ1 y REQ2, se dejan de respetar) de los servicios REST del sistema.<br><br>Para determinar esto, usaremos los resultados del “Summary Report” de la herramienta JMeter. |
| **Infraestructura requerida** | Local (Node.js + PostgreSQL en Docker opcional)<br><br>Cliente local pruebas (JMeter)                                                                                                                                                                                                |

## ASRs evaluados

| ID    | Descripción                                                                                                                                                                                                                                                           | Métricas a satisfacer |
| ----- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------- |
| ASR 1 | Como tendero, quiero consultar los productos que alguna vez he pedido, que actualmente estén en promoción y disponibles en el catálogo de mi zona, con un p99 de **1000 ms** en operación normal (500 req/min).                                                       | Latencia p99 < 1000ms |
| ASR 2 | Como tendero, durante eventos con promociones en donde múltiples tiendas están comprando, quiero que al menos el **98% de los pedidos** sean creados exitosamente, aun cuando un alto número de tenderos realicen pedidos simultáneamente, se estiman (5000 req/min). | Error % ≤ 2%          |


> **Criterio de punto de inflexión:** *basta con que se incumpla **al menos uno** de los dos ASRs.*

## Diagrama de despliegue

<img src="recursos/Pasted image 20260304160111.png"/>

Note que todos los componentes están desplegados en un único nodo de ejecución, en este caso su máquina local, de igual forma note que la comunicación entre componentes sigue los mismos protocolos que si se ejecutara en nodos distintos.

## Estilos de arquitectura

| Estilos de Arquitectura asociados | Análisis (Atributos de calidad que favorece y desfavorece)                                                                |
| --------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| Monolito                          | - Favorece latencia y testeabilidad.<br>- Desfavorece escalabilidad y disponibilidad.                                     |
| Cliente-servidor                  | - Favorece seguridad (el control de acceso a los datos es centralizado).<br>- Desfavorece escalabilidad y disponibilidad. |
| Capas                             | - Favorece la mantenibilidad y la flexibilidad del sistema.<br>- Desfavorece latencia y aumenta la complejidad.           |

## Tecnologías asociadas

| Tecnologías asociadas         | Selección y Justificación                                                                                                                                                                          |
| ----------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Frameworks**                | - **NestJS:** Framework backend para Node.js basado en TypeScript que promueve arquitectura modular, inyección de dependencias y separación por capas, facilitando mantenibilidad y escalabilidad. |
| **Lenguajes de programación** | - **TypeScript:** Lenguaje principal del backend, aporta tipado estático y mayor robustez en el desarrollo.                                                                                        |
| **Plataforma de ejecución**   | - **Node.js:** Entorno de ejecución basado en event loop, adecuado para aplicaciones I/O intensivas como APIs REST.                                                                                |
| **Bases de datos**            | - **PostgreSQL:** Base de datos relacional robusta que soporta transacciones ACID, índices avanzados y optimización de consultas complejas (JOINs).                                                |
| **Herramientas de análisis**  | - **Apache JMeter :** Herramienta de pruebas de carga utilizada para simular concurrencia y medir latencia, throughput y porcentaje de error.                                                      |
| **Contenedores (opcional)**   | - **Docker:** Permite levantar servicios en entornos aislados para facilitar reproducibilidad del experimento.                                                                                     |
| **Librerías**                 | - **TypeORM:** ORM utilizado por NestJS para mapear entidades a tablas y manejar consultas, relaciones y transacciones.                                                                            |
## Preparación del entorno

### Levantar PostgreSQL con Docker (recomendado)

```bash
docker run --name chiper-db  -e POSTGRES_PASSWORD=postgres  -e POSTGRES_DB=chiper  -p 5432:5432  -d postgres
```
### Levantar el backend monolítico
En el repo del backend (chiper-api) diríjase a la rama `load-tests y ejecute:

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

El objetivo de las pruebas en un primer momento es **simular los escenarios** basados en las necesidades de negocio. Note también que las pruebas de carga no tendrán los mismos resultados para un diferente número de datos, por esa razón en el proyecto base se agrega un script (como provider de Nest) para agregar un número de datos. El script se encuentra en la siguiente ruta `src/datasources/database-seeder.service.ts` puede configurar el número de entidades modificando `load-seed.yaml`

Para correr la aplicación junto con el script de carga ejecute la aplicación de la siguiente forma `SEED_MODE=load npm run start`


> [!WARNING]
> Su tarea es diseñar el número y la distribución de datos en las tablas para que las pruebas tengan sentido. Para mayor facilidad el script lee un archivo `yaml` en donde usted puede definir el número de datos por cada prueba. **En los entregables tiene que justificar el número de datos y distribución para cada prueba y la justificación de los mismos**

Las pruebas en JMeter se definen con los siguientes parámetros
#### Threads:
Indica el número de threads que se lanzarán en 1 Loop (Iteración).
#### Ramp-Up Period:
Tiempo en segundos en los cuales se deben lanzar los threads. Para el primer caso de prueba será de 5 segundos, lo cual indica que 5 threads se crearan y enviaran peticiones en 5 segundos. Cada petición creada se enviará cada segundo:
#### Loop Count (Iteraciones):
Indica el número de iteraciones que se van a hacer del escenario de prueba. En cada iteración se van a ejecutar el no. de threads indicados en el primer parámetro (i.e., number of threads). 
### Matriz mínima de pruebas (mínimo recomendado)
Haga al menos **8 ejecuciones** de los escenarios de operación normal y estrés fuerte, para las otras ejecute al menos 4 veces (más si el quiebre no es claro):

| Test                 | Ramp-Up | Threads | Loops | Usuarios concurrentes (req/seg) |
| -------------------- | ------- | ------- | ----- | ------------------------------- |
| **Smoke test**       | 5s      | 5       | 1     | 1                               |
| **Baja carga**       | 10s     | 10      | 1     | 3                               |
| **Carga media**      | 20s     | 100     | 1     | 5                               |
| **Operación normal** | 50s     | 450     | 1     | 9                               |
| **Alta carga**       | 75s     | 1500    | N/A   | 20                              |
| **Muy alta carga**   | 100s    | 3000    | N/A   | 30                              |
| **Estrés**           | 150s    | 7500    | N/A   | 50                              |
| **Estrés fuerte**    | 200s    | 18000   | N/A   | 90                              |

## Pruebas de carga

A continuación, descargue Apache Jmeter en su máquina personal y realice las pruebas de carga

Descargue el archivo [`load_test.jmx`](recursos/load_test.jmx) el cual contiene las pruebas GET y POST.

El siguiente [recurso](https://testertina.medium.com/a-beginners-guide-to-performance-testing-with-apache-jmeter-be7a7eb0a6ad) contiene información de que componentes tiene jMeter, apréndalos para modificar los argumentos necesarios en el test que le proveemos
#### Ejecución de pruebas de carga alta

Para escenarios de alta carca > 450 JMeter empieza a tener limitaciones de performance, por lo que como **alternativa lo invitamos a que use copilot o el agente de IA de su preferencia para generar un script para la ejecución de pruebas**, este script debe tener las siguientes características:
- Las peticiones deben ser http a los endpoints a los cuales se busca hacer la prueba
- El script debe permitir configurar Ramp-Up y Threads para cada prueba
- Para POST, usar un body JSON realista de “pedido grande” con 10 ítems (productoId y cantidad)
- Debe registrar por request: timestamp, método, endpoint, status_code, latency_ms, error (si aplica).
- Debe calcular al final:  
	- total requests por tipo (GET/POST)  
	- throughput (req/s)  
	- latencia promedio, p95 y p99 por tipo  
	- Error % por tipo (status >= 400 + timeouts + connection errors)
- Idealmente debería generar la tabla y gráficos para **SU** análisis

Les dejamos un prompt de ejemplo, note que debe cambiar algunos valores para ajustarlo al laboratorio
```
Actúa como un ingeniero de performance. Necesito un script en Python para ejecutar pruebas de carga ligeras contra un backend NestJS usando HTTP.

Contexto:
- Base URL: http://localhost:3000
- Endpoint GET (lectura pesada): <RUTA_GET>
- Endpoint POST (escritura): <RUTA_POST>

Requerimientos del script:
* Debe permitir configurar por argumentos CLI o variables:
   - --endpoint (endpoint a testear)
   - --users (concurrencia máxima)
   - --ramp-up (segundos)
   - --duration (segundos)

* Para POST, usar un body JSON realista de “pedido grande” con 10 ítems (productoId y cantidad).

* Debe registrar por request: timestamp, método, endpoint, status_code, latency_ms, error (si aplica).
* Debe calcular al final:
   - total requests por tipo (GET/POST)
   - throughput (req/s)
   - latencia promedio, p95 y p99 por tipo
   - Error % por tipo (status >= 400 + timeouts + connection errors)
* Debe exportar resultados a CSV: results_get.csv y results_post.csv con columnas:
   timestamp_iso,status_code,latency_ms,error
* Debe imprimir un resumen final claro en consola.

Restricciones:
- Usa solo librerías estándar o, si necesitas, sugiere instalar exactamente UNA librería: httpx o aiohttp. Prefiero async/await.
- Maneja timeouts y errores de conexión, debes registrarlos.
- Incluye instrucciones de ejecución y ejemplo:
  python load_test.py --users 100 --ramp-up 50 --duration 60
```

Como estudiante usted tiene acceso a Github copilot para generación de código, este [tutorial](../tutoriales/como_usar_github_copilot) le explicará como usarlo
## Entregables

> [!WARNING]
> - Todos los entregables deben estar bien organizados y 
> documentados en un archivo de Word o PDF.
> - Las capturas de pantalla mostrando la ejecución del laboratorio son tan importantes como los resultados
> - Incluir los prompts utilizados para la generación de pruebas

1. Complete la siguiente tabla con los resultados que obtuvo en las pruebas del laboratorio. En el documento deben ir las capturas de pantalla como evidencia de las pruebas realizadas. Estas capturas incluyen el "Summary report", las configuraciones de Jmeter.

| Threads | Ramp-up | p99 (ms) | p95 (ms) | Throughput | Error % |
| ------- | ------- | -------- | -------- | ---------- | ------- |
| &nbsp;  | &nbsp;  | &nbsp;   | &nbsp;   | &nbsp;     | &nbsp;  |
| &nbsp;  | &nbsp;  | &nbsp;   | &nbsp;   | &nbsp;     | &nbsp;  |
| &nbsp;  | &nbsp;  | &nbsp;   | &nbsp;   | &nbsp;     | &nbsp;  |


Responder con evidencia:
1. Describa la distribución de los datos y la razón de los mismos para cada prueba basado en el contexto de Chiper
2. ¿Cuál fue el punto de inflexión y cuál ASR se rompió primero?
3. Teniendo en cuenta los resultados registrados, ¿el diseño monolítico de arquitectura propuesto en este experimento beneficia el cumplimiento de los ASRs involucrados?
4. En caso afirmativo, explique cómo se beneficiaron los ASRs. De lo contrario, explique qué modificaciones podría hacer a la arquitectura (estilos o tácticas) para cumplir con los ASRs.
5. ¿El patrón de degradación fue gradual o abrupto? ¿En donde se encuentra el cuello de botella de la aplicación?
6. ¿Qué endpoint degradó primero y por qué ocurrió?
