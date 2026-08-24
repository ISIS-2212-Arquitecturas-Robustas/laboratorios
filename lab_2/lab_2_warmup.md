# Warm-up en clase — Lab 2: Pruebas de Carga al Monolito de Cheapest

## Contexto

Se van a probar dos endpoints del backend monolítico de Cheapest:

| Endpoint | Qué hace | ASR a cumplir |
| --- | --- | --- |
| `GET /logistics/tenderos/productos-disponibles?tiendaId=&zona=` | Consulta con varios JOINs: pedidos históricos ∩ promociones activas ∩ catálogo con disponibilidad de la zona | p99 < 1000 ms en operación normal (500 req/min) |
| `POST /logistics/pedidos` | Escritura transaccional de un pedido con múltiples ítems | Error % ≤ 2% en pico (5000 req/min) |

El proyecto trae un script de seed (`src/datasources/database-seeder.service.ts`) que lee el archivo `src/datasources/load-seed.yaml` donde ustedes definen **cuántos registros crear por tabla y cómo se distribuyen**: además de los conteos por tabla, el archivo acepta las llaves `tiendas`, `zonas` y `distribucion para controlar cuántas tiendas/zonas existen y qué tan concentrada está la actividad en ellas.

## Tarea 

Complete el `load-seed.yaml` con números concretos (no "muchos" o "pocos", sino cantidades exactas) para que el escenario sea realista y no uniforme — el propio laboratorio les pide considerar que "hay tiendas que compran mucho más que otras, zonas con más actividad comercial y productos que son más populares que otros" (distribución tipo Pareto, no uniforme):

| Entidad | Cantidad total | Cómo se distribuye (zonas/tiendas con más o menos peso) |
| --- | ---: | --- |
| Tiendas | | |
| Zonas | | |
| Catálogos por zona | | |
| Productos | | |
| Promociones activas | | |
| Pedidos históricos por tienda | | |

Para cada fila, escriba en una línea el criterio que usó para el número (ej: "80 tiendas, 20% en 'Zona Norte' concentran 60% de los pedidos históricos, el resto distribuido uniformemente en las otras 4 zonas").

## Cierre de la sesión

Cada estudiante debe terminar con el `load-seed.yaml` completo. Este es el archivo real que van a usar para poblar la base de datos al ejecutar el laboratorio, y es exactamente la base de la respuesta al punto 1 de los entregables ("Describa la distribución de los datos y la razón de los mismos"). No hay que rediseñarlo después.
