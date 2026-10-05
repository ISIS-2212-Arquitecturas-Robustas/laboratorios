# Warm-up en clase — Lab 2: Pruebas de Carga al Monolito de Cheapest

## Contexto

Se van a probar dos endpoints del backend monolítico de Cheapest:

| Endpoint | Qué hace | ASR a cumplir |
| --- | --- | --- |
| `GET /logistics/tenderos/productos-disponibles?tiendaId=&zona=` | Consulta con varios JOINs: pedidos históricos ∩ promociones activas ∩ catálogo con disponibilidad de la zona | p99 < 1000 ms en operación normal (500 req/min) |
| `POST /logistics/pedidos` | Escritura transaccional de un pedido con múltiples ítems | Error % ≤ 2% en pico (5000 req/min) |

El proyecto trae un script de seed (`src/datasources/database-seeder.service.ts`) que lee el archivo `src/datasources/load-seed.yaml` donde usted define **cuántos registros crear por tabla y cómo se distribuyen**: además de los conteos por tabla, el archivo acepta las llaves `tiendas`, `zonas` y `distribucion` para controlar cuántas tiendas/zonas existen y qué tan concentrada está la actividad en ellas.

## Tarea

Complete el `load-seed.yaml` con números concretos (no "muchos" o "pocos", sino cantidades exactas) para que el escenario sea realista y no uniforme — el propio laboratorio le pide considerar que "hay tiendas que compran mucho más que otras, zonas con más actividad comercial y productos que son más populares que otros":

| Entidad | Cantidad total |
| --- | ---: |
| Tiendas | |
| Zonas | |
| Catálogos por zona | |
| Productos | |
| Promociones activas | |
| Pedidos históricos por tienda | |

**Cómo se distribuye la actividad:** la concentración (`distribucion` de `load-seed.yaml`) es una configuración global y afecta a la vez a tiendas, zonas y productos (cada una con su propio sesgo, pero con el mismo `peso_cabeza`/`fraccion_cabeza`). Descríbalo:

> _(ej: "20% de las tiendas y zonas concentran el 80% de la actividad (pedidos, catálogos), y 20% de los productos concentran el 80% de las promociones e items de pedido")_

## Cierre de la sesión

Cada estudiante debe terminar con el `load-seed.yaml` completo. Este es el archivo real que van a usar para poblar la base de datos al ejecutar el laboratorio, y es exactamente la base de la respuesta al punto 1 de los entregables ("Describa la distribución de los datos y la razón de los mismos"). No hay que rediseñarlo después.
