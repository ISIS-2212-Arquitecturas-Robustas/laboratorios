# Mejoras propuestas — Lab 2: Pruebas de Carga al Monolito de Chiper

Este documento desarrolla en detalle los puntos de mejora anotados en `notas.txt`, indicando la sección del laboratorio a la que aplica cada uno, el problema concreto que se observó y la mejora sugerida.

---

## 1. Diagrama de despliegue

**Sección afectada:** [`## Diagrama de despliegue`](lab_2_pruebas_carga.md#diagrama-de-despliegue)

**Problema:** La imagen del diagrama se presenta sin ningún texto que oriente al estudiante sobre qué debe observar en ella antes de leer la explicación siguiente.

**Mejora sugerida:** Agregar un *caption* (pie de imagen) corto debajo de la imagen que describa en una línea qué representa el diagrama, por ejemplo:

> *Figura 1. Despliegue de los componentes del backend monolítico de Chiper (API, base de datos) sobre un único nodo de ejecución local.*

Esto ayuda a que el diagrama se pueda referenciar más adelante (p. ej. "como se ve en la Figura 1") y facilita su lectura para quien llega sin contexto previo.

---

## 2. Preparación del entorno

**Sección afectada:** [`## Preparación del entorno`](lab_2_pruebas_carga.md#preparación-del-entorno)

Esta sección tiene varios vacíos que generan fricción real durante la ejecución del laboratorio. Se detallan por separado:

### 2.1 Cambio de rama no explicado
El instructivo dice *"diríjase a la rama `load-tests`"* pero no indica el comando. No todos los estudiantes recuerdan el flujo de git de laboratorios anteriores.

**Mejora:** Incluir el comando explícito:
```bash
git checkout load-tests
```

### 2.2 Falta el link al repositorio del laboratorio anterior
El backend (`chiper-api`) se asume ya clonado de un laboratorio previo, pero el enlace no se repite aquí. Si un estudiante no hizo el laboratorio anterior o perdió el link, queda bloqueado.

**Mejora:** Repetir el link al repositorio `chiper-api` en esta sección, aunque ya se haya compartido antes.

### 2.3 No se explica qué hace `docker compose up`
El comando `docker compose up postgres -d` se presenta sin contexto. Es importante aclarar:
- Que se debe ejecutar **desde el directorio base del repositorio**, porque ahí es donde vive el `docker-compose.yml`. Si se ejecuta desde otro directorio, Docker no encontrará el archivo y fallará.
- Qué hace exactamente el flag `up` (crear y levantar el contenedor definido en el compose) para quienes no manejan Docker con soltura.

### 2.4 Conflicto de puertos con el laboratorio anterior
Si el estudiante no va a reutilizar la misma base de datos del laboratorio anterior, es muy probable que el contenedor viejo siga corriendo y ocupando el puerto `5432`, generando este error al intentar levantar el nuevo entorno:

```
Error response from daemon: failed to set up container networking: driver failed programming external connectivity on endpoint chiper-postgres (5d86a48a3d107d38bfa708e8f6a067bf9cf5210839d04ff07a5e176bd25d855e): Bind for 0.0.0.0:5432 failed: port is already allocated
```

**Mejora:** Antes de levantar el nuevo entorno, recomendar limpiar el contenedor del laboratorio anterior:
```bash
docker stop chiper-postgres
docker rm chiper-postgres
```
o alternativamente detener el `docker-compose` del laboratorio previo desde su propio directorio. Vale la pena documentar este error explícitamente en el laboratorio para que, si aparece, el estudiante lo reconozca de inmediato y sepa cómo resolverlo sin perder tiempo debuggeando Docker.

---

## 3. Pruebas de carga — instalación de JMeter

**Sección afectada:** [`## Pruebas de carga`](lab_2_pruebas_carga.md#pruebas-de-carga)

**Problema:** El laboratorio asume que el estudiante ya sabe instalar y usar JMeter. En la práctica, esta es una de las principales fuentes de bloqueo y pérdida de tiempo, ya que muchos estudiantes nunca lo han usado.

**Mejora sugerida:** Agregar, junto al link del [recurso de componentes de JMeter](https://testertina.medium.com/a-beginners-guide-to-performance-testing-with-apache-jmeter-be7a7eb0a6ad):
- Un mini-tutorial (o link a la [página oficial de descarga](https://jmeter.apache.org/download_jmeter.cgi)) con los pasos de instalación para los sistemas operativos más comunes (Windows, macOS, Linux).
- Aclarar requisitos previos (versión de Java requerida, por ejemplo), ya que un JMeter mal instalado es una causa frecuente de errores confusos al ejecutar las pruebas.

---

## 4. Ejecución de pruebas de carga alta — ambigüedad sobre el script

**Sección afectada:** [`#### Ejecución de pruebas de carga alta`](lab_2_pruebas_carga.md#ejecución-de-pruebas-de-carga-alta)

**Problema:** El texto actual dice que para cargas > 450 threads "se invita" a usar un script generado con IA como *alternativa* a JMeter, pero no queda claro si:
- Es **obligatorio** generar y ejecutar ese script, o
- Es opcional y JMeter podría seguir usándose (a pesar de sus limitaciones de performance ya mencionadas).

Esta ambigüedad genera una pregunta razonable: si de todas formas hay que resolver el problema con un script propio, ¿para qué se pide usar JMeter en primer lugar, sabiendo que tiene problemas conocidos de ejecución?

**Mejora sugerida:** Aclarar explícitamente en el enunciado:
- Que JMeter se usa para los escenarios de carga baja/media/normal (hasta 450 threads) porque permite visualizar y aprender los componentes de una prueba de carga de forma gráfica (ese es su valor pedagógico).
- Que el script en Python **sí es obligatorio** para los escenarios de alta carga (> 450 threads) porque JMeter deja de ser una herramienta confiable en ese rango, y no porque JMeter esté descartado del laboratorio.

---

## 5. Entregables — mínimo de pruebas no especificado

**Sección afectada:** [`## Entregables`](lab_2_pruebas_carga.md#entregables) y [`### Matriz mínima de pruebas`](lab_2_pruebas_carga.md#matriz-mínima-de-pruebas-mínimo-recomendado)

**Problema:** La tabla de entregables solo muestra 3 filas de ejemplo, lo cual se puede malinterpretar como que basta con reportar dos pruebas (una para operación normal y otra para el evento de promociones). Sin embargo, la intención real del laboratorio —según la sección de "Matriz mínima de pruebas"— es que el estudiante **incremente el número de hilos de forma controlada y progresiva** hasta encontrar el punto de inflexión, ejecutando como mínimo 8 corridas para los escenarios de operación normal y estrés fuerte, y al menos 4 para los demás.

**Mejora sugerida:** Ajustar la tabla de entregables para que:
- Tenga como mínimo tantas filas como pruebas mínimas se piden en la matriz (8 escenarios base, más las repeticiones exigidas), en lugar de solo 3 filas de ejemplo.
- Se agregue una nota explícita antes de la tabla aclarando: *"No es suficiente con reportar únicamente los escenarios de operación normal y evento de promociones; se espera que documente el incremento progresivo de carga y las repeticiones indicadas en la matriz mínima de pruebas, con el fin de ubicar con precisión el punto de inflexión."*

---

## 6. Falta un índice del documento

**Sección afectada:** encabezado del documento [`lab_2_pruebas_carga.md`](lab_2_pruebas_carga.md)

**Problema:** El laboratorio es extenso (más de 300 líneas, con 5 etapas, 4 preguntas intercaladas y una sección de entregables), pero no tiene un índice al inicio. Esto dificulta que el estudiante ubique rápidamente una sección puntual (por ejemplo, volver a la matriz de pruebas o a una pregunta específica) sin hacer scroll manual por todo el documento.

**Mejora sugerida:** Agregar una tabla de contenido (índice) justo debajo del título principal, enlazando a los encabezados existentes, por ejemplo:

```markdown
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
```

Muchos visores de Markdown (GitHub incluido) generan anclas automáticamente a partir de los encabezados, por lo que este índice funcionaría como navegación clicable sin necesidad de herramientas adicionales.

---

## Resumen de acciones

| # | Sección del laboratorio | Acción propuesta |
|---|--------------------------|-------------------|
| 1 | Diagrama de despliegue | Agregar caption descriptivo a la imagen |
| 2 | Preparación del entorno | Agregar comando de `git checkout`, repetir link del repo, explicar `docker compose up` y su requisito de directorio, documentar limpieza de contenedores previos y el error de puerto ocupado |
| 3 | Pruebas de carga | Agregar tutorial o link oficial de instalación de JMeter |
| 4 | Ejecución de pruebas de carga alta | Aclarar que JMeter aplica hasta 450 threads y el script propio es obligatorio para cargas mayores |
| 5 | Entregables | Ampliar tabla de resultados esperados y aclarar que se espera el incremento progresivo completo de la matriz mínima, no solo 2 escenarios |
| 6 | Encabezado del documento | Agregar índice navegable al inicio del laboratorio |
