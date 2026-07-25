# Notas de Mejora — Lab 4: Pruebas de Carga en AWS (Microservicios)

> Especificación estructurada de las mejoras identificadas sobre `lab_4_pruebas_de_carga_en_aws_microservicios.md`, a partir de `notas.txt`.

## 1. ASRs mal definidos

**Sección afectada:** `1.2 ASRs involucrados` (línea 42-48)

**Problema identificado:**
- Los ASRs (REQ1, REQ2, REQ3) están redactados como historias de usuario ("Como tendero, quiero...") en lugar de seguir la estructura de escenario de calidad (ASR) enseñada en el curso.
- No se identifican explícitamente los campos propios de un ASR: estímulo, fuente del estímulo, entorno/contexto, artefacto, respuesta y medida de la respuesta.
- Al no seguir la estructura pedida, los estudiantes pueden replicar el formato incorrecto sin darse cuenta de que no cumple lo exigido en el curso.

**Mejora propuesta:**
- Reescribir REQ1, REQ2 y REQ3 (o añadir una tabla complementaria) usando la estructura de ASR/escenario de calidad definida en el curso (estímulo, fuente, entorno, artefacto, respuesta, medida de respuesta), manteniendo las métricas ya definidas.
- Aclarar que la Pregunta 1 debe resolverse sobre ASRs correctamente estructurados, para evitar que un ASR mal definido invalide el análisis pedido.

---

## 2. Replicación horizontal y escalamiento independiente no se evidencian en el diagrama

**Sección afectada:** `2.1 Diagrama de despliegue` (línea 70-72), relacionado con `2.3 Tácticas` (línea 81-88)

**Problema identificado:**
- Las tácticas de "Replicación horizontal de tareas ECS" y "Escalamiento independiente por microservicio" (línea 85-86) se describen en la tabla de tácticas, pero el diagrama de despliegue (`diagrama_componentes.png`) no muestra evidencia visual de esto (por ejemplo, múltiples tareas/instancias por servicio ECS o `desired count` distinto por servicio).
- Esto genera una desconexión entre lo que se pide analizar (tácticas de escalamiento) y lo que el diagrama realmente comunica.

**Mejora propuesta:**
- Actualizar el diagrama para representar explícitamente varias tareas ECS por servicio (replicación horizontal) y la posibilidad de que cada microservicio escale con un número de tareas independiente del resto.
- Alternativamente, si el diagrama no se actualiza, agregar una nota aclaratoria indicando que la replicación/escalamiento independiente se evidencia en configuración (sección 4.3) y no en el diagrama, para no generar expectativas erróneas sobre lo que el estudiante debe leer del diagrama.

---

## 3. Sección de Tecnologías sin apoyo para entender los servicios nuevos

**Sección afectada:** `3. Tecnologías` (línea 94-105)

**Problema identificado:**
- La tabla lista las tecnologías (API Gateway, ECS/Fargate, ECR, RDS, NestJS, TypeORM, JMeter) sin recursos de apoyo ni orientación sobre cómo profundizar en ellas.
- Al ser varios servicios de AWS nuevos respecto a labs anteriores (API Gateway, ECS, ECR), los estudiantes pueden no entender a detalle qué hace cada uno ni cómo se relacionan entre sí antes de llegar a la sección de despliegue.

**Mejora propuesta:**
- Agregar, junto a cada tecnología nueva, un recurso de referencia (documentación oficial o guía interna) o una nota sugiriendo el uso de IA generativa para explorar en detalle qué hace cada servicio y cómo encaja en la arquitectura de microservicios propuesta, antes de iniciar la sección 4 (Despliegue).

---

## 4. Inconsistencia entre la matriz de pruebas (5.2) y las tablas de entregables (7.1)

**Sección afectada:** `5.2 Matriz mínima de pruebas` (línea 203-218) y `7.1 Tablas de resultados` (línea 276-291)

**Problema identificado:**
- La matriz de la sección 5.2 define columnas (Ramp-Up, Threads totales, Loops, Carga concurrente total) y un mínimo de repeticiones (8 para Operación normal y Estrés fuerte, 4 para el resto), mientras que el formato sugerido en 7.1 usa columnas distintas (# threads/users, Ramp-up, p99, p95, Throughput, Error %) y no menciona repeticiones.
- No queda claro si el mínimo de repeticiones de 5.2 es obligatorio para la calificación, ya que lo único que se define como entregable calificable es la tabla de 7.1. Esto puede llevar a que un estudiante cumpla 7.1 sin ejecutar el mínimo de pruebas de 5.2, o que dude si 5.2 es solo una guía opcional.

**Mejora propuesta:**
- Unificar el formato de tabla entre 5.2 y 7.1 (o dejar explícito cómo se relacionan sus columnas), de modo que la tabla de entregables sea una extensión directa de la matriz de pruebas y no una estructura distinta.
- Declarar explícitamente en 7.1 (o en una nota en 5.2) que el mínimo de repeticiones de la matriz 5.2 **sí es obligatorio** y forma parte de lo que se califica, especificando qué pasa si no se ejecutan todas las repeticiones mínimas (por ejemplo, penalización o tabla incompleta).
