# Warm-up en clase — Lab 1: Fundamentos de Nest

> Esta es una actividad *opcional* previa al laboratorio. El enunciado completo del Lab 1 está en [`lab_1_nest.md`](lab_1_nest.md).

## Contexto

Cheapest ya tiene un CRUD completo implementado para la entidad `Catalogo`, con arquitectura por capas (`Entity` → `Repository` → `Service` → `Controller`). Este es el patrón exacto que usarán en el resto del curso.

`Catalogo` entity (referencia):

```typescript
@Entity('catalogos')
export class Catalogo {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column('uuid')
  tiendaId: string;

  @Column('timestamp')
  vigenciaDesde: Date;

  @Column('timestamp')
  vigenciaHasta: Date;

  @Column('varchar', { length: 255 })
  zona: string;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;

  @ManyToMany(() => Producto, (producto) => producto.catalogos)
  @JoinTable()
  productos: Producto[];
}
```

`CreateCatalogoDto` (referencia):

```typescript
export class CreateCatalogoDto {
  @IsUUID()
  tiendaId: string;

  @IsDateString()
  vigenciaDesde: Date;

  @IsDateString()
  vigenciaHasta: Date;

  @IsString()
  @MaxLength(255)
  zona: string;
}
```

El diagrama de dominio completo está en [`recursos/Modelo_Dominio_Cheapest.pdf`](recursos/Modelo_Dominio_Cheapest.pdf). De ahí necesitan solo los campos de `Producto`: `codigoInterno`, `codigoBarras`, `nombre`, `marca`, `categoria`, `presentacion`, `precioBase`, `monedaId`, y su relación many-to-many con `Catalogo` (ya está definida en la entidad de arriba).

## Tarea 

> ⚠️ **Nota:** los cuatro archivos que se piden a continuación **ya existen, implementados, en el [repositorio de Cheapest-api](https://github.com/ISIS-2212-Arquitecturas-Robustas/Cheapest-api)** (rama `main`). El objetivo de este warm-up **no** es producir código nuevo, sino que cada equipo lo escriba por su cuenta a partir del patrón de `Catalogo` para afianzar la comprensión de `Entity`/DTOs antes de verlos ya resueltos en el repositorio.

En un IDE con soporte de TypeScript instalado (por ejemplo VS Code con las dependencias del proyecto instaladas, para tener resaltado de errores y autocompletado — no es necesario correr la aplicación ni la base de datos), escriban el código de los siguientes archivos siguiendo **exactamente el mismo patrón** que `Catalogo`:

1. **`producto.entity.ts`** — entidad `Producto` con TypeORM: `id` (uuid), `codigoInterno`, `codigoBarras`, `nombre`, `marca`, `categoria`, `presentacion`, `precioBase`, `monedaId` (uuid), `createdAt`, `updatedAt`, y la relación inversa `@ManyToMany` hacia `Catalogo`.
2. **`create-producto.dto.ts`** — DTO de creación con `class-validator` (`@IsString`, `@IsNumber`, `@MaxLength`, etc. según el tipo de cada campo).
3. **`update-producto.dto.ts`** — DTO de actualización
4. **`query-producto.dto.ts`** — DTO de consulta con al menos un filtro opcional (por ejemplo `categoria`).

**No es necesario** escribir el Repository, Service ni Controller todavía — eso lo verán en el resto del laboratorio, donde reutilizarán directamente lo que escribieron aquí.

## Cierre de la sesión

Cada equipo debe terminar con los 4 archivos escritos en el IDE, sin errores de compilación de TypeScript (no es necesario ejecutar la aplicación). Este código se integra tal cual como parte del **Entregable 2.1 (CRUD de Producto)** del Lab 1 — no hay que rehacerlo después.
