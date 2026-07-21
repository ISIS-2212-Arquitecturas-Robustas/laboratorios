# Warm-up en clase — Lab 8: Microservicios Orientados a Eventos (EDA, CQRS y Event Sourcing)

## Contexto

El código vive en la rama `Cheapest-eda` del repositorio `Cheapest-api`. La entidad `EventoPedido` ya está definida. Algunos métodos tienen `throw new Error('Not implemented')` que deben completarse; otros ya están implementados y solo hay que revisarlos.

## Tarea 

### 5. Parte 1 - Event Sourcing: historial de Pedidos

#### Tarea 1.1 - Completar `EventoPedidoRepository`

Archivo: `libs/logistica/src/repositories/evento-pedido.repository.ts`

Implemente `nextVersion(pedidoId)` y `appendEvent(data)`:

```typescript
async nextVersion(pedidoId: string): Promise<number> {
  // Buscar el último evento del pedido ordenado por version DESC.
  // Si no existe ninguno, retornar 1.
  // Hint: this.repository.findOne({ where: { pedidoId }, order: { version: 'DESC' } })
}

async appendEvent(data: Omit<EventoPedido, 'id' | 'createdAt'>): Promise<EventoPedido> {
  // Crear y guardar el evento.
  // Hint: const entity = this.repository.create(data); return this.repository.save(entity);
}
```

#### Tarea 1.2 - Revisar `PedidoService.update()`

Archivo: `libs/logistica/src/services/pedido.service.ts`

El método `update()` ya tiene el esqueleto que llama a `eventoPedidoRepository.nextVersion(id)`. Verifique que:
1. La llamada a `appendEvent()` ocurre **dentro de la transacción** junto con el `UPDATE pedidos`.
2. El evento `PedidoCambioEstado` incluye `estadoAnterior`, `estadoNuevo` y `version`.
3. Sólo se registra el evento si `dto.estado` es diferente al estado actual.

#### Tarea 1.3 - Verificar el endpoint de historial

El endpoint `GET /logistics/pedidos/:id/historial` ya está registrado en `PedidoController`. Verifique que `getHistorial()` en `PedidoService` retorna los eventos ordenados por `version ASC`.

Con el código completo, esta es la verificación esperada (guárdenla para correrla apenas tengan el stack desplegado): crear un pedido, avanzar su estado tres veces con `PATCH`, y consultar `/historial` — la respuesta debe mostrar **4 eventos** en orden: `PedidoCreado` (versión 1) + 3 `PedidoCambioEstado` (versiones 2, 3, 4).

### 6. Parte 2 - CQRS Read Model

#### Tarea 3.1 - Revisar `updateResumenTienda()` en `VentaCreadaConsumer`

Archivo: `libs/inventario/src/consumers/venta-creada.consumer.ts`

El método `updateResumenTienda()` ya tiene la expresión DynamoDB completa. Verifique que los `ExpressionAttributeValues` son correctos:
- `:uno` → `1` (para el `ADD ventasMes`)
- `:total` → `Number(payload.total)` (para el `ADD totalVentasMes`)
- `:nuevaVenta` → array de un elemento con `{ ventaId, fechaHora, total }`

#### Tarea 3.2 - Revisar `ResumenTiendaService.getResumen()`

Archivo: `libs/ventas/src/services/resumen-tienda.service.ts`

El método `getResumen()` ya hace el `GetItem` de DynamoDB. Verifique que la clave `{ tiendaId, sk: 'RESUMEN' }` coincide con la clave que el consumer escribe en `updateResumenTienda()`.

## Cierre de la sesión

Al terminar, cada equipo debe tener las Tareas 1.1 a 1.3 y 3.1 a 3.2 completas/revisadas y el pull request o commit listo. Esto es exactamente el código que pide el laboratorio en las secciones 5 y 6 — no hay que rehacerlo después, se sigue directamente con el despliegue y el experimento comparativo de la sección 7.
