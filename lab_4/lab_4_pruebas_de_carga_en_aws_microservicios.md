# Lab 4 — Pruebas de Carga en AWS para la Arquitectura de Microservicios

## Etapas del laboratorio

| Etapa                                  | Resumen                                                                                     | Uso de IA generativa                                                                            |
| -------------------------------------- | ------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| 1. Experimento y ASRs de escalabilidad | Hipótesis de diseño, escenarios de calidad vinculados (ASRs), diseño y planeación del experimento de carga simultánea en microservicios. | Uso acotado para ordenar hipótesis; la priorización de ASRs y el análisis de escalamiento del monolito con sus datos del Lab 3 deben ser propios. |
| 2. Análisis arquitectónico             | Evaluación de estilos (microservicios, API Gateway) y tácticas de escalamiento. | Recomendado para contrastar trade-offs.                      |
| 3. Despliegue en AWS                   | Guía paso a paso para levantar la infraestructura: imágenes de los servicios, base de datos, balanceador de carga, contenedores y API Gateway. | Recomendado para asistencia operativa (comandos/configuración), con verificación manual en AWS. |
| 4. Pruebas de carga simultáneas        | Ejecución de GET y POST en paralelo para observar aislamiento y escalabilidad por servicio. | Recomendado para automatizar experimentos.                   |
| 5. Interpretación y entregables        | Análisis de eficiencia de escalamiento y consolidación de resultados.                       | No recomendado para generar conclusiones sin evidencia cuantitativa.                            |

## Objetivos

- Desplegar la aplicación de Cheapest en una arquitectura de microservicios usando AWS.
- Ejecutar pruebas de carga sobre dos endpoints críticos (GET y POST) en simultáneo.
- Evaluar el atributo de calidad principal del laboratorio: escalabilidad.
- Analizar el comportamiento del sistema distribuido bajo carga: latencia, throughput, errores y capacidad de escalar por servicio.
- Proponer mejoras de arquitectura y configuración de infraestructura para mejorar escalabilidad y disponibilidad.

## Índice

- [1. Plan del laboratorio](#1-plan-del-laboratorio)
- [2. Ejecución: despliegue de la infraestructura](#2-ejecución-despliegue-de-la-infraestructura)
- [3. Entregables](#3-entregables)

## 1. Plan del laboratorio

### 1.1 Descripción

| Elemento | Detalle |
|---|---|
| Título | Prueba de carga a arquitectura de microservicios de Cheapest en AWS |
| Propósito | Evaluar la escalabilidad del sistema al ejecutar cargas simultáneas en endpoints GET y POST |
| Resultados esperados | Evidenciar cómo la separación en microservicios permite escalar de forma independiente y sostener mayor carga |
| Infraestructura | En AWS: los tres microservicios ejecutándose en contenedores, una base de datos administrada compartida, un balanceador de carga y un API Gateway. Fuera de AWS: su computador personal para ejecutar JMeter. Cada pieza de AWS se presenta en la etapa de ejecución, en el momento en que la va a crear. |

### 1.2 Hipótesis de diseño

| # | Hipótesis |
| --- | --- |
| H1 | **Si** separamos la aplicación en microservicios (Logística, Inventario, Ventas) desplegados de forma independiente, cada uno en sus propios contenedores, **entonces** el sistema sostiene 5000 req/min de carga simultánea GET + POST (throughput ≥ 83.3 req/s, error % ≤ 10%), **porque** cada servicio se escala según su propia demanda y una carga pesada en uno no consume la capacidad de los demás. |
| H2 | **Si** aplicamos replicación horizontal (más copias del contenedor de un microservicio) y escalamiento independiente por microservicio, **entonces** el p99 de `POST /logistics/pedidos` se mantiene < 2000 ms bajo carga simultánea, **porque** las copias adicionales reparten las peticiones y reducen la utilización de cada una. |
| H3 | **Si** usamos una única base de datos administrada, compartida por los tres servicios, **entonces** el punto de inflexión del sistema lo determinará el acoplamiento con esa base de datos más que la capacidad de cómputo de los contenedores, **porque** agregar copias de un servicio aumenta el número de conexiones y consultas concurrentes contra un único recurso que no escala horizontalmente. |

### 1.3 Escenarios de calidad vinculados


#### REQ1 — Latencia

**Historia de usuario**

- **Yo como** tendero,
- **quiero** confirmar mis pedidos mientras el sistema recibe la carga de otros tenderos,
- **para** recibir la confirmación en un tiempo que no interrumpa la atención a mis clientes.

**Escenario**

| Elemento | Descripción |
| --- | --- |
| Estímulo | Solicitudes de confirmación de pedido (`POST /logistics/pedidos`) ejecutadas en concurrencia con consultas de productos (`GET`), mientras la carga total sube de 8 TPS a 83 TPS. |
| Artefacto | Microservicio de Logística, que expone `/logistics/pedidos` (y la base de datos compartida que usa). |
| Ambiente | Operación normal (8 TPS, 500 req/min) y pico de carga (83 TPS, 5000 req/min) de carga total, GET + POST en simultáneo, sobre la arquitectura desplegada en AWS. |
| Medida de la respuesta | p99 de la confirmación de pedido < 2000 ms. |

#### REQ2 — Disponibilidad

**Historia de usuario**

- **Yo como** tendero,
- **quiero** consultar los productos disponibles para mi tienda durante un evento de alta demanda,
- **para** ofrecerlos a mis clientes sin que la consulta falle.

**Escenario**

| Elemento | Descripción |
| --- | --- |
| Estímulo | Ráfaga de consultas de productos disponibles (`GET /logistics/tenderos/productos-disponibles`) ejecutadas en concurrencia con confirmaciones de pedido (`POST`). |
| Artefacto | Microservicio de Logística, que expone `/logistics/tenderos/productos-disponibles` (y la base de datos compartida que usa). |
| Ambiente | Evento de alta demanda: 83 TPS (5000 req/min) de carga total, GET + POST en simultáneo. |
| Medida de la respuesta | Error % de las consultas <= 10%. |

#### REQ3 — Escalabilidad

**Historia de usuario**

- **Yo como** gerente de operaciones (COO),
- **quiero** que el sistema soporte un crecimiento en el número de confirmaciones de pedido durante un pico comercial,
- **para** atender de forma adecuada las campañas de promociones.

**Escenario**

| Elemento | Descripción |
| --- | --- |
| Estímulo | Crecimiento de la carga de 8 TPS (500 req/min) a 83 TPS (5000 req/min), es decir, un factor de escala de 900% de crecimiento, sobre la confirmación de pedidos (`POST /logistics/pedidos`) en concurrencia con consultas (`GET`). |
| Artefacto | Arquitectura de microservicios completa (API Gateway, balanceador de carga, contenedores de los microservicios y base de datos compartida), con el microservicio de Logística como punto de entrada de la confirmación de pedidos. |
| Ambiente | Pico comercial (por ejemplo, promociones) con GET + POST en simultáneo, partiendo de operación normal (8 TPS). |
| Medida de la respuesta | Al alcanzar la carga máxima de la matriz de pruebas (prueba *Estrés fuerte*, ramp-up de 200 s): throughput total >= 83,3 TPS (req/s) y Error % de las confirmaciones de pedido <= 10%. |

> [!IMPORTANT]
> **Pregunta 1:**
> REQ1, REQ2 y REQ3 pueden degradarse de forma diferente por servicio.
> Antes de desplegar los microservicios, analice qué tan eficiente es escalar el monolito **agregando recursos** (eje X: instancias, vCPU o memoria; no carga). Con sus resultados del **Lab 3** como datos de partida, defina un criterio matemático simple (por ejemplo, ganancia marginal de throughput por recurso agregado, `ΔThroughput / ΔRecursos`), compare sus resultados con el escalamiento ideal (lineal) y explique a partir de qué punto agregar recursos deja de traducirse en throughput proporcional en Cheapest y qué componente de la arquitectura lo explica.
> La respuesta debe apoyarse en los ASRs.

### 1.4 Diseño del experimento

**¿Cómo se va a validar la hipótesis?** Cada escenario de calidad habla de una sola funcionalidad: REQ1 y REQ3 de confirmar pedidos (`POST /logistics/pedidos`) y REQ2 de consultar productos disponibles (`GET /logistics/tenderos/productos-disponibles`). Lo que vamos a probar es cómo se comportan esas funcionalidades **en concurrencia**, es decir, mientras la otra también recibe carga. El playbook de pruebas de carga es el siguiente:

1. **Referencia del monolito.** Con los resultados del Lab 3, analice la eficiencia del escalamiento del monolito al agregar recursos e identifique el punto a partir del cual deja de ser proporcional. Este análisis constituye la referencia de comparación para las etapas siguientes.
2. **Despliegue de los microservicios.** Siga la guía de ejecución de este laboratorio para levantar la infraestructura en AWS: publicar la imagen de cada servicio, crear la base de datos, crear el balanceador de carga, poner a correr los contenedores de cada servicio y exponerlos a través de un API Gateway. Al finalizar, verifique con los endpoints de `health` que los tres servicios responden.
3. **Carga de datos base.** La base de datos se crea vacía. Cargue los datos base antes de ejecutar las pruebas; sin ellos, el GET retorna una lista vacía y el POST falla.
4. **Definición de la distribución de carga.** Establezca qué proporción de las peticiones es GET y qué proporción es POST, y configure en JMeter dos Thread Groups, uno por endpoint, que se ejecuten simultáneamente.
5. **Ejecución escalonada de la carga.** Ejecute la matriz de pruebas de menor a mayor carga, con el mínimo de repeticiones exigido para cada prueba. En cada ejecución registre, por endpoint, el p99, el p95, el throughput y el error %.
6. **Comparación con los umbrales.** Determine en qué escalón deja de cumplirse cada ASR (REQ1, REQ2 y REQ3) e identifique el punto de inflexión de GET, de POST y del sistema completo: la primera prueba en la que el throughput deja de crecer en proporción a la carga, el p99 crece de forma no lineal o el error % supera el umbral.
7. **Identificación del cuello de botella.** Si algún ASR se incumple, analice con las métricas de uso de recursos (CPU, memoria, conexiones) si la causa es la capacidad de cómputo de los contenedores, el acoplamiento entre servicios o la base de datos compartida. Evalúe el efecto de escalar el servicio que se satura primero.
8. **Análisis comparativo.** Contraste los resultados con el comportamiento del monolito del Lab 3 y concluya en qué medida la separación en microservicios y el escalamiento independiente de cada servicio contribuyeron al cumplimiento de los ASR (hipótesis H1 a H3).

**¿Qué componentes se van a diseñar o modificar?**

| Componente | Cambio |
| --- | --- |
| Registro de imágenes | Publicación de la imagen `1.0.0` de cada microservicio |
| Base de datos administrada | Una única base de datos PostgreSQL, compartida por los tres servicios |
| Balanceador de carga | Un balanceador con una entrada por servicio: da una dirección estable y reparte el tráfico entre las copias de cada servicio |
| Contenedores de los microservicios | Un servicio por microservicio, cada uno con su propio número de copias, de modo que cada uno se escala de forma independiente |
| API Gateway | Una única URL pública con rutas hacia cada microservicio |
| JMeter | Dos Thread Groups (GET y POST) ejecutados en simultáneo, con la distribución de carga que usted justifique |

**¿Qué métricas se van a medir?**

| Métrica | Hipótesis / ASR | Umbral |
| --- | --- | --- |
| p99 y p95 por endpoint | H2 / REQ1 | p99 < 2000 ms |
| Error % por endpoint (GET para REQ2, POST para REQ3) | H1 / REQ2, REQ3 | ≤ 10% |
| Throughput total y por endpoint | H1 / REQ3 | ≥ 83.3 req/s a 5000 req/min |
| Punto de inflexión de GET, POST y global; cuello de botella (cómputo de los contenedores vs. base de datos) | H2, H3 | Primera prueba donde el throughput deja de crecer en proporción a la carga, el p99 crece de forma no lineal o el error % supera el 10% |

**Escenarios funcionales.** Se prueban dos escenarios funcionales:

1. GET (lectura pesada / consulta con JOINs)
   - Consultar productos que un usuario haya pedido, que estén en promoción y disponibles.

2. POST (escritura pesada / entidad grande)
   - Confirmar o crear pedidos con carga grande (múltiples ítems y datos asociados).

3. Ejecución simultánea GET + POST
   - Ambas cargas se ejecutan al mismo tiempo para observar aislamiento entre servicios y comportamiento de escalamiento.

### 1.5 Planeación del experimento

**Recursos requeridos**

| Recurso | Detalle |
| --- | --- |
| Infraestructura AWS | Su cuenta de AWS (la misma del Lab 3), donde creará el registro de imágenes, la base de datos administrada, el balanceador de carga, los contenedores y el API Gateway |
| Herramientas locales | Docker, la línea de comandos de AWS (AWS CLI), JMeter (o un script en Python para las cargas altas) y los resultados del Lab 3 como referencia |
| Créditos AWS | La infraestructura consume créditos mientras esté encendida; elimine los recursos al terminar |

**Elementos de arquitectura involucrados**

Microservicios de Logística, Inventario y Ventas, API Gateway, balanceador de carga, base de datos compartida y el generador de carga (JMeter).

*Estilos de arquitectura asociados*

| Estilos de arquitectura asociados | Análisis (atributos de calidad que favorece y desfavorece) |
| --- | --- |
| Microservicios | Favorece escalabilidad independiente por dominio funcional, despliegue desacoplado y resiliencia localizada.<br>Desfavorece complejidad operativa, observabilidad y mayor costo de coordinación. |
| API Gateway | Favorece seguridad y control de tráfico.<br>Puede desfavorecer latencia adicional por salto de red y posible cuello de botella si no se configura bien. |

*Tácticas y patrones*

| Tácticas | Análisis (atributos de calidad que favorece y desfavorece) |
| --- | --- |
| Replicación horizontal | Favorece mayor capacidad de procesamiento y tolerancia a fallos por redundancia.<br>Desfavorece costos y mantenibilidad. |
| Escalamiento independiente por microservicio | Favorece costos, escalabilidad y elasticidad.<br>Desfavorece mantenibilidad. |
| Balanceo de tráfico por servicio | Favorece disponibilidad.<br>Desfavorece latencia y mantenibilidad. |
| Uso de base de datos administrada | Favorece disponibilidad y mantenibilidad.<br>Desfavorece costos y portabilidad. |

**Esfuerzo estimado** (referencia para planear; puede variar según su experiencia con AWS)

| Etapa | Esfuerzo aprox. |
| --- | --- |
| Ejecución: despliegue de la infraestructura en AWS | 1 h |
| Ejecución de la matriz de carga (con repeticiones mínimas) | 1,5 h |
| Interpretación de resultados y entregables | 1,5 h |
| **Total** | **4 h** |

## 2. Ejecución: despliegue de la infraestructura

En esta etapa va a levantar en AWS la infraestructura de los microservicios de Cheapest. **Todavía no piense en las pruebas de carga ni en los entregables**: el único objetivo es que, al terminar, los tres microservicios respondan a través de una URL pública. Lo que debe hacer con esa infraestructura se explica después, en los entregables.

Esta es una guía paso a paso, pero no es para copiar y pegar. Cada paso se apoya en un tutorial que muestra el procedimiento con **un** servicio y con valores de ejemplo; usted debe entender qué hace cada comando para repetirlo con los tres servicios y con los valores de las tablas de este enunciado. A lo largo de la guía encontrará además preguntas que debe responder en su informe.

### 2.1 Lo que va a construir

![Diagrama de despliegue y pruebas de carga](./recursos/diagrama_componentes.png)

Va a crear cinco piezas, en este orden. Cada una se explica de nuevo, con más detalle, en el paso donde se crea:

| Orden | Pieza | Qué es | Para qué se usa en Cheapest | Documentación |
| --- | --- | --- | --- | --- |
| 1 | **Amazon ECR** (Elastic Container Registry) | Un registro privado de imágenes Docker dentro de su cuenta de AWS (el equivalente a Docker Hub, pero en AWS). | Guarda la imagen de cada microservicio para que AWS pueda descargarla cuando arranque los contenedores. | [Amazon ECR](https://docs.aws.amazon.com/ecr/) |
| 2 | **Amazon RDS** (Relational Database Service) | Una base de datos relacional administrada: AWS opera el servidor, la instalación del motor y los respaldos. En el Lab 3 usted instaló PostgreSQL en una instancia EC2; aquí solo pide la base de datos y AWS la administra. | Es la base de datos PostgreSQL que comparten los tres microservicios. | [Amazon RDS](https://docs.aws.amazon.com/rds/) |
| 3 | **Application Load Balancer (ALB)** | El balanceador de carga que ya usó en el Lab 3: recibe peticiones HTTP y las reparte entre varios destinos sanos. | Da una dirección fija a cada microservicio y reparte las peticiones entre sus contenedores. | [Elastic Load Balancing](https://docs.aws.amazon.com/elasticloadbalancing/) |
| 4 | **Amazon ECS** (Elastic Container Service) con **Fargate** | ECS es el servicio de AWS que ejecuta contenedores Docker y los mantiene encendidos. Fargate es la modalidad de ECS en la que AWS pone las máquinas: usted no crea ni administra instancias EC2, como sí lo hizo en el Lab 3. | Ejecuta los contenedores de Logística, Inventario y Ventas a partir de las imágenes guardadas en ECR. | [Amazon ECS](https://docs.aws.amazon.com/ecs/) |
| 5 | **Amazon API Gateway** | Un servicio administrado que publica una única URL pública y envía cada petición, según su ruta, al backend que corresponde. Es la implementación en AWS del patrón API Gateway. | Es la URL a la que apuntará JMeter: recibe todas las peticiones y las envía al microservicio correcto a través del ALB. | [Amazon API Gateway](https://docs.aws.amazon.com/apigateway/) |

Al terminar, una petición recorrerá este camino: su computador → API Gateway (URL pública) → ALB (un puerto por microservicio) → contenedor del microservicio en ECS → base de datos en RDS.

> [!NOTE]
> El diagrama representa la topología general del despliegue, pero **no** muestra varias copias de un mismo microservicio ni que cada microservicio pueda tener un número distinto de copias. La replicación horizontal y el escalamiento independiente por microservicio no se ven en el diagrama: se evidencian en la configuración de cada servicio de ECS. No asuma que el diagrama por sí solo demuestra esas tácticas.

La aplicación sigue usando las mismas tecnologías de los laboratorios anteriores:

| Categoría | Tecnologías | Recurso de referencia |
| --- | --- | --- |
| Framework backend | NestJS | [Documentación oficial NestJS](https://docs.nestjs.com/) |
| Lenguaje | TypeScript | [Documentación oficial TypeScript](https://www.typescriptlang.org/docs/) |
| ORM | TypeORM | [Documentación oficial TypeORM](https://typeorm.io/) |
| Pruebas de carga | Apache JMeter | [Documentación oficial Apache JMeter](https://jmeter.apache.org/usermanual/index.html) |

> [!NOTE]
> Si alguno de los servicios de AWS de la tabla es nuevo para usted, se recomienda usar IA generativa antes de empezar a desplegar, para explorar en detalle qué hace cada uno y cómo encaja en la arquitectura de microservicios propuesta (por ejemplo: "¿qué rol cumple ECR frente a ECS y en qué momento del despliegue se usa cada uno?").

### 2.2 Antes de empezar

1. **Revise la guía de migración.** La [Guía de migración de monolito a microservicios](./guia_migracion_monolito_microservicios.md) explica cómo cambió el código de Cheapest. Esos cambios no son el foco del laboratorio, pero determinan cómo se despliega y se configura cada servicio (un contenedor y un puerto por servicio, y una variable de entorno para que Inventario y Ventas encuentren a Logística).
2. **Prepare el código.** Los cambios con respecto al monolito están en la rama `microservicios` del repositorio de Cheapest. Cámbiese a esa rama y ejecute `npm install`.
3. **Prepare las herramientas.** Necesita Docker en su computador y la línea de comandos de AWS (AWS CLI). Los comandos `aws` de los tutoriales puede ejecutarlos en su computador, si tiene AWS CLI instalado y configurado, o en CloudShell, que es una terminal dentro de la consola web de AWS que ya viene con AWS CLI configurado para su cuenta.
4. **Lleve una bitácora de valores.** Cada pieza que cree le devuelve un identificador que necesitará más adelante. Anótelos a medida que avanza:

   | Valor | Dónde lo obtiene | Para qué lo necesitará |
   | --- | --- | --- |
   | URI de las tres imágenes | Al publicar las imágenes en ECR | Para indicarle a ECS qué imagen ejecutar |
   | ID de la VPC y de dos subredes en zonas distintas | Al crear la base de datos | Para la base de datos, el ALB y los servicios de ECS |
   | ID del Security Group de los contenedores (`SG_ECS_ID`) | Lo crea usted antes de la base de datos | Para dar acceso a la base de datos y al ALB, y para crear los servicios de ECS |
   | ID del Security Group de la base de datos (`SG_RDS_ID`) | Al crear la base de datos | Para cargar los datos base |
   | Endpoint de la base de datos (`DB_HOST`) y contraseña | Al crear la base de datos | Para cargar los datos base y para las variables de entorno de los servicios |
   | DNS del ALB (`ALB_DNS`) y ARN de cada target group | Al crear el ALB | Para registrar los servicios de ECS y para configurar API Gateway |
   | URL de invocación de API Gateway | Al configurar API Gateway | Para probar los servicios y, después, para JMeter |

### 2.3 Paso 1 — Publicar las imágenes en ECR

**Qué es y por qué se necesita.** En el Lab 3 el código se instalaba directamente en cada instancia. Ahora cada microservicio se empaqueta como una imagen Docker, y AWS necesita un lugar de donde descargarla cada vez que arranca un contenedor. Ese lugar es **Amazon ECR**, un registro privado de imágenes dentro de su cuenta. En ECR las imágenes se organizan en **repositorios**: un repositorio guarda las versiones (tags) de una misma imagen.

Debe crear un repositorio por servicio:

| Servicio   | Nombre sugerido del repositorio | Nombre de la imagen | Tag imagen |
| ---------- | --------------------------- | ---------- | ---------- |
| Logística  | `cheapest-logistica`          | `logistica-service`          | `1.0.0`    |
| Inventario | `cheapest-inventario`         | `inventario-service`         | `1.0.0`    |
| Ventas     | `cheapest-ventas`             | `ventas-service`             | `1.0.0`    |

Para cada servicio debe construir la imagen, etiquetarla con el URI del repositorio y publicarla en ECR. Haga lo siguiente:

1. Siga el tutorial [Subir imágenes Docker a Amazon ECR](../tutoriales/subir_imagenes%20_a_ecr.md), que explica paso a paso cómo publicar la imagen de un servicio; el tutorial lo hace con `inventario-service` en el repositorio `cheapest-inventario`.
2. Haga el mismo procedimiento para `logistica-service` (repositorio `cheapest-logistica`) y para `ventas-service` (repositorio `cheapest-ventas`), cambiando el nombre del repositorio y de la imagen según la tabla anterior. Tenga en cuenta que cada servicio tiene su propio `Dockerfile` (en `apps/<servicio>/Dockerfile`), por lo que el comando de construcción no es idéntico para los tres.
3. Use el tag `1.0.0` en los tres servicios. El tutorial usa `0.0.1` como ejemplo, así que reemplácelo por `1.0.0`.
4. Verifique que los tres repositorios existen y que cada uno contiene su imagen con el tag `1.0.0`.
5. Anote el URI completo de cada imagen (con el tag `1.0.0`); lo usará cuando cree los contenedores.

Al final tendrá que ver algo así:
![](./recursos/ecr_view.png)
Y dentro de cada repositorio
![](./recursos/ecr_image.png)

### 2.4 Paso 2 — Crear la base de datos en RDS

**Qué es y por qué se necesita.** En el Lab 3 usted creó una instancia EC2 e instaló PostgreSQL en ella. **Amazon RDS** es el servicio de bases de datos relacionales administradas de AWS: usted indica el motor (PostgreSQL), el tamaño y las credenciales, y AWS se encarga del servidor. Los tres microservicios comparten **una única** base de datos PostgreSQL en RDS.

**Primero, el Security Group de los contenedores.** La base de datos solo debe aceptar conexiones de los microservicios, no de todo internet. Como en el Lab 3, eso se controla con Security Groups: el de la base de datos autoriza el puerto 5432 únicamente desde el Security Group de los contenedores de los microservicios. Esos contenedores todavía no existen, pero su Security Group se puede crear desde ya, vacío (sin reglas de entrada). Créelo en la misma VPC en la que va a crear la base de datos y anote su ID: es el valor que los tutoriales llaman `SG_ECS_ID`, y lo volverá a usar al crear el balanceador y los contenedores.

**Luego, la base de datos:**

1. Siga el tutorial [Crear una instancia RDS PostgreSQL para Cheapest](../tutoriales/crear_instancia_rds.md) (versión CloudShell), que crea la instancia en 6 pasos:
   1. Identifica la VPC y las subredes donde se va a crear la base de datos.
   2. Crea el *DB Subnet Group* que usará la instancia (la lista de subredes en las que RDS puede ubicar la base de datos).
   3. Crea el Security Group de RDS y autoriza el puerto 5432 **solo** desde el Security Group de los contenedores (`SG_ECS_ID`), de modo que únicamente los microservicios puedan conectarse.
   4. Crea la instancia RDS PostgreSQL (base `Cheapest`, usuario `postgres`).
   5. Espera a que la instancia esté disponible.
   6. Consulta el endpoint de la instancia.
2. Al terminar, anote el endpoint (`DB_HOST`), el nombre de la base (`--db-name`, `Cheapest` en el tutorial), la contraseña del usuario `postgres` y el ID del Security Group de RDS (`SG_RDS_ID`). Anote también el ID de la VPC y de las dos subredes: los volverá a usar para el balanceador y para los contenedores.
3. Cree el esquema y cargue los datos base, como se explica a continuación. Este paso no está en el tutorial, porque usa el script de seed que viene en el código de la rama `microservicios`.

Más adelante, cuando cree los contenedores, les pasará el endpoint, el usuario, la contraseña y el nombre de la base como variables de entorno para que se conecten a esta RDS.

#### Crear el esquema y cargar los datos base

La RDS se crea **vacía**: sin tablas y sin datos. A diferencia del Lab 3, en la rama `microservicios` los servicios **no** ejecutan un seeder al arrancar. Sin este paso, las pruebas de carga no tienen datos: el GET responde una lista vacía y el POST falla porque la tienda, los productos y la moneda del pedido no existen.

- **Esquema (tablas):** lo crea TypeORM (`synchronize`) cuando `DB_SYNCHRONIZE=true`. El script de seed también sincroniza el esquema completo (las entidades de los tres servicios) antes de insertar los datos.
- **Datos:** el script `npm run db:seed` de la rama `microservicios` carga `libs/shared/database/src/seed.sql`, que contiene los mismos UUID fijos que usa el plan de JMeter del Lab 2 (tiendas `bbbbbbbb-...`, productos `aaaaaaaa-...`, moneda `cccccccc-...`, zonas `Zona Norte`/`Zona Sur`). Si detecta que la base ya tiene datos, no inserta nada.

Ejecútelo **una sola vez**, desde su computador, con el repositorio en la rama `microservicios` (después de `npm install`) y **antes** de continuar con el paso siguiente.

> [!IMPORTANT]
> La RDS se creó con `--no-publicly-accessible`, por lo que **no es alcanzable desde su computador** sin importar las reglas del Security Group. Correr `npm run db:seed` directamente fallará por timeout, o peor: si no define `DB_HOST`, el script sembrará silenciosamente un Postgres local (hace `process.env.DB_HOST ??= '127.0.0.1'`) y le dará una falsa sensación de éxito.

Para sembrar la RDS desde su computador, hágala temporalmente pública y restrinja el acceso a su propia IP. Los comandos `aws` puede correrlos en CloudShell o en su terminal, pero el primer comando (`curl`) debe correrlo en su computador, para obtener la IP de su computador y no la de CloudShell:

```bash
# 1. Anote su IP pública actual (corra este comando en SU computador o busque "cuál es mi IP" en Google)
curl -s https://checkip.amazonaws.com

# 2. Haga la instancia temporalmente pública
aws rds modify-db-instance --db-instance-identifier Cheapest-rds --publicly-accessible --apply-immediately

# 3. Espere a que el cambio se aplique (puede tardar 1-2 minutos)
aws rds describe-db-instances --db-instance-identifier Cheapest-rds --query "DBInstances[0].PubliclyAccessible"

# 4. Abra el puerto 5432 SOLO para su IP (no 0.0.0.0/0: expondría las credenciales de la base a internet)
aws ec2 authorize-security-group-ingress --group-id <SG_RDS_ID> --protocol tcp --port 5432 --cidr <SU_IP_PUBLICA>/32
```

Luego, desde su computador, corra el seed apuntando explícitamente a la RDS:

```bash
DB_HOST=<ENDPOINT_RDS> DB_PORT=5432 DB_USERNAME=postgres DB_PASSWORD=<PASSWORD> DB_NAME=Cheapest npm run db:seed
```

> En Windows (PowerShell), defina cada variable antes del comando: `$env:DB_HOST="<ENDPOINT_RDS>"`, `$env:DB_USERNAME="postgres"`, etc., y luego ejecute `npm run db:seed`.

Salida esperada: `Database seeded successfully.` (o `Database already seeded. Skipping.` si ya se había cargado).

> [!WARNING]
> Defina siempre `DB_HOST` al correr el seed. Si lo omite, el script usa `127.0.0.1` y, si tiene un Postgres local corriendo, lo sembrará a él y el comando terminará sin errores aunque la RDS siga vacía.

Al terminar, **revierta los cambios** para no dejar la base expuesta:

```bash
aws rds modify-db-instance --db-instance-identifier Cheapest-rds --no-publicly-accessible --apply-immediately
aws ec2 revoke-security-group-ingress --group-id <SG_RDS_ID> --protocol tcp --port 5432 --cidr <SU_IP_PUBLICA>/32
```

### 2.5 Paso 3 — Crear el balanceador de carga (ALB)

**Qué es y por qué se necesita.** Los contenedores que va a crear en el paso siguiente reciben una IP nueva cada vez que se reinician, y el API Gateway solo puede apuntar a una dirección por servicio. Para que cada microservicio tenga una dirección estable, y para que al agregar copias de un servicio las copias nuevas también reciban tráfico, delante de los contenedores va un **Application Load Balancer (ALB)**, el mismo tipo de balanceador del Lab 3: reparte las peticiones entre los contenedores de cada servicio y tiene un DNS que no cambia.

Un ALB se configura con dos elementos:

- **Target group:** el conjunto de destinos a los que el ALB reenvía peticiones (aquí, los contenedores de un microservicio). Incluye un *health check*: el ALB consulta periódicamente una ruta de cada destino y solo envía tráfico a los que responden bien.
- **Listener:** el puerto en el que el ALB escucha, junto con la regla que dice a qué target group reenvía lo que llega por ese puerto.

Se crea el balanceador **antes** que los contenedores porque, al crear cada servicio de contenedores, hay que indicarle en qué target group debe registrarse.

Siga el tutorial [Configurar un Application Load Balancer para servicios de ECS](../tutoriales/configurar_alb_para_ecs.md), que explica paso a paso cómo crear el ALB:

1. Crear el Security Group del ALB y permitir los puertos 3001 a 3003 (paso 1 del tutorial).
2. Permitir que el ALB llegue a los contenedores, agregando al Security Group de los contenedores (`SG_ECS_ID`, el que creó antes de la base de datos) una regla de entrada desde el Security Group del ALB (paso 2 del tutorial).
3. Crear el ALB (paso 3 del tutorial).
4. Crear un target group por servicio, con health check en `/health` (paso 4 del tutorial).
5. Crear un listener por servicio, que reenvía al target group correspondiente (paso 5 del tutorial).

Deténgase ahí: los pasos 6 y 7 del tutorial (registrar los servicios en el ALB y verificar) se hacen cuando cree los contenedores, en el paso siguiente de esta guía.

El ALB es **uno solo** y tiene tres listeners, uno por servicio. Use estos valores:

| Servicio | Target group | Puerto del listener | Puerto del contenedor |
| --- | --- | --- | --- |
| Logística | `tg-Cheapest-logistica` | 3001 | 3001 |
| Inventario | `tg-Cheapest-inventario` | 3002 | 3002 |
| Ventas | `tg-Cheapest-ventas` | 3003 | 3003 |

Al terminar, anote el **DNS del ALB** (`<ALB_DNS>`) y el **ARN de cada target group**. El DNS es la dirección estable de los microservicios: `http://<ALB_DNS>:3001` para Logística, `http://<ALB_DNS>:3002` para Inventario y `http://<ALB_DNS>:3003` para Ventas. Todavía no responde nadie en esas direcciones, porque los target groups están vacíos.

### 2.6 Paso 4 — Crear los servicios en ECS

**Qué es y por qué se necesita.** **Amazon ECS** es el servicio de AWS que ejecuta contenedores Docker y los mantiene encendidos. Lo usará con **Fargate**, la modalidad en la que AWS pone las máquinas donde corren los contenedores: a diferencia del Lab 3, no hay instancias EC2 que crear, configurar ni actualizar. ECS tiene su propio vocabulario:

| Término | Qué es |
| --- | --- |
| **Clúster** | Una agrupación lógica donde viven los servicios y sus tareas. Con Fargate no contiene máquinas suyas; es solo el "contenedor" organizativo. |
| **Task definition** | La receta para ejecutar un contenedor: qué imagen usar, cuánta CPU y memoria darle, qué puerto expone y qué variables de entorno recibe. |
| **Tarea** (*task*) | Una copia en ejecución de una task definition; en este laboratorio, un contenedor de un microservicio corriendo. |
| **Servicio** | El encargado de mantener encendido un número fijo de tareas de una misma task definition. Si una tarea se cae, el servicio lanza otra. |
| **Desired count** | El número de tareas que el servicio debe mantener encendidas. |

Va a desplegar los tres microservicios como tres servicios de ECS (Fargate) en un mismo clúster. Siga el tutorial [Crear un servicio en Amazon ECS](../tutoriales/crear_instancia_ecs.md), que explica paso a paso cómo desplegar **un** servicio (`inventario`) así:

1. Configurar el Security Group para los puertos de la aplicación (paso 0 del tutorial).
2. Crear el clúster de ECS (paso 1 del tutorial).
3. Escribir el archivo `task-definition.json` (paso 2 del tutorial) y registrarlo (paso 3 del tutorial).
4. Crear el servicio a partir de la task definition (paso 4 del tutorial).
5. Verificar que la tarea esté `RUNNING` (pasos 5 a 8 del tutorial).

El tutorial usa valores de ejemplo (`inventario-task`, puerto `3000`, imagen `inventario_service:v1`, etc.). Usted debe seguir los mismos pasos, pero **reemplazando esos valores por los de las tablas que aparecen a continuación**, una vez por cada servicio (Logística, Inventario y Ventas):

- **Paso 0 del tutorial (Security Group):** use un único Security Group para las tareas de los tres servicios: el que creó vacío antes de la base de datos (`SG_ECS_ID`), que ya tiene acceso a la RDS. Debe tener reglas de entrada para los puertos 3001, 3002 y 3003 **desde el Security Group del ALB**; ya las agregó cuando creó el balanceador, así que solo verifique que existen. Sin esas reglas, el ALB marca las tareas como `unhealthy` y no les envía tráfico.
- **Paso 1 del tutorial (clúster):** créelo una sola vez (`Cheapest-cluster`); los tres servicios corren en el mismo clúster.
- **Pasos 2 y 3 del tutorial (task definition):** en el `task-definition.json` de cada servicio, ponga en `family` el nombre de la columna *Task Definition* de la tabla de recursos (por ejemplo `td-Cheapest-logistica`), en `image` la URI de la imagen que publicó en ECR (con el tag `1.0.0`), en `containerPort` el puerto del servicio y en `environment` las variables de la columna *Variables a declarar*, con los valores de la tabla de variables.
- **Paso 4 del tutorial (servicio):** use como `--service-name` el nombre de la columna *Servicio ECS* (por ejemplo `svc-Cheapest-logistica`), como `--task-definition` la task definition del servicio y como `--desired-count` el valor de *Desired count inicial*. Además, registre el servicio en su target group agregando al comando `--load-balancers targetGroupArn=<TG_ARN>,containerName=<NOMBRE_CONTENEDOR>,containerPort=<PUERTO>`: `<TG_ARN>` es el ARN del target group de ese servicio (el que anotó al crear el ALB) y `containerName` es el `name` del contenedor en su task definition.
- **Pasos 5 a 8 del tutorial (verificación):** compruebe que la tarea de cada servicio queda en `RUNNING` y que en su target group aparece `healthy` (`aws elbv2 describe-target-health --target-group-arn <TG_ARN>`, puede tardar uno o dos minutos).

Recursos de ECS (Fargate) y parámetros necesarios para el proyecto del curso:

| Servicio   | Task Definition        | Servicio ECS            | Puerto contenedor | Desired count inicial | Variables a declarar                                                                         |
| ---------- | ---------------------- | ----------------------- | ----------------- | --------------------- | -------------------------------------------------------------------------------------------- |
| Logística  | `td-Cheapest-logistica`  | `svc-Cheapest-logistica`  | 3001              | 1                     | `PORT=3001`, `DB_HOST`, `DB_PORT`, `DB_USERNAME`, `DB_PASSWORD`, `DB_NAME`, `DB_SYNCHRONIZE=true`                       |
| Inventario | `td-Cheapest-inventario` | `svc-Cheapest-inventario` | 3002              | 1                     | `PORT=3002`, `DB_HOST`, `DB_PORT`, `DB_USERNAME`, `DB_PASSWORD`, `DB_NAME`, `DB_SYNCHRONIZE=true`, `LOGISTICA_BASE_URL` |
| Ventas     | `td-Cheapest-ventas`     | `svc-Cheapest-ventas`     | 3003              | 1                     | `PORT=3003`, `DB_HOST`, `DB_PORT`, `DB_USERNAME`, `DB_PASSWORD`, `DB_NAME`, `DB_SYNCHRONIZE=true`, `LOGISTICA_BASE_URL` |

Valores de las variables:

| Variable | Valor |
| --- | --- |
| `DB_HOST` | Endpoint de la RDS (el que consultó en el último paso del tutorial de RDS), por ejemplo `cheapest-rds.xxxxxxxx.us-east-1.rds.amazonaws.com` |
| `DB_PORT` | `5432` |
| `DB_USERNAME` | `postgres` (el `--master-username` de la RDS) |
| `DB_PASSWORD` | La contraseña que definió en `--master-user-password` |
| `DB_NAME` | El `--db-name` de la RDS (`Cheapest` en el tutorial; respete mayúsculas y minúsculas) |
| `DB_SYNCHRONIZE` | `true`: cada servicio crea o actualiza las tablas de sus entidades al arrancar. El código también usa `true` si la variable no está definida, pero declárela explícitamente para no depender de ese valor por defecto |
| `LOGISTICA_BASE_URL` | `http://<ALB_DNS>:3001` (el DNS del ALB y el puerto del listener de Logística), sin `/` final ni prefijo `/logistics` (el cliente HTTP lo agrega). Es la dirección con la que Inventario y Ventas llaman a Logística para validar productos |

> [!NOTE]
> Use el nombre `DB_USERNAME`, el mismo del `.env.example`, del `docker-compose.yml` y de la [guía de migración](./guia_migracion_monolito_microservicios.md#4-variables-de-entorno). El código también acepta `DB_USER` como alias, pero use un solo nombre en las tres task definitions.

**Orden de creación:** como `LOGISTICA_BASE_URL` usa el DNS del ALB, que ya conoce desde que creó el balanceador, puede crear los tres servicios en cualquier orden.

Verifique que todas las tareas queden en estado `RUNNING` y `healthy` en su target group antes de continuar. Puede probar cada servicio a través del ALB con `curl http://<ALB_DNS>:<PUERTO>/health`.

> [!NOTE]
> **¿Quién decide cuántas tareas corren?** Usted. El `desired count` de cada servicio es el número de tareas que ECS debe mantener encendidas: ECS/Fargate solo se encarga de mantener ese número (por ejemplo, reinicia una tarea que se cae) y no lo cambia por su cuenta, porque en este laboratorio **no se configura ningún auto scaling**. Tampoco lo hace el ALB: su trabajo es solo repartir las peticiones entre las tareas que existan. Todos los servicios empiezan con `desired count = 1` y, si quiere cambiarlo, debe hacerlo usted manualmente, servicio por servicio.

> [!IMPORTANT]
> **Pregunta 3:**
> Suponga que solo puede aumentar `desired count` en un servicio antes de una ventana comercial crítica.
> ¿Cuál escalaría primero en Cheapest y bajo qué evidencia cuantitativa tomaría esa decisión?
> Incluya qué métrica usaría para evitar escalar a ciegas.

### 2.7 Paso 5 — Exponer los servicios con API Gateway

**Qué es y por qué se necesita.** Hasta aquí cada microservicio tiene su propia dirección (`http://<ALB_DNS>:<PUERTO>`). **Amazon API Gateway** es un servicio administrado que publica una única URL pública y envía cada petición, según su ruta, al backend que corresponde. Con él, quien consume Cheapest (y JMeter) usa una sola URL y no necesita saber cuántos microservicios hay ni en qué puerto está cada uno. API Gateway tiene tres conceptos:

- **Integración:** la dirección del backend al que API Gateway reenvía las peticiones (aquí, el ALB en el puerto de un microservicio).
- **Ruta:** la combinación de método y path que API Gateway acepta (por ejemplo `GET /logistics/health`), asociada a una integración.
- **Stage:** un entorno publicado de la API. Su nombre queda como primer segmento de la URL: con un stage llamado `lab`, todas las rutas quedan bajo `/lab/...`.

Va a exponer los tres microservicios a través de una única API HTTP. Siga el tutorial [Configurar API Gateway para microservicios de Cheapest](../tutoriales/configurar_api_gateway.md) (versión CloudShell), que explica paso a paso cómo exponer un servicio así:

1. Crear la API HTTP (paso 1 del tutorial).
2. Crear la integración de negocio y la integración de health hacia el ALB (paso 2 del tutorial).
3. Crear la ruta de negocio (`ANY /<prefijo>/{proxy+}`) y la ruta de health (`GET /<prefijo>/health`) (paso 3 del tutorial).
4. Crear el stage (paso 4 del tutorial).
5. Obtener la URL de invocación (paso 5 del tutorial) y probar los endpoints (paso 6 del tutorial).

El tutorial deja como variables el prefijo, el puerto y la dirección del backend de cada servicio (`<PREFIJO_SERVICIO>`, `<PUERTO>`, `<ALB_DNS>`). Usted debe seguir los mismos pasos, **reemplazando esas variables por los valores de las tablas que aparecen a continuación**:

- **Paso 1 del tutorial:** cree la API **una sola vez**, con el nombre `Cheapest-ms-api` y tipo HTTP API.
- **Pasos 2 y 3 del tutorial:** **repítalos para cada servicio** (Logística, Inventario y Ventas). En `<PREFIJO_SERVICIO>` use el prefijo de la tabla de rutas (`logistics`, `inventory` o `ventas`), en `<PUERTO>` el puerto del servicio (3001, 3002 o 3003) y en `<ALB_DNS>` el DNS del ALB. Al final debe tener seis rutas: una de negocio y una de health por servicio.
- **Paso 4 del tutorial:** cree el stage con el nombre `lab` y con `--auto-deploy`, tal como lo indica el tutorial.
- **Pasos 5 y 6 del tutorial:** guarde la URL de invocación, porque es la que usará en JMeter, y pruebe con `curl` el `health` de cada servicio.

Rutas de negocio (una por servicio):

| Servicio   | Route track (prefijo) |
| ---------- | --------------------- |
| Logística  | `/logistics/*`        |
| Inventario | `/inventory/*`        |
| Ventas     | `/ventas/*`           |

Además del proxy de negocio (`/<prefijo>/{proxy+}`), cree una ruta específica por servicio para el healthcheck, ya que el `HealthController` de cada microservicio expone `/health` en la raíz del contenedor (sin el prefijo del servicio). Por eso la ruta de health necesita su propia integración, que apunta a `/health` y no a `/<prefijo>/health`:

| Servicio   | Ruta en API Gateway | Backend real          |
| ---------- | -------------------- | ---------------------- |
| Logística  | `GET /logistics/health` | `http://<ALB_DNS>:3001/health` |
| Inventario | `GET /inventory/health` | `http://<ALB_DNS>:3002/health` |
| Ventas     | `GET /ventas/health`    | `http://<ALB_DNS>:3003/health`    |

Recursos globales de API Gateway y parámetros necesarios:

| Recurso global | Nombre sugerido | Parámetros necesarios                                                                   |
| -------------- | --------------- | --------------------------------------------------------------------------------------- |
| API            | `Cheapest-ms-api` | Tipo **HTTP API** (`--protocol-type HTTP`), CORS y autorización `NONE` para el laboratorio. |
| Stage          | `lab`           | Creado con `--auto-deploy`.   |
| Deployment     | — (automático)  | Con `--auto-deploy`, cada cambio en rutas e integraciones se publica solo en el stage; no necesita crear deployments manuales. |

> [!NOTE]
> Use **HTTP API**, no REST API. Son dos productos distintos de API Gateway con comandos distintos: todos los comandos de este laboratorio y del tutorial (`aws apigatewayv2 ...`) corresponden a HTTP API. Si crea una REST API (`aws apigateway ...` o la opción "REST API" en la consola), esos comandos no le van a funcionar.

### 2.8 Paso 6 — Verificar el despliegue completo

Desde su computador, pruebe el health de cada servicio a través de API Gateway (no existe un `/health` global único; cada microservicio expone el suyo bajo su propio prefijo de ruta):

- GET: `https://<API_ID>.execute-api.<REGION>.amazonaws.com/<STAGE>/logistics/health`
- GET: `https://<API_ID>.execute-api.<REGION>.amazonaws.com/<STAGE>/inventory/health`
- GET: `https://<API_ID>.execute-api.<REGION>.amazonaws.com/<STAGE>/ventas/health`

`<STAGE>` es el nombre del stage que creó (`lab`). Los tres deben responder correctamente. Compruebe también que la base de datos tiene los datos base, consultando los productos disponibles de una de las tiendas del seed: la respuesta debe ser una lista con productos, no una lista vacía.

- GET: `https://<API_ID>.execute-api.<REGION>.amazonaws.com/<STAGE>/logistics/tenderos/productos-disponibles?tiendaId=<UUID_TIENDA>&zona=Zona Norte`

> [!TIP]
> Si alguna de estas rutas no responde, no diagnostique solo desde API Gateway. Vaya de adentro hacia afuera: (1) que la tarea esté `RUNNING` en ECS; (2) que esté `healthy` en su target group (`aws elbv2 describe-target-health --target-group-arn <TG_ARN>`); (3) que `curl http://<ALB_DNS>:<PUERTO>/health` responda. Si el target está `unhealthy`, revise el Security Group de las tareas: debe permitir el puerto del servicio desde el Security Group del ALB. Si el `curl` al ALB funciona pero la ruta de API Gateway da 404, la integración de health probablemente quedó apuntando a `/<prefijo>/health` en vez de `/health`, o está olvidando el nombre del stage en la URL.

> [!NOTE]
> Tanto las integraciones de API Gateway como `LOGISTICA_BASE_URL` apuntan al **DNS del ALB**, que no cambia cuando las tareas se reinician o cuando se agregan más (el ALB registra las tareas nuevas por su cuenta). Solo tendría que actualizarlos si elimina y vuelve a crear el ALB: en ese caso, actualice las integraciones siguiendo el paso 7 del [tutorial de API Gateway](../tutoriales/configurar_api_gateway.md#7-si-la-dirección-del-backend-cambia-actualizar-la-integración) y registre una nueva revisión de las task definitions de Inventario y Ventas con el `LOGISTICA_BASE_URL` nuevo.
>
> **Síntoma típico de `LOGISTICA_BASE_URL` incorrecta:** `/inventory/health` y `/ventas/health` responden bien, pero las operaciones de inventario o ventas que validan productos tardan unos 3 segundos (`LOGISTICA_TIMEOUT_MS`) y devuelven `503` con el mensaje `Logistica service is unavailable`.

Con esto termina el despliegue. Debe tener:

- Tres repositorios en ECR, cada uno con su imagen `1.0.0`.
- Una instancia de RDS disponible, no pública y con los datos base cargados.
- Un ALB con tres listeners y tres target groups, cada uno con su tarea en `healthy`.
- Un clúster de ECS con tres servicios, cada uno con una tarea en `RUNNING`.
- Una API HTTP en API Gateway con el stage `lab` y seis rutas, cuyos tres `health` responden.

Ahora que conoce todas las piezas y el camino que recorre una petición, responda la siguiente pregunta. Recuerde que REQ3 es el escenario de escalabilidad: al crecer la carga de 500 a 5000 req/min con GET y POST en simultáneo, el sistema debe sostener un throughput total de al menos 83,3 req/s con un error % de las confirmaciones de pedido de máximo 10%.

> [!IMPORTANT]
> **Pregunta 2:**
> Si el sistema no cumple REQ3 durante carga simultánea, ¿cómo determinaría si el problema está en desacoplamiento insuficiente entre microservicios o en capacidad de infraestructura (ECS/RDS/API Gateway)?

## 3. Entregables

Con la infraestructura ya desplegada y verificada, en esta etapa se le pide **usarla**: tomar evidencias de lo que montó, someterla a carga, modificarla para ver cómo responde y analizar los resultados. Cada entregable explica qué debe hacer con la infraestructura y qué debe incluir en el informe.

| Entregable | Qué debe hacer con la infraestructura desplegada |
| --- | --- |
| Evidencias del despliegue | Tomar capturas de cada pieza que creó. |
| Pruebas de carga simultáneas | Apuntar JMeter (o un script) a la URL de API Gateway y ejecutar la matriz de pruebas con GET y POST en simultáneo, observando el uso de recursos en AWS. |
| Tablas de resultados | Registrar las métricas de cada ejecución y marcar dónde se incumple cada ASR y dónde está el punto de inflexión. |
| Efecto de escalar un servicio | Cambiar el número o el tamaño de las tareas del servicio que se satura primero y volver a medir. |
| Evidencias de las pruebas y prompts | Guardar capturas, logs, prompts y scripts. |
| Análisis | Interpretar los resultados y responder las preguntas de análisis. |
| Respuestas a las preguntas del enunciado | Responder las cuatro preguntas marcadas como **Pregunta** a lo largo del enunciado. |

### 3.1 Evidencias del despliegue

Adjunte capturas del despliegue de la arquitectura en AWS:

- Los tres repositorios de ECR, con la imagen `1.0.0` de cada servicio.
- La instancia RDS en estado disponible.
- Los servicios de ECS y la cantidad de tareas por servicio, en estado `RUNNING`.
- El ALB con sus tres target groups y las tareas en `healthy`.
- La configuración de API Gateway: la API, el stage `lab` y las rutas creadas.

### 3.2 Pruebas de carga simultáneas

> Las pruebas base son las mismas de labs anteriores, pero ahora el escenario principal ejecuta GET y POST en simultáneo para evaluar escalabilidad de servicios independientes.

#### Qué endpoints se ejecutan en simultáneo

En cada ejecución corren al mismo tiempo dos cargas, cada una sobre una funcionalidad de los ASRs:

| Carga | Endpoint (vía API Gateway) | ASR asociado |
| --- | --- | --- |
| GET: consultar productos disponibles | `GET /lab/logistics/tenderos/productos-disponibles?tiendaId=<UUID>&zona=Zona Norte` | REQ2 (disponibilidad: error % de las consultas ≤ 10%) |
| POST: confirmar un pedido | `POST /lab/logistics/pedidos` | REQ1 (latencia: p99 < 2000 ms) y REQ3 (escalabilidad: throughput total ≥ 83,3 req/s y error % ≤ 10% en el pico) |

El prefijo `/lab` es el nombre del stage que creó al configurar API Gateway. Ambas cargas se ejecutan a la vez en el mismo plan de JMeter, cada una en su propio Thread Group; así cada endpoint se mide con el otro compitiendo por los mismos recursos (las tareas de ECS y la base de datos en RDS).

**Escenarios de carga** (carga total, sumando GET y POST):

- Operación normal: 500 req/min total.
- Evento de promociones (pico): 5000 req/min total.

#### Distribución GET/POST

La distribución se expresa como "% de GET / % de POST" e indica qué proporción de la carga total le corresponde a cada endpoint. Por ejemplo, **60/40** significa que el 60% de los threads (y de las peticiones) va al GET y el 40% al POST; **50/50** significa mitad y mitad. Como en JMeter cada Thread Group es una carga, la distribución se traduce en repartir los threads totales entre los dos grupos. Con 200 threads totales:

| Distribución | Grupo GET | Grupo POST |
| --- | ---: | ---: |
| 60/40 | 120 threads | 80 threads |
| 50/50 | 100 threads | 100 threads |

Para el smoke test use 50/50. Para el resto de las pruebas usted escoge la distribución, respondiendo la siguiente pregunta, y debe justificarla en el informe.

> [!IMPORTANT]
> **Pregunta 4:**
> La distribución de carga indica cuántas de las peticiones son de consulta (GET) y cuántas de confirmación de pedido (POST). Se escribe "% GET / % POST": por ejemplo, 70/30 significa que de cada 100 peticiones, 70 son GET y 30 son POST; 50/50 significa 50 GET y 50 POST.
> Diseñe una estrategia de distribución de carga GET/POST que represente un lunes de alta demanda en Cheapest (piense cuántos tenderos consultan productos frente a cuántos confirman pedidos).
> ¿Qué distribución escogería para evaluar riesgo real y cuál para estresar el peor caso técnico?
> Justifique por qué no necesariamente deben coincidir.

#### Matriz mínima de pruebas

Estas son las pruebas que debe ejecutar, de menor a mayor carga. La columna **Threads totales** es la suma de los threads de los dos Thread Groups, repartidos según la distribución GET/POST. Use el mismo ramp-up en ambos grupos.

| Test | Ramp-Up | Threads totales | Loops | Carga concurrente total (req/s) | Repeticiones mínimas |
| --- | --- | --- | --- | --- | ---: |
| Smoke test | 5s | 10 | 1 | 1 | 4 |
| Baja carga | 10s | 40 | 1 | 3 | 4 |
| Carga media | 20s | 200 | 1 | 5 | 4 |
| Operación normal | 50s | 900 | 1 | 9 | 8 |
| Alta carga | 75s | 3000 | N/A | 20 | 4 |
| Muy alta carga | 100s | 6000 | N/A | 30 | 4 |
| Estrés | 150s | 12000 | N/A | 50 | 4 |
| Estrés fuerte | 200s | 24000 | N/A | 90 | 8 |

> [!IMPORTANT]
> El mínimo de repeticiones indicado en la columna "Repeticiones mínimas" **es obligatorio y forma parte de la calificación**. Las tablas de resultados que debe entregar son una extensión directa de esta matriz: cada prueba de la matriz debe tener tantas filas de resultados como repeticiones mínimas se definen aquí. Entregar las tablas de resultados sin haber ejecutado el mínimo de repeticiones de cada prueba se considera una matriz de pruebas incompleta.

#### Cómo observar la infraestructura durante las pruebas

JMeter le dice cómo ve el sistema un cliente (latencia, throughput, errores), pero no qué pieza se está quedando sin capacidad. Para eso está **Amazon CloudWatch**, el servicio de monitoreo de AWS: todas las piezas que desplegó le envían métricas automáticamente, sin configurar nada. Puede verlas en la consola de CloudWatch o en la pestaña de monitoreo de cada recurso:

| Pieza | Dónde verlo | Métricas disponibles |
| --- | --- | --- |
| Tareas de ECS (por servicio) | Consola de ECS → clúster → servicio → pestaña de métricas | Uso de CPU (`CPUUtilization`) y de memoria (`MemoryUtilization`) del servicio |
| Base de datos RDS | Consola de RDS → instancia → pestaña de monitoreo | Uso de CPU (`CPUUtilization`) y conexiones abiertas (`DatabaseConnections`) |
| ALB | Consola de EC2 → balanceadores de carga → pestaña de monitoreo | Tiempo de respuesta de los destinos (`TargetResponseTime`) y errores 5xx |
| API Gateway | Consola de API Gateway → API → métricas | Latencia total (`Latency`), latencia del backend (`IntegrationLatency`) y errores 4xx/5xx |

Durante cada prueba, y sobre todo en las de mayor carga, tome nota (o captura) de estas métricas para cada uno de los tres servicios de ECS y para la RDS: son la evidencia que necesitará para decir qué servicio degradó primero y cuál fue el cuello de botella.

#### Prueba base: smoke test

Antes de escalar la carga, ejecute una prueba pequeña para confirmar que todo funciona. Siga estos pasos:

1. Descargue el plan [`load_test.jmx`](../lab_2/recursos/load_test.jmx) del Lab 2 y ábralo en JMeter. Ya trae dos Thread Groups, **Grupo GET Request** y **Grupo POST Request**, cada uno con su petición y sus listeners.
2. En el sampler de **cada** Thread Group, cambie estos valores para apuntar a API Gateway en lugar de `localhost`:

   | Campo | Valor |
   | --- | --- |
   | Protocol | `https` |
   | Server Name or IP | `<API_ID>.execute-api.<REGION>.amazonaws.com` (la URL de invocación de API Gateway, sin `https://` ni el stage) |
   | Port Number | `443` |
   | Path (GET) | `/lab/logistics/tenderos/productos-disponibles?tiendaId=<UUID_TIENDA>&zona=Zona Norte` |
   | Path (POST) | `/lab/logistics/pedidos` |

   Use los UUID de los datos base que cargó en la RDS con el seed (el plan trae los mismos UUID fijos del seed; si los cambió, actualícelos también en el cuerpo del POST).
3. Configure cada Thread Group para el smoke test (10 threads totales, repartidos 50/50):

   | | Grupo GET | Grupo POST |
   | --- | --- | --- |
   | Number of Threads | 5 | 5 |
   | Ramp-up period (s) | 5 | 5 |
   | Loop Count | 1 | 1 |

4. Ejecute el plan completo (botón **Start**): JMeter lanza los dos Thread Groups al mismo tiempo.
5. Revise que la prueba sea válida: en **View Results Tree** las peticiones GET deben responder `200` y las POST `2xx`, y el **Error %** debe ser 0. Si hay errores, no siga escalando: revise primero que los tres `health` respondan a través de la URL de API Gateway y que la RDS tenga los datos base (que el seed haya terminado con `Database seeded successfully.` apuntando a la RDS y no a un Postgres local).
6. Registre, para **cada** Thread Group, el p99, el p95, el throughput y el error % del **Aggregate Report** y del **Summary Report**. Esta es la línea base contra la que comparará el resto de las pruebas.
7. Repita el smoke test 4 veces, que es el mínimo de repeticiones que exige la matriz para esta prueba.

#### Ejecutar el resto de la matriz

Después del smoke test, recorra la matriz de arriba hacia abajo (de menor a mayor carga) con el mismo plan de JMeter. Para **cada fila** haga lo siguiente:

1. **Calcule los threads de cada grupo.** Tome los *Threads totales* de la fila y repártalos según la distribución GET/POST que escogió. Ejemplo con la fila *Baja carga* (40 threads totales) y una distribución 60/40: Grupo GET = 40 × 0,6 = **24** threads y Grupo POST = 40 × 0,4 = **16** threads.
2. **Configure los dos Thread Groups.** En *Number of Threads* ponga los valores calculados; en *Ramp-up period* ponga el ramp-up de la fila (10 s en el ejemplo), el **mismo en ambos grupos**; y en *Loop Count* ponga 1. Así los dos grupos empiezan y terminan juntos y la prueba es comparable entre filas.
3. **Limpie los resultados anteriores.** En cada listener (Aggregate Report, Summary Report) use *Clear All* antes de ejecutar; de lo contrario se mezclan las métricas de esta ejecución con las de la anterior.
4. **Ejecute** el plan con **Start** y espere a que terminen ambos Thread Groups. Mientras corre, observe en CloudWatch el uso de CPU y memoria de las tareas de ECS de cada servicio, y el uso de CPU y las conexiones de la RDS.
5. **Registre los resultados por endpoint.** Del Aggregate Report y del Summary Report anote, para el Grupo GET y para el Grupo POST por separado, el p99, el p95, el throughput y el error %. Guárdelos con *Save Table Data* (CSV) para no perderlos y llene la fila correspondiente de las tablas de resultados.
6. **Repita** la prueba tantas veces como indique la columna *Repeticiones mínimas* (limpiar, ejecutar y registrar en cada repetición), esperando 1 o 2 minutos entre repeticiones para que las tareas y la base de datos se estabilicen, y verificando que las tareas sigan en `RUNNING`.
7. **Decida si continúa.** Si en alguna fila deja de cumplirse un ASR (REQ1: p99 del POST < 2000 ms; REQ2: error % del GET ≤ 10%; REQ3: throughput total ≥ 83,3 req/s y error % del POST ≤ 10% en el pico), marque esa fila como el punto donde se incumple, pero continúe con las filas siguientes para poder ubicar el punto de inflexión.

#### Cargas altas con script en Python

Para las filas de *Alta carga* en adelante (más de 450 threads, columna *Loops* = N/A), JMeter deja de ser confiable como generador de carga en su computador: el limitante pasa a ser su computador y no el sistema que está probando. Ejecute esas filas con un script en Python como generador de carga (puede ser el mismo de los Labs 2 y 3, apuntando ahora a la URL de API Gateway), manteniendo la misma distribución GET/POST y el mismo ramp-up de la fila, y además:

- ejecución simultánea de GET y POST,
- métricas por endpoint (p95, p99, throughput, error %),
- y trazabilidad temporal de resultados.

### 3.3 Tablas de resultados

Para saber si una prueba cumple o no, compare las métricas que registró en JMeter (o en el script) con los umbrales de los ASR:

| ASR | Funcionalidad | Qué medir en cada ejecución | Se cumple si |
| --- | --- | --- | --- |
| REQ1 (latencia) | `POST /logistics/pedidos` | p99 del Grupo POST | p99 < 2000 ms |
| REQ2 (disponibilidad) | `GET /logistics/tenderos/productos-disponibles` | Error % del Grupo GET | Error % <= 10% |
| REQ3 (escalabilidad) | `POST /logistics/pedidos` en el pico de 5000 req/min de carga total | Throughput total de la prueba y Error % del Grupo POST | Throughput total >= 83.3 req/s y Error % <= 10% |

Entregue **dos tablas** (una por endpoint):

- Tabla A: Resultados del **GET** (en escenario simultáneo)
- Tabla B: Resultados del **POST** (en escenario simultáneo)

Formato sugerido (extensión directa de la matriz mínima de pruebas: mismas columnas `Test`, `Ramp-Up` y `Threads totales`, agregando una fila por cada repetición mínima exigida y las métricas medidas):

| Test | Ramp-Up | Threads totales | # Repetición | p99 (ms) | p95 (ms) | Throughput (req/s) | Error % |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Smoke test | 5s | 10 | 1 |  |  |  |  |
| Smoke test | 5s | 10 | 2 |  |  |  |  |
| ... | ... | ... | ... |  |  |  |  |
| Operación normal | 50s | 900 | 1 |  |  |  |  |
| ... | ... | ... | ... |  |  |  |  |

> [!IMPORTANT]
> Cada tabla debe estar **completa** y respetar el mínimo de ejecuciones exigido por escenario en la matriz mínima de pruebas:
> - **8 ejecuciones** como mínimo para *Operación normal* y *Estrés fuerte*.
> - **4 ejecuciones** como mínimo para el resto de escenarios (Smoke test, Baja carga, Carga media, Alta carga, Muy alta carga, Estrés).
>
> De cada ejecución se espera reportar todas las columnas de la tabla y **marcar explícitamente** (resaltando la fila o con una nota al pie) la primera fila donde se incumple cada umbral y el registro correspondiente al **punto de inflexión**.

> [!NOTE]
> Recuerde qué es el punto de inflexión: la primera fila de la matriz (de menor a mayor carga) donde el sistema deja de escalar de forma eficiente. Se da en la primera fila donde **al menos uno** de estos casos deja de cumplirse de forma sostenida:
>
> - El throughput deja de crecer en proporción a la carga ofrecida (los threads de la matriz): la curva se aplana mientras la carga sigue subiendo.
> - El p99 empieza a crecer de forma no lineal respecto al aumento de carga.
> - El Error % supera el umbral del ASR correspondiente (<= 10% para REQ2 y REQ3).
>
> Identifíquelo en tres niveles: en la **Tabla A** (GET), en la **Tabla B** (POST) y para el **sistema completo** (GET + POST en simultáneo). Para decidir en qué fila ocurre, compare filas consecutivas de la matriz.

### 3.4 Efecto de escalar el servicio que se satura primero

Hasta aquí midió la infraestructura tal como la desplegó: una tarea por servicio. Si algún ASR se incumple, identifique con las métricas de CloudWatch cuál de los tres servicios se satura primero, dele más capacidad **solo a ese servicio** y vuelva a ejecutar la prueba de la matriz en la que se incumplió el ASR, para comparar el antes y el después. Esta comparación es la evidencia con la que sustentará, en el análisis, cuánto aporta el escalamiento independiente y qué estrategia de escalamiento recomienda. Repórtela aparte de las Tablas A y B, indicando qué cambió en la infraestructura.

No tiene que volver a desplegar nada: lo que se modifica es la configuración de los servicios de ECS que ya creó. Hay dos formas de darle más capacidad a un servicio, y se pueden combinar:

| Estrategia | Qué se cambia | Dónde se configura |
| --- | --- | --- |
| **Horizontal** | Se agregan más tareas iguales. | El `desired count` del servicio de ECS. |
| **Vertical** | Se hace más grande cada tarea (más CPU y memoria). | Los campos `cpu` y `memory` de la task definition. |
| **Mixta** | Ambas a la vez: más tareas y más grandes. | El `desired count` y los campos `cpu` y `memory`. |

**Escalamiento horizontal.** Cambie el número de tareas del servicio y verifique que todas queden en `RUNNING`:

```bash
aws ecs update-service --cluster Cheapest-cluster --service <SERVICIO_ECS> --desired-count <N>
aws ecs list-tasks --cluster Cheapest-cluster --service-name <SERVICIO_ECS>
```

`<SERVICIO_ECS>` es el **nombre** del servicio de ECS que le dio al crearlo (por ejemplo, `svc-Cheapest-logistica`), y `<N>` es el número de tareas que quiere mantener.

> [!NOTE]
> Cuando ECS lanza las tareas nuevas, las registra automáticamente en el target group del servicio y el ALB reparte las peticiones entre todas las tareas sanas (por defecto, en turnos). No hay que configurar nada más. Recuerde que en este laboratorio no hay auto scaling: el número de tareas solo cambia cuando usted ejecuta este comando.

**Escalamiento vertical.** El tamaño de la tarea está en el `task-definition.json` del servicio (`cpu` en unidades de CPU, donde 1024 es 1 vCPU, y `memory` en MB; el tutorial de ECS usa `512` y `1024`). Cámbielos por valores mayores, registre una nueva revisión de la task definition y actualice el servicio para que use esa revisión:

```bash
aws ecs register-task-definition --cli-input-json file://task-definition.json
aws ecs update-service --cluster Cheapest-cluster --service <SERVICIO_ECS> --task-definition <TASK_DEFINITION>
```

`<TASK_DEFINITION>` es el nombre (`family`) de la task definition del servicio, por ejemplo `td-Cheapest-logistica`.

Fargate solo acepta ciertas combinaciones de CPU y memoria:

| `cpu` | Memoria permitida |
| --- | --- |
| 256 (0,25 vCPU) | 512 MB a 2 GB |
| 512 (0,5 vCPU) | 1 GB a 4 GB |
| 1024 (1 vCPU) | 2 GB a 8 GB |
| 2048 (2 vCPU) | 4 GB a 16 GB |
| 4096 (4 vCPU) | 8 GB a 30 GB |

Al actualizar el servicio, ECS reemplaza la tarea por una nueva (con otra IP) y el ALB la registra automáticamente: no hay que actualizar las integraciones de API Gateway ni `LOGISTICA_BASE_URL`, porque ambas apuntan al DNS del ALB y no a la IP de la tarea.

**Escalamiento mixto.** Combine ambos: primero cambie el tamaño de la tarea en la task definition (vertical) y luego ajuste el `desired count` (horizontal) con los comandos anteriores.

Antes de repetir la prueba, verifique que las tareas del servicio que escaló estén en `RUNNING` y `healthy` en su target group, y espere 1 o 2 minutos para que se estabilicen.

### 3.5 Evidencias de pruebas de carga y prompts

Adjunte evidencias de:

- Configuración de la prueba: los Thread Groups GET y POST en simultáneo (o el script) con la distribución GET/POST que escogió.
- Ejecución de pruebas (capturas de Summary y Aggregate Reports o logs del script). Al menos para la iteración donde **deja de cumplirse** algún ASR y dos iteraciones relevantes más.
- Métricas de CloudWatch de las tareas de ECS y de la RDS durante las pruebas de mayor carga.
- **Prompts utilizados** (si usó IA) y el **script final** (si aplica).

### 3.6 Análisis breve

Incluya un análisis de 1 a 2 páginas que responda los siguientes puntos. Junto a cada uno se indica qué dato debe interpretar para resolverlo:

1. **¿Cuál fue el punto de inflexión de GET y POST cuando se ejecutaron simultáneamente?** Use las Tablas A y B: el punto de inflexión es la primera fila donde el throughput deja de crecer en proporción a la carga, el p99 crece de forma no lineal o el error % supera el 10%.
2. **¿Qué servicio degradó primero y por qué?** Compare, durante las pruebas, el uso de CPU y memoria de las tareas ECS de cada servicio y de la RDS (CloudWatch), y vea cuál se acerca primero al límite.
3. **¿Cómo cambió el comportamiento frente al monolito del Lab 3?** Compare p99, throughput y error % de este lab con los del Lab 3 para niveles de carga equivalentes.
4. **¿Qué tanto aportaría el escalamiento independiente de microservicios al cumplimiento de los ASR?** Con la evidencia de qué servicio degradó primero, de cuál fue el cuello de botella y de la prueba en la que escaló un solo servicio, explique qué ocurre al escalar solo el servicio que saturó primero (y no todos) y qué ventaja tiene frente al monolito del Lab 3, que solo puede escalarse completo.
5. **¿El patrón de degradación fue gradual o abrupto?** Mire cómo cambian el p99 y el error % entre filas consecutivas de la matriz: si crecen de forma progresiva, es gradual; si saltan de golpe entre dos filas, es abrupto.
6. **¿Cuál fue el cuello de botella principal (aplicación, red, API Gateway, RDS u otro)?** Use las métricas de CloudWatch de las tareas ECS (CPU y memoria), de la RDS (CPU y conexiones) y de API Gateway (latencia total frente a latencia del backend).
7. **Dada la evidencia recolectada, ¿qué estrategia de escalamiento en ECS recomiendan (horizontal, vertical o mixta) y por qué?** Apóyese en si el recurso saturado fue CPU o memoria de una tarea (vertical) o la cantidad de peticiones concurrentes (horizontal), y en lo que observó al escalar un solo servicio.
8. **¿Qué cambios de arquitectura proponen para reducir el acoplamiento con RDS y qué trade-offs introducen?** Parta del cuello de botella principal que identificó. Investigue qué tácticas (diferentes de una base de datos por servicio) puede usar y justifique con el contexto de Cheapest.
9. **Si tuvieran que priorizar una inversión de infraestructura para el siguiente evento promocional de 5000 req/min, ¿cuál componente reforzarían primero y cómo justifican la decisión con las medidas de respuesta?** Compare sus resultados de la prueba de pico (*Estrés fuerte*) con los umbrales de los ASR: p99 del POST < 2000 ms, error % ≤ 10% y throughput total ≥ 83,3 req/s.

### 3.7 Respuestas a las preguntas del laboratorio

Incluya en el informe las respuestas argumentadas a las cuatro preguntas marcadas como **Pregunta** a lo largo del enunciado. Cada respuesta debe incluir los elementos que pide la pregunta y debe ir más allá de lo superficial. Para que no tenga que buscarlas, son las siguientes:

- **Pregunta 1 — Eficiencia de escalamiento del monolito.** Con sus resultados del Lab 3, defina un criterio matemático simple para medir qué tan eficiente es escalar el monolito agregando recursos, compárelo con el escalamiento ideal (lineal) y explique desde qué punto agregar recursos deja de traducirse en throughput proporcional y qué componente lo explica, apoyándose en los ASRs.
- **Pregunta 2 — Diagnóstico del incumplimiento de escalabilidad.** Si el sistema no cumple REQ3 durante carga simultánea, cómo determinaría si el problema está en desacoplamiento insuficiente entre microservicios o en capacidad de infraestructura (ECS, RDS o API Gateway).
- **Pregunta 3 — Qué servicio escalar primero.** Si solo pudiera aumentar el `desired count` de un servicio antes de una ventana comercial crítica, cuál escalaría, con qué evidencia cuantitativa y qué métrica usaría para no escalar a ciegas.
- **Pregunta 4 — Distribución de carga GET/POST.** Qué distribución representa un lunes de alta demanda en Cheapest, cuál escogería para evaluar riesgo real y cuál para estresar el peor caso técnico, y por qué no necesariamente coinciden.

> [!IMPORTANT]
> **¿A dónde se suben los entregables?**
> A la Actividad correspondiente en el aula de Bloque Neón de su sección.

## Nota final (créditos AWS)

Cuando termine:

- Detenga o elimine los recursos de ECS, RDS, el ALB y API Gateway, y las imágenes que no use en ECR, para evitar consumo innecesario de créditos.
