# Notas de Mejora — Lab 3: Pruebas de Carga en AWS

> Especificación estructurada de las mejoras identificadas sobre `lab_3_pruebas_de_carga_en_aws.md`, a partir de `notas.txt`.

## 1. Diagrama de despliegue

**Sección afectada:** `2.1 Diagrama de despliegue` (línea 73-75)

**Problema identificado:**
- La imagen `diagrama_componentes.png` no tiene descripción ni caption.
- El ícono de la DB es diferente al de las instancias de app, pero ambas son instancias EC2; no se explica esta diferencia visual y puede confundir al estudiante.
- No se especifican las características de la máquina (tipo de instancia, recursos) asociada a cada componente del diagrama.

**Mejora propuesta:**
- Añadir un caption/descripción corto debajo de la imagen explicando qué representa cada elemento.
- Aclarar en una nota que el ícono distinto de la DB es solo convención visual (uso diferenciado), pero que sigue siendo una instancia EC2 igual que las de app.
- Agregar una nota con el tipo de instancia y recursos (vCPU, RAM, almacenamiento) usados por cada máquina del diagrama, para que sea consistente con la sección 4.

---

## 2. Acceso a AWS Academy

**Sección afectada:** `4.1.1 Acceso a AWS Academy` (línea 149-163)

**Problema identificado:**
- Los pasos intermedios para iniciar el laboratorio no están del todo detallados (falta indicar explícitamente el botón "Start Lab" y la espera del punto verde).
- No se advierte sobre el riesgo de presionar "Reset Lab", que puede tomar bastante tiempo en restablecer el ambiente.

**Mejora propuesta:**
- Detallar el paso a paso: presionar **Start Lab**, esperar hasta que el indicador cambie a **punto verde** (ambiente listo).
- Agregar una advertencia (`[!WARNING]`) indicando **no presionar "Reset Lab"** salvo que sea estrictamente necesario, ya que el reseteo del ambiente puede demorar considerablemente.

---

## 3. Orden de Security Groups

**Sección afectada:** `4.2 Configuración de seguridad` (línea 165-212)

**Problema identificado:**
- El Security Group 3 (`chiper-http`, línea 201) queda ubicado **después** del bloque `[!IMPORTANT]` de la Pregunta 4 (línea 190-199), mientras que los SG 1 y 2 están antes. Esto da la impresión de que el SG3 es conceptualmente diferente o menos relevante que los otros dos.

**Mejora propuesta:**
- Reordenar la sección para que los **tres Security Groups (4.2.1, 4.2.2 y 4.2.3)** aparezcan consecutivos, y dejar el bloque `[!IMPORTANT]` (Pregunta 4) después de los tres, ya que la pregunta aplica al conjunto completo de la configuración de seguridad.

---

## 4. Conexión a instancias EC2 vía UI de AWS

**Sección afectada:** `4.3.1 Conexión por SSH` (línea 229-235)

**Problema identificado:**
- Solo se documenta la conexión por terminal externo (SSH con archivo `.pem`), lo cual puede ser una barrera para estudiantes sin experiencia en terminales o en configuración de llaves SSH.

**Mejora propuesta:**
- Evaluar documentar como alternativa la conexión mediante **EC2 Instance Connect** desde la consola web de AWS (sin necesidad de terminal externo ni gestión de archivos `.pem`), dejando SSH externo como opción secundaria.

---

## 5. Imagen base con Docker preinstalado

**Sección afectada:** `4.3 Crear instancia EC2 para Base de Datos` (línea 214-227, AMI)

**Problema identificado:**
- Se usa Ubuntu Server 24.04 LTS como AMI, lo que obliga a instalar Docker manualmente en un paso aparte, consumiendo tiempo en tareas no relacionadas con el objetivo principal del laboratorio.

**Mejora propuesta:**
- Evaluar el uso de la AMI **Amazon Linux con Docker preinstalado**, reduciendo el tiempo de instalación y enfocando el laboratorio en las pruebas de carga y no en la configuración del ambiente.

---

## 6. Aclarar cuándo reiniciar servicios

**Sección afectada:** `4.6 Iniciar servicios en las instancias` (línea 386-406)

**Problema identificado:**
- No queda claro en qué momento es necesario ejecutar este paso; el estudiante podría repetirlo innecesariamente o saltárselo cuando sí es requerido.

**Mejora propuesta:**
- Especificar explícitamente que este paso **solo aplica**:
  - Para `chiper-db`: cuando la instancia fue **detenida** (stopped).
  - Para las instancias de app: cuando el **proceso de Node** fue detenido (no necesariamente la instancia completa).

---

## 7. Ubicación y origen de `load-tests.jmx`

**Sección afectada:** `5.3 Ejecutar con JMeter` (línea 441-448)

**Problema identificado:**
- Se indica "Descargue del repositorio el archivo `load-tests.jmx`" sin especificar **de qué repositorio** ni incluir un link. No es claro si corresponde al repo del backend u otro.

**Mejora propuesta:**
- Confirmar que el archivo corresponde al **repositorio del backend** y añadir el link directo (o ruta dentro del repo) donde se encuentra `load-tests.jmx`.

---

## 8. Mínimo de pruebas esperado

**Sección afectada:** `7. Entregables` (línea 479-522)

**Problema identificado:**
- No se especifica con claridad, a nivel de entregables, el número mínimo de pruebas/ejecuciones esperadas ni qué se evalúa de cada una (más allá de la matriz de la sección 5.2).

**Mejora propuesta:**
- Reforzar en la sección de entregables (7.1) el mínimo de ejecuciones exigido por escenario (consistente con la matriz de 5.2: 8 para *Operación normal* y *Estrés fuerte*, 4 para el resto) y qué se espera reportar de cada una (tablas completas, punto de inflexión marcado, etc.).

---

## 9. Apagado/eliminación de recursos AWS

**Sección afectada:** `Nota final (créditos AWS)` (línea 524-527)

**Problema identificado:**
- Al ser el primer laboratorio con AWS, la instrucción final ("Detenga o elimine las instancias e infraestructura creada") es muy breve y no indica **cómo** hacerlo ni dónde encontrar el procedimiento.

**Mejora propuesta:**
- Especificar el procedimiento para apagar/eliminar cada recurso creado (instancias EC2, ALB, Security Groups), o referenciar directamente la sección del tutorial de creación de instancias donde se documenta este paso.
