# Warm-up en clase — Lab 7: Limitaciones de los Microservicios Orientados a Conexión (Fan-out)

## Contexto

El endpoint `GET /ventas/resumen-operativo` llama secuencialmente a Logística e Inventario. El experimento tiene tres fases: (1) baseline por servicio individual, (2) carga sobre el endpoint orquestado, (3) con Inventario reducido a 1 tarea ECS (`desired count = 1`, sin apagarlo).

## Tarea 

### Pregunta 2

> ¿Por qué reducir el `desired count` de Inventario a 1 tarea (sin apagarlo) es un experimento más representativo de una situación real que apagar el servicio por completo?
> Relacione su respuesta con el concepto de **saturación** en la fórmula de fan-out y con escenarios reales de Cheapest.

### Pregunta 3

> Proponga **una alternativa arquitectónica** al patrón de orquestación síncrona que permita entregar el resumen operativo a los tenderos con p99 < 500 ms, sin necesidad de que Ventas llame síncronamente a Logística e Inventario en el momento de la petición.
> Analice los trade-offs de su propuesta en términos de consistencia de datos, complejidad operativa y costo de implementación para Cheapest.

Para la Pregunta 3, tengan en cuenta esta tabla del laboratorio con las tácticas que **no** resuelven el problema estructural, para no proponer algo que ya sabemos que no funciona:

| Táctica | ¿Por qué no resuelve el problema estructural? |
| --- | --- |
| Escalamiento horizontal de ECS (servicios dependientes) | Reduce $\rho_i$ y mejora latencia individual, pero el fan-out sigue multiplicando la carga: escalar los servicios dependientes no elimina el compounding de p99. |
| Timeouts más cortos en el orquestador | Reduce la latencia máxima pero aumenta el error %: cambiar el síntoma no corrige la causa. |
| Retry en el orquestador | Amplifica el fan-out: con 1 reintento, $F = L \times N \times 2$. Empeora la saturación de los servicios dependientes. |
| Cacheo de respuestas de servicios dependientes | Mitiga el fan-out para datos que toleran staleness, pero los datos de stock e inventario requieren consistencia reciente en Cheapest. |
| Circuit breaker (sidecar, Lab 5) | Protege al orquestador de un servicio dependiente caído, pero no reduce la latencia compuesta cuando todos funcionan. Solo mueve el problema de latencia a graceful degradation. |

## Cierre de la sesión

Cada estudiante debe terminar con las respuestas escritas a las Preguntas 2 y 3. Son exactamente las respuestas que pide el laboratorio — no hay que rehacerlas después, se incluyen tal cual en los entregables. La Pregunta 3, en particular, es la base conceptual del Lab 8.
