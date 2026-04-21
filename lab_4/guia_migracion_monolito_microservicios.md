# Guía de Migración: De Monolito a Microservicios


Este documento describe el proceso de migración de **chiper-api** (monolito NestJS) a el proyecto en la rama **microservices** (arquitectura de microservicios con NestJS monorepo).

La API gestiona tres dominios de negocio:
- **Logística**: catálogo de productos, pedidos, despachos, promociones
- **Inventario**: ítems por tienda, registros de compra/venta
- **Ventas**: transacciones de venta e ítems de venta

---

## 1. Arquitectura original: Monolito

```
chiper-api/
└── src/
    ├── datasources/          # Configuración central de base de datos
    ├── logistica/            # Módulo de logística
    │   ├── controllers/
    │   ├── services/
    │   ├── repositories/
    │   └── dtos/
    ├── inventario/           # Módulo de inventario
    │   ├── controllers/
    │   ├── services/
    │   ├── repositories/
    │   ├── dtos/
    │   └── clients/          # Llamadas internas
    ├── ventas/               # Módulo de ventas
    ├── app.module.ts         # Módulo raíz que importa los 3 dominios
    └── main.ts               # Único punto de entrada (puerto 3000)
```

### Características del monolito

| Aspecto | Detalle |
|--------|---------|
| Despliegue | 1 contenedor Docker |
| Puerto | 3000 |
| Base de datos | Conexión única; TypeORM descubre todas las entidades automáticamente |
| Comunicación entre módulos | Llamadas directas en proceso (inyección de dependencias) |
| Build | `npm run build` → un solo artefacto |

### Comunicación entre módulos

En el monolito, `InventarioService` llama directamente a `ProductoService` sin cruzar red:

```typescript
// inventario/services/item-inventario.service.ts
@Injectable()
export class ItemInventarioService {
  constructor(
    private readonly productoService: ProductoService,  // inyectado directamente
  ) {}

  async create(dto: CreateItemInventarioDto) {
    const exists = await this.productoService.exists(dto.productoId);
    if (!exists) throw new NotFoundException('Producto no encontrado');
    // ...
  }
}
```

---

## 2. Arquitectura objetivo: Microservicios

```
chiper-api-microservices/
├── apps/
│   ├── logistica/            # Aplicación 1 — puerto 3001
│   │   ├── src/
│   │   │   ├── app.module.ts
│   │   │   ├── health.controller.ts
│   │   │   └── main.ts
│   │   └── Dockerfile
│   ├── inventario/           # Aplicación 2 — puerto 3002
│   │   ├── src/
│   │   │   ├── app.module.ts
│   │   │   ├── health.controller.ts
│   │   │   └── main.ts
│   │   └── Dockerfile
│   └── ventas/               # Aplicación 3 — puerto 3003
│       ├── src/
│       │   ├── app.module.ts
│       │   ├── health.controller.ts
│       │   └── main.ts
│       └── Dockerfile
└── libs/
    ├── logistica/            # Lógica de negocio como librería compartida
    ├── inventario/
    ├── ventas/
    └── shared/
        ├── database/         # Módulo de BD reutilizable
        ├── logistica-client/ # Cliente HTTP para comunicación entre servicios
        └── tienda-client/    # Cliente mock para servicio externo
```

### Características de los microservicios

| Aspecto | Detalle |
|--------|---------|
| Despliegue | 3 contenedores Docker independientes |
| Puertos | logistica: 3001 · inventario: 3002 · ventas: 3003 |
| Base de datos | Compartida (PostgreSQL), pero cada servicio registra solo sus entidades |
| Comunicación entre servicios | HTTP con cliente dedicado y timeout configurable |
| Build | `npm run build` construye los 3 servicios; también se puede construir por separado |

---

## 3. Cambios paso a paso

### 3.1 Convertir el proyecto a monorepo NestJS

El primer cambio estructural fue convertir el proyecto en un **monorepo NestJS**, que permite tener múltiples aplicaciones y librerías compartidas en un mismo repositorio.

El patrón monorepo es ampliamente utilizado en la construcción de microservicios porque facilita compartir código común (librerías), especialemnte cuando los microservicios comparten lenguaje y framework. Para que entienda que es un monorepo, consulte el siguiente [blog](https://circleci.com/blog/monorepo-dev-practices/)

```bash
# En el monolito, un solo tsconfig.json y package.json raíz.
# En el monorepo, se agrega nest-cli.json con la configuración de proyectos:
```

Nest permite configurar monorepos con un archivo `nest-cli.json` donde se definen las aplicaciones (`apps/`) y las librerías (`libs/`). Esto facilita la gestión de dependencias y el build de cada servicio.

```json
// nest-cli.json
{
  "monorepo": true,
  "root": "apps/logistica",
  "projects": {
    "logistica": { "type": "application", "root": "apps/logistica" },
    "inventario": { "type": "application", "root": "apps/inventario" },
    "ventas": { "type": "application", "root": "apps/ventas" },
    "shared-database": { "type": "library", "root": "libs/shared/database" },
    "logistica-client": { "type": "library", "root": "libs/shared/logistica-client" }
  }
}
```

### 3.2 Extraer la lógica de negocio a librerías (`libs/`)

La lógica de los módulos se **movió** de `src/*/` a `libs/*/`, sin cambios en el código de negocio. Esto permite que cada aplicación en `apps/` importe la librería correspondiente y que las librerías sean reutilizables.

```
ANTES (monolito):          DESPUÉS (microservices):
src/logistica/     →       libs/logistica/
src/inventario/    →       libs/inventario/
src/ventas/        →       libs/ventas/
src/datasources/   →       libs/shared/database/
```

Cada `app` en `apps/` queda mínima:

```typescript
// apps/logistica/src/app.module.ts
@Module({
  imports: [LogisticaModule],  // importa la librería
})
export class AppModule {}
```

### 3.3 Crear módulo de base de datos dinámico

El monolito usaba un módulo de base de datos estático que descubría todas las entidades con un glob:

```typescript
// ANTES — src/datasources/database.providers.ts
entities: [__dirname + '/../**/*.entity{.ts,.js}'],  // descubre todo
```

En microservicios se creó un módulo dinámico en `libs/shared/database/` que recibe las entidades explícitamente:

```typescript
// DESPUÉS — libs/shared/database/src/database.module.ts
@Module({})
export class DatabaseModule {
  static forRoot(entities: EntityClassOrSchema[]): DynamicModule {
    return {
      module: DatabaseModule,
      providers: [
        {
          provide: DATA_SOURCE,
          useFactory: async () => {
            const dataSource = new DataSource({
              type: 'postgres',
              // ...config desde env vars
              entities,  // solo las entidades del servicio
              synchronize: process.env.DB_SYNCHRONIZE === 'true',
            });
            return dataSource.initialize();
          },
        },
      ],
      exports: [DATA_SOURCE],
    };
  }
}
```

Cada servicio registra únicamente sus propias entidades:

```typescript
// apps/logistica/src/app.module.ts
DatabaseModule.forRoot([
  Producto, Catalogo, Pedido, ItemPedido,
  Despacho, DisponibilidadZona, Promocion, NotaCredito,
])

// apps/inventario/src/app.module.ts
DatabaseModule.forRoot([
  ItemInventario, RegistroCompraProductoTienda, RegistroVentaProductoTienda,
])
```

### 3.4 Reemplazar llamadas en proceso por HTTP

Este es el cambio más importante en términos de arquitectura. Las llamadas directas entre módulos se convirtieron en llamadas HTTP entre servicios.

**Se creó un cliente HTTP dedicado** en `libs/shared/logistica-client/`:

```typescript
// libs/shared/logistica-client/src/logistica-productos.client.ts
@Injectable()
export class LogisticaProductosClient {
  private readonly baseUrl: string;
  private readonly timeoutMs: number;

  constructor() {
    this.baseUrl = process.env.LOGISTICA_BASE_URL ?? 'http://localhost:3001';
    this.timeoutMs = Number(process.env.LOGISTICA_TIMEOUT_MS ?? 3000);
  }

  async exists(productoId: string): Promise<boolean> {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.timeoutMs);

    try {
      const response = await fetch(
        `${this.baseUrl}/logistics/productos/${productoId}`,
        { method: 'GET', signal: controller.signal },
      );
      return response.ok;
    } catch {
      throw new ServiceUnavailableException('Servicio de logística no disponible');
    } finally {
      clearTimeout(timeout);
    }
  }
}
```

**El servicio de inventario ahora usa el cliente HTTP** en lugar de inyectar `ProductoService`:

```typescript
// libs/inventario/src/services/item-inventario.service.ts
@Injectable()
export class ItemInventarioService {
  constructor(
    // ANTES: private readonly productoService: ProductoService
    private readonly productoClient: LogisticaProductosClient,  // DESPUÉS
  ) {}

  async create(dto: CreateItemInventarioDto) {
    const exists = await this.productoClient.exists(dto.productoId);
    if (!exists) throw new NotFoundException('Producto no encontrado');
    // ...
  }
}
```

### 3.5 Agregar health checks

Cada servicio expone un endpoint `/health` para que Docker y los otros servicios puedan verificar su disponibilidad antes de enviar tráfico:

```typescript
// apps/logistica/src/health.controller.ts
@Controller('health')
export class HealthController {
  @Get()
  check() {
    return { status: 'ok', service: 'logistica' };
  }
}
```

### 3.6 Actualizar docker-compose.yml

```yaml
# ANTES — monolito
services:
  postgres:
    image: postgres:15-alpine
  app:
    build: .
    ports: ["3000:3000"]
    depends_on: [postgres]

# DESPUÉS — microservicios
services:
  postgres:
    image: postgres:15-alpine

  logistica:
    build:
      context: .
      dockerfile: apps/logistica/Dockerfile
    ports: ["3001:3001"]
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      - LOGISTICA_BASE_URL=http://logistica:3001

  inventario:
    build:
      context: .
      dockerfile: apps/inventario/Dockerfile
    ports: ["3002:3002"]
    depends_on:
      logistica:            # inventario espera a que logistica esté saludable
        condition: service_healthy
    environment:
      - LOGISTICA_BASE_URL=http://logistica:3001

  ventas:
    build:
      context: .
      dockerfile: apps/ventas/Dockerfile
    ports: ["3003:3003"]
    depends_on:
      logistica:            # ventas también depende de logistica
        condition: service_healthy
    environment:
      - LOGISTICA_BASE_URL=http://logistica:3001
```

### 3.7 Actualizar scripts de build

```json
// package.json — scripts agregados en microservicios
{
  "scripts": {
    "build": "npm run build:logistica && npm run build:inventario && npm run build:ventas",
    "build:logistica": "nest build logistica",
    "build:inventario": "nest build inventario",
    "build:ventas": "nest build ventas",
    "start:logistica:prod": "node dist/apps/logistica/main",
    "start:inventario:prod": "node dist/apps/inventario/main",
    "start:ventas:prod": "node dist/apps/ventas/main"
  }
}
```

---

## 4. Variables de entorno

| Variable | Monolito | Microservicios | Descripción |
|----------|----------|----------------|-------------|
| `DB_HOST` | ✓ | ✓ | Host de PostgreSQL |
| `DB_PORT` | ✓ | ✓ | Puerto de PostgreSQL |
| `DB_USERNAME` | ✓ | ✓ | Usuario de BD |
| `DB_PASSWORD` | ✓ | ✓ | Contraseña de BD |
| `DB_NAME` | ✓ | ✓ | Nombre de la base de datos |
| `NODE_ENV` | ✓ | ✓ | Entorno de ejecución |
| `LOGISTICA_BASE_URL` | — | ✓ | URL del servicio de logística |
| `LOGISTICA_TIMEOUT_MS` | — | ✓ | Timeout para llamadas HTTP (default: 3000ms) |
| `DB_SYNCHRONIZE` | — | ✓ | Controla sincronización de esquema |
| `DB_CONNECT_TIMEOUT_MS` | — | ✓ | Timeout de conexión a BD |

---

## 5. Endpoints: comparación de puertos

Los endpoints son **idénticos** en ambas versiones; solo cambia el puerto donde se sirven.

| Dominio | Endpoint | Monolito | Microservicio |
|---------|----------|----------|---------------|
| Logística | `/logistics/productos/*` | :3000 | :3001 |
| Logística | `/logistics/pedidos/*` | :3000 | :3001 |
| Logística | `/logistics/despachos/*` | :3000 | :3001 |
| Inventario | `/inventory/items/*` | :3000 | :3002 |
| Ventas | `/ventas/ventas/*` | :3000 | :3003 |
| Health | `/health` | — | :3001, :3002, :3003 |

---

## 6. Comparación final

| Aspecto | Monolito | Microservicios |
|--------|----------|----------------|
| Contenedores | 1 | 3 |
| Puertos | 3000 | 3001, 3002, 3003 |
| Comunicación interna | En proceso (0ms) | HTTP (~1-3ms) |
| Fallo de un módulo | Afecta toda la app | Aislado por servicio |
| Escalado | Toda la app | Por dominio |
| Base de datos | Conexión única, entidades globales | Compartida, entidades por servicio |
| Build | 1 artefacto | 3 artefactos independientes |
| Complejidad de desarrollo | Baja | Media |
| Complejidad de despliegue | Baja | Media |

### Dependencias entre servicios

`logistica` es el servicio raíz: no depende de nadie. `inventario` y `ventas` consultan a `logistica` para validar productos.

---

## 7. Decisiones de diseño destacadas

1. **Monorepo en lugar de repos separados**: facilita compartir librerías (`libs/shared/`) y mantener consistencia de versiones entre servicios.

2. **Base de datos compartida**: se eligió una BD compartida en lugar de una BD por servicio pensando en que Chiper cuenta con datos reales y valiosos que tendrán que migrarse de forma gradual.

3. **Librerías en `libs/`**: toda la lógica de negocio vive en librerías, no en las apps. Las apps son solo puntos de entrada (`main.ts` + `app.module.ts`), lo que facilita reutilizar la lógica si se agregan nuevas apps.
