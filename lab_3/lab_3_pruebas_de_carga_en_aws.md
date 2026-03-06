# Lab 3 — Pruebas de Carga en AWS para el Monolito de Chiper


> Este laboratorio continúa el trabajo del **Lab 2**. El objetivo es ejecutar **pruebas de carga con JMeter** sobre los **endpoints (GET y POST)** definidos en el Lab 2, pero ahora desplegados en **AWS (EC2)**.

## Objetivos

- Ejecutar **pruebas de carga** sobre el backend monolítico de Chiper desplegado en AWS (EC2).
- Encontrar el **punto de inflexión** del sistema (máximo de usuarios/hilos antes de incumplir ASRs).
- Analizar el comportamiento del monolito bajo carga: **latencia, throughput, errores** y posibles cuellos de botella.
- Proponer **mejoras de arquitectura y/o tácticas** para mejorar desempeño y disponibilidad.


## Índice

- [1. Experimento](#1-experimento)
- [2. Arquitectura](#2-arquitectura)
- [3. Tecnologías](#3-tecnologías)
- [4. Despliegue (AWS)](#4-despliegue-aws)
- [5. Pruebas de carga](#5-pruebas-de-carga-con-jmeter)
- [6. Interpretación de resultados](#6-interpretación-de-resultados)
- [7. Entregables](#7-entregables)

## 1. Experimento

### 1.1 Descripción

| Elemento | Detalle |
|---|---|
| Título | Prueba de carga al monolito de Chiper en AWS |
| Propósito | Determinar el **punto de inflexión** de un endpoint **GET** (consulta compleja) y un endpoint **POST** (escritura pesada) definidos en el Lab 2 |
| Resultados esperados | Identificar el número máximo de usuarios concurrentes en el que los **ASRs** se dejan de respetar |
| Infraestructura | 2 instancias **EC2** (App y DB) + computador personal para ejecutar JMeter |

### 1.2 ASRs involucrados (del Lab 2)

- **REQ1 — Latencia:** Como tendero, quiero confirmar un pedido en menos de **2000 ms**.
  - Umbral: **Average Response Time < 2000 ms**

- **REQ2 — Disponibilidad bajo carga:** Como Chiper, quiero que al menos el **90% de las peticiones** sean exitosas bajo alta demanda.
  - Umbral: **Error % ≤ 10%**

> En este laboratorio medimos REQ1 y REQ2 con el **Summary Report** de JMeter.

### 1.3 Qué se va a probar

Se prueban dos escenarios (del Lab 2):

1) **GET (lectura pesada / consulta con JOINs):**
   - Consultar **productos que un usuario alguna vez haya pedido**, que estén **en promoción** y **disponibles** en el catálogo.
   - Debe involucrar múltiples JOINs (Usuario → Pedidos → Items → Producto → Promoción → Catálogo/Inventario).

2) **POST (escritura pesada / entidad grande):**
   - Confirmar/crear un pedido con una carga grande (por ejemplo, **muchos items**, direcciones/detalles, totales, auditoría, etc.).
   - Debe crear varias filas relacionadas (Pedido + Items + posible historial).

## 2. Arquitectura

### 2.1 Estilos de arquitectura asociados (y efectos)

- **Monolito**
  - Favorece: latencia y mantenibilidad.
  - Desfavorece: escalabilidad y disponibilidad.

- **Cliente / Servidor**
  - Favorece: control centralizado.
  - Desfavorece: escalabilidad y disponibilidad.

- **Capas (Nest: Controller → Service → Repository/ORM)**
  - Favorece: mantenibilidad.
  - Puede desfavorecer: latencia (más saltos y abstracción) y complejidad.

### 2.2 Tácticas

En este experimento **no se aplica** una táctica específica (el objetivo es medir el comportamiento base del monolito).

### 2.3 Elementos de arquitectura

#### 2.3.1 Diagrama de despliegue

TODO
- `[Imagen 1: Vista de despliegue (PC con JMeter -> EC2 chiper-app -> EC2 chiper-db)]`

#### 2.3.2 Diagrama de componentes

TODO
- `[Imagen 2: Componentes (JMeter, API Chiper, módulos del dominio del Lab 2, Persistencia/TypeORM, PostgreSQL)]`

---

## 3. Tecnologías

| Categoría                | Tecnologías   |
| ------------------------ | ------------- |
| Framework backend        | NestJS        |
| Lenguaje                 | TypeScript    |
| Base de datos            | PostgreSQL    |
| ORM                      | TypeORM       |
| Plataforma de despliegue | AWS EC2       |
| Pruebas de carga         | Apache JMeter |

---

## 4. Despliegue (AWS)

> Este laboratorio asume que ya completó el **Pre-Lab del Lab 3** y que sus instancias quedaron creadas.

### 4.1 Iniciar instancias EC2

1. Inicie las instancias:
   - `chiper-db`
   - `chiper-app`
2. Identifique:
   - **IP pública** de `chiper-app` (la usará JMeter)
   - **IP privada** de `chiper-db` (la usa el backend)

TODO
- `[Imagen 3: EC2 list con IP pública/privada visibles]`

### 4.2 Ejecutar la base de datos (chiper-db)

- Confirme que PostgreSQL está arriba:

```bash
docker ps
```

> Si no está activo:

```bash
# Opción A: crear y levantar (primera vez)
docker run --name chiper-db \
-e POSTGRES_PASSWORD=postgres \
-e POSTGRES_DB=chiper \
-p 5432:5432 \
-d postgres

# Opción B: si ya existe, solo iniciar
docker start chiper-db
```

### 4.3 Ejecutar el monolito (chiper-app)

1) Conéctese por SSH.

2) Entre al repo.

3) Verifique variables de entorno/archivo `.env`:

- `DB_HOST` debe apuntar a la **IP privada** de `chiper-db`
- `PORT=3000` (o el puerto que use el backend)

4) Levante la app:

```bash
npm install
npm run start:dev
```

> Si su repo está listo para producción, puede usar `npm run start`.

TODO
- `[Imagen 4: logs del backend levantado en 0.0.0.0:3000]`

### 4.4 Verificación rápida desde el navegador

En su computador:
- `http://<IP_PUBLICA_APP>:3000/health`

TODO
- `[Imagen 5: /health OK]`

---

## 5. Pruebas de carga

> En el **Lab 2** ya aprendió a usar JMeter. En este laboratorio el foco es: **diseñar y ejecutar una matriz de pruebas**, medir **p99/p95**, y detectar el **punto de inflexión**.
>
> Además de JMeter, para cargas altas puede usar un **script en Python** como generador de carga (Puede ser el mismo que el del anterior laboratorio, solo recuerde que ya no está apuntando a `localhost`).

### 5.1 Escenarios de carga (derivados de ASRs)

- **Operación normal:** 500 req/min (≈ 8.3 req/s)
- **Evento de promociones (pico):** 5000 req/min (≈ 83.3 req/s)

### 5.2 Matriz mínima de pruebas

Ejecute al menos **8 ejecuciones** para *Operación normal* y *Estrés fuerte*. Para el resto, ejecute al menos **4** (o más si el quiebre no es claro):

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

> Mantenga constantes los parámetros base para que el comparativo sea válido.

### 5.3 Ejecutar con JMeter

1. Descargue del repositorio el archivo `load-tests.jmx` (incluye las pruebas **GET** y **POST**).
2. Actualice en el plan:
   - `Server Name or IP` = `IP_PUBLICA_APP`
   - `Port` = `3000` (o el que corresponda)
1. Ejecute la primera parte de la matriz de pruebas.

TODO
- `[Imagen X: Configuración de load-tests.jmx apuntando a IP pública de chiper-app]`
- `[Imagen X: Summary Report de una iteración]`

### 5.4 Opción B — Cargas altas con script en Python

A partir de **> 450 threads**, JMeter puede empezar a ser el cuello de botella del cliente. En esos casos use el script en Python del anterior laboratorio

## 6. Interpretación de resultados

Saque conclusiones respecto a los siguientes parámetros registrados:

- **# Samples:** cantidad total de peticiones.
- **Average:** tiempo promedio de respuesta (ms).
- **Min/Max:** tiempos extremos.
- **Std. Dev.:** variabilidad.
- **Error %:** porcentaje de fallos.
- **Throughput:** peticiones por segundo.

### 6.1 Umbrales por ASR

- **REQ1 (Latencia):** `Average < 2000 ms`
- **REQ2 (Disponibilidad):** `Error % ≤ 10%`

### 6.2 Definir “punto de inflexión”

Para cada endpoint:

- Es el **mayor** número de threads donde **todavía** se cumplen ambos:
  - Avg < 2000 ms
  - Error % ≤ 10%

Luego reporte el primer punto (threads) donde dejan de cumplirse.

TODO
- `[Imagen 12: Summary Report GET en la iteración donde falla el ASR]`
- `[Imagen 13: Summary Report POST en la iteración donde falla el ASR]`

## 7. Entregables

### 7.1 Tablas de resultados

Entregue **dos tablas** (una por endpoint):

- Tabla A: Resultados del **GET**
- Tabla B: Resultados del **POST**

Use este formato (con **p95 y p99**):

| # threads/users | Ramp-up (s) | p99 (ms) | p95 (ms) | Throughput (req/s) | Error % |
|---:|---:|---:|---:|---:|---:|
| 5 | 5 |  |  |  |  |
| 10 | 10 |  |  |  |  |
| ... | ... |  |  |  |  |

- Marque el registro del **punto de inflexión**.

### 7.2 Evidencias

Adjunte capturas de pantalla de:

- `Summary Report` por iteración (o al menos de las iteraciones relevantes)
- La iteración donde **deja de cumplir** REQ1 o REQ2

### 7.3 Evidencias y prompts

Adjunte evidencias de:

- Configuración de la prueba (JMeter o script Python).
- Ejecución de pruebas (capturas de Summary Report o logs del script).
- Iteración donde **deja de cumplir** algún ASR.
- **Prompts utilizados** (si usó IA) y el **script final**.

### 7.4 Análisis breve

Incluya un análisis (1–2 páginas) que responda:

1. ¿Cuál fue el punto de inflexión y cuál ASR se rompió primero?
2. Con base en los resultados, ¿el diseño monolítico favorece el cumplimiento de los ASRs? Explique.
3. ¿Qué cambios de arquitectura (estilos o tácticas) propondría para cumplir los ASRs?
4. ¿El patrón de degradación fue gradual o abrupto? ¿Cuál fue el cuello de botella más probable?
5. ¿Qué endpoint degradó primero y por qué ocurrió?

## Nota final (créditos AWS)

Cuando termine:

- **Detenga o elimine** las instancias según la regla del curso.
- Si el curso exige eliminación: elimine `chiper-app` y `chiper-db`.

**Placeholder imagen**
- `[Imagen 14: Instancias detenidas/eliminadas]`

