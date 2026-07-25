# Mejoras Laboratorio 1 — NestJS

Sugerencias de mejora organizadas por sección del documento `lab_1_nest.md`.

---

## Capítulo 2 — Componentes principales de Nest

### 2.0 Inconsistencia en los niveles de la arquitectura

El enunciado introductorio del capítulo menciona que Nest distingue **3 capas** (Middleware, Controllers, Providers), y luego propone una arquitectura de **4 niveles**. Sin embargo, la lista de 4 niveles que se presenta no corresponde exactamente a los mismos 4 elementos explicados en las subsecciones 2.1–2.4:

- La lista dice: `Middleware`, `Controller`, `Service`, `Providers de infraestructura`.
- Las subsecciones cubren: `Middleware`, `Controllers`, `Providers` (agrupando Services e Infraestructura), `Modules`.

**Sugerencia:** Alinear la lista numerada con las subsecciones, o aclarar explícitamente la distinción entre los dos esquemas antes de presentarlos.

---

### 2.4 Módulos — Claridad sobre el bloque `[!IMPORTANT]`

La `Pregunta 1` está dentro de un bloque `[!IMPORTANT]` pero no queda claro si:

- El estudiante debe incluir su respuesta en el **reporte entregable**, o
- Es una **reflexión interna** para orientar el pensamiento durante el laboratorio.

**Sugerencia:** Agregar una línea explícita al final del bloque indicando si la respuesta hace parte del entregable. Esto aplica también para las demás preguntas del documento.

---

## Capítulo 3 — Arquitectura del curso

### 3.1 Diagrama sin caption

El diagrama `recursos/nest_arch.png` se inserta sin ningún título ni descripción:

```md
![](recursos/nest_arch.png)
```

Un lector que no entienda la imagen de inmediato no tiene ningún contexto textual para orientarse.

**Sugerencia:** Agregar un caption descriptivo y, si es posible, incluir también el diagrama de componentes (`componentes.png`) directamente en el MD con la misma lógica. Navegar fuera del tutorial para ver imágenes interrumpe el flujo de lectura. Si los diagramas tienen versiones de alta resolución, incluir ambas cosas: la imagen embebida y un enlace al PDF/fuente original.

> **Nota:** El diagrama `componentes.png` en el Paso 5.1 se referencia con una ruta relativa incorrecta (`![](componentes.png)`) — debería ser `![](recursos/componentes.png)`.

---

## Capítulo 4 — Inyección de dependencias

### 4.1 Falta contexto conceptual previo

El capítulo explica correctamente **cómo funciona** la inyección de dependencias en Nest (flujo, decoradores, módulo), pero no introduce **qué es** ni **por qué existe** el patrón antes de entrar al framework.

Un estudiante que nunca ha trabajado con DI puede seguir el ejemplo mecánicamente sin entender el problema que resuelve.

**Sugerencia:** Agregar un párrafo inicial (3-5 líneas) que explique el problema concreto que surge cuando una clase crea sus dependencias con `new` directamente: acoplamiento, dificultad para testear, rigidez para cambiar implementaciones. Luego presentar DI como la solución a ese problema, y recién entonces explicar cómo Nest lo implementa.

---

### 4.3 No se explica qué genera Nest al crear un módulo

En la sección de Providers se menciona que los providers se listan en el módulo, pero en ningún punto anterior se muestra qué archivos y estructura genera Nest cuando se ejecuta:

```bash
nest generate module logistica
nest generate service catalogo
```

El estudiante llega al Paso 5 sin saber qué carpetas y archivos se crean, cuál es la convención de nombres, ni cómo se relacionan entre sí.

**Sugerencia:** Incluir en el Capítulo 4 (o al inicio del Capítulo 5) un bloque que muestre el árbol de archivos generado por el CLI al crear un módulo completo, y explicar brevemente la responsabilidad de cada archivo.

---

## Capítulo 5 — Creación del CRUD

### 5.0 Estructura del repositorio no explicada

Después de la sección de instalación se indica trabajar con el [repositorio de chiper-api](https://github.com/ISIS-2212-Arquitecturas-Robustas/chiper-api), pero:

- No se aclara si el estudiante debe hacer `git clone` del repo o continuar con el proyecto que creó.
- No se describe la estructura de carpetas del repositorio clonado.
- Se empieza a hablar del módulo `datasources` sin explicar que cada carpeta de `src/` corresponde a un subdominio.

**Sugerencia:**

1. Indicar explícitamente si se debe clonar el repositorio o si lo creado hasta ese punto es suficiente.
2. Si se clona, recordar ejecutar `npm install` antes de cualquier otra cosa, ya que `node_modules/` no está en el repo.
3. Mostrar el árbol de carpetas del repositorio clonado con una descripción de cada paquete/subdominio, por ejemplo:

```
src/
 ├── datasources/      # Configuración de conexión a la base de datos
 ├── logistica/        # Subdominio de logística (Catálogo, Producto)
 │   ├── controllers/
 │   ├── services/
 │   ├── repositories/
 │   └── dtos/
 └── identificacion/   # Subdominio de autenticación e identidad (Tienda)
```

4. Para los archivos mencionados por primera vez, incluir la **ruta completa** desde la raíz del proyecto (ej. `src/datasources/database.module.ts`), y si es un repositorio público en GitHub, un enlace directo al archivo.

---

### 5.1 Conceptos no introducidos antes de usarlos

El capítulo usa varios términos sin definición previa:

| Término | Dónde aparece | Problema |
|---|---|---|
| `TypeORM` | Dependencias e instalación | Se instala sin saber qué es ni qué problema resuelve |
| `Entity` | Paso 1 | Se usa el decorador `@Entity` sin explicar qué es una entidad en el contexto de un ORM |
| `ValidationPipe` | Paso 4 | Se aplica en el controlador sin explicar qué hace ni cómo funciona |
| `DTO` | Múltiples pasos | Se menciona pero no se define formalmente |

**Sugerencia:** Agregar una sección breve de "Conceptos clave" al inicio del Capítulo 5, o definir cada término en el momento en que se introduce por primera vez con un bloque destacado (puede ser un `[!NOTE]`).

En particular, para **TypeORM** sería valioso un párrafo que explique:
- Qué es un ORM y por qué usar uno.
- Cómo TypeORM mapea clases TypeScript a tablas en la base de datos.
- Un enlace a la documentación oficial para quien quiera profundizar.

---

### 5.2 Estructura del proyecto no explicada

Al crear el proyecto con `nest new chiper-backend` se genera una estructura de archivos que puede ser desconocida para estudiantes sin experiencia en Node.js:

```
chiper-backend/
 ├── src/
 ├── node_modules/
 ├── package.json
 ├── tsconfig.json
 └── tsconfig.build.json
```

**Sugerencia:** Agregar una descripción breve de los archivos y carpetas más relevantes:

- `node_modules/`: librerías instaladas localmente (no se sube al repositorio).
- `package.json`: manifiesto del proyecto; lista dependencias y scripts (`npm run start:dev`).
- `tsconfig.json`: configuración del compilador de TypeScript.

También sería útil indicar para qué sirve cada dependencia instalada en la sección de instalación, no solo el comando. Por ejemplo: `class-validator` permite anotar propiedades de clases con reglas de validación que `ValidationPipe` evalúa automáticamente.

---

### 5.3 Comando Docker sin explicación de parámetros

El comando Docker se presenta sin explicar sus parámetros:

```bash
docker run --name chiper-db  -e POSTGRES_PASSWORD=postgres  -e POSTGRES_DB=chiper  -p 5432:5432  -d postgres
```

**Sugerencia:** Agregar una tabla o comentarios inline que expliquen cada flag:

| Flag | Valor | Descripción |
|---|---|---|
| `--name` | `chiper-db` | Nombre del contenedor para referenciarlo fácilmente |
| `-e POSTGRES_PASSWORD` | `postgres` | Contraseña del usuario `postgres` |
| `-e POSTGRES_DB` | `chiper` | Nombre de la base de datos que se crea al iniciar |
| `-p 5432:5432` | `host:contenedor` | Expone el puerto 5432 del contenedor al host |
| `-d` | — | Ejecuta el contenedor en segundo plano (*detached*) |

Además, agregar el comando para verificar que el contenedor está corriendo:

```bash
docker ps
```

Esto es especialmente útil para estudiantes que nunca han usado Docker.

---

### 5.4 Título "Arquitectura breve" poco informativo

El subtítulo `**Arquitectura breve:**` antes del listado de capas en el Paso 5.1 no comunica bien su propósito.

**Sugerencia:** Reemplazarlo por algo más descriptivo, como `**Capas del CRUD de Catálogo:**` o `**Resumen de responsabilidades por capa:**`.

---

## Entregables

### Estandarización del repositorio

Actualmente los entregables se solicitan como un **archivo comprimido** o un **documento PDF con código adjunto**. Esto genera fricciones:

- El proceso de descomprimir y revisar código es tedioso para monitores y docentes.
- No hay trazabilidad de cambios.
- No hay una forma estándar de ejecutar el proyecto.

**Sugerencia:** Estandarizar el uso de **un repositorio GitHub por estudiante o grupo**, con el flujo:

1. El estudiante hace un **fork** del repositorio base `chiper-api`.
2. Trabaja sobre su fork.
3. Entrega el enlace al repositorio en el reporte.

Esto simplifica la calificación (clonar y ejecutar), permite ver el historial de commits y es coherente con prácticas profesionales reales. Se recomienda incluir una sección al inicio del laboratorio explicando cómo hacer el fork.

---

### 2.1 Inconsistencia en la ubicación de `Producto`

En el **diagrama de componentes**, el componente `Producto` aparece dentro del subdominio de **Ventas**, pero en el entregable 2.1 se pide implementarlo dentro del módulo de **Logística** (`LogisticaModule`).

**Sugerencia:** Corregir el diagrama para que `Producto` quede dentro del subdominio de Logística, o explicar explícitamente la decisión de arquitectura que justifica este aparente desacuerdo entre diseño e implementación.

---

### Inconsistencia de nombres entre diagramas y código

Se usan nombres distintos para los mismos elementos según el contexto (diagrama vs. código):

**Sugerencia:** Alinear los nombres de entidades, módulos y componentes entre todos los artefactos del laboratorio (diagramas, enunciado y código). Si existe una razón para que difieran (ej. convención de nombres del ORM vs. nombre de negocio), aclararlo explícitamente.

---

### Desconexión entre capas del diagrama y el código

El laboratorio presenta diagramas de dominio y subdominios, y luego el código, pero la conexión entre ambos no es explícita. El estudiante debe inferir cómo cada elemento del diagrama se traduce a un archivo o clase en Nest.

**Sugerencia:** Agregar una tabla o sección breve que mapee los elementos del diagrama a su equivalente en el código, por ejemplo:

| Elemento del diagrama | Archivo en Nest | Capa |
|---|---|---|
| `Catálogo` (entidad de dominio) | `catalogo.entity.ts` | Repository / Entidad |
| `Gestión de catálogos` (capacidad) | `CatalogoService` | Service |
| Subdominio Logística | `LogisticaModule` | Module |

Esto reduce la brecha entre el modelado arquitectónico y la implementación concreta, que es uno de los objetivos centrales del laboratorio.
