# Crear una instancia RDS PostgreSQL para Cheapest

## Objetivos

- Crear una instancia de Amazon RDS con PostgreSQL para el laboratorio.
- Configurar red y seguridad para permitir acceso a la base de datos.

## Marco conceptual

### Amazon RDS

Amazon Relational Database Service (RDS) es un servicio administrado para bases de datos relacionales. Permite aprovisionar motores como PostgreSQL sin administrar directamente el sistema operativo ni tareas base de operacion como backups automáticos, parches y monitoreo.

Mas informacion en: [Amazon RDS](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Welcome.html)

### PostgreSQL en RDS

RDS para PostgreSQL ofrece un motor compatible con PostgreSQL administrado por AWS.

### Security Groups y Subnet Group

- Security Group: controla que origenes y puertos pueden conectarse a la base.
- DB Subnet Group: define en que subredes de la VPC puede desplegarse la instancia RDS.

## Tutorial consola AWS

Puede crear RDS desde la interfaz grafica siguiendo la guia oficial:
[Creación de una instancia de base de datos de PostgreSQL](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_PostgreSQL.html)

## Tutorial CloudShell (AWS CLI)

### 0. Configuracion objetivo

| Parámetro | Valor sugerido |
| --- | --- |
| Motor | PostgreSQL |
| Identificador DB | `Cheapest-rds` |
| Usuario admin | `postgres` |
| Clase | `db.t3.micro` |
| Almacenamiento | 20 GB |
| Multi-AZ | No (laboratorio) |
| Acceso público | No |

### 1. Identificar VPC y subredes

```bash
aws ec2 describe-vpcs --query "Vpcs[*].{VpcId:VpcId,Cidr:CidrBlock}" --output table
```

```bash
aws ec2 describe-subnets --filters Name=vpc-id,Values=<VPC_ID> --query "Subnets[*].{SubnetId:SubnetId,AZ:AvailabilityZone,Cidr:CidrBlock}" --output table
```

Guarde al menos 2 subredes de distintas zonas:

- `SUBNET_1`
- `SUBNET_2`

### 2. Crear DB Subnet Group

```bash
aws rds create-db-subnet-group  --db-subnet-group-name Cheapest-db-subnet-group  --db-subnet-group-description "Subnet group para RDS de Cheapest"  --subnet-ids <SUBNET_1> <SUBNET_2>
```

### 3. Crear Security Group para RDS

Cree un security group que permita trafico en el puerto 5432:

```bash
aws ec2 create-security-group  --group-name Cheapest-rds-sg  --description "Acceso a RDS de Cheapest"  --vpc-id <VPC_ID>
```

Guarde el `GroupId` devuelto (`SG_RDS_ID`). Autorice el trafico entrante en 5432 desde el security group que usan las tareas de ECS (`SG_ECS_ID`, el mismo que usara en el tutorial de ECS), en vez de abrirlo a `0.0.0.0/0`:

```bash
aws ec2 authorize-security-group-ingress  --group-id <SG_RDS_ID>  --protocol tcp --port 5432  --source-group <SG_ECS_ID>
```

> [!NOTE]
> Si aun no ha creado el security group de ECS, puede crear primero un security group vacio para ECS (ver [tutorial de ECS](./crear_instancia_ecs.md)), anotar su `GroupId` y usarlo aqui como `SG_ECS_ID`.

### 4. Crear la instancia RDS PostgreSQL

```bash
aws rds create-db-instance  --db-instance-identifier Cheapest-rds  --db-instance-class db.t3.micro --db-name Cheapest  --engine postgres  --engine-version 18.2  --master-username postgres  --master-user-password <PASSWORD_SEGURA>  --allocated-storage 20  --db-subnet-group-name Cheapest-db-subnet-group  --vpc-security-group-ids <SG_RDS_ID>  --no-publicly-accessible  --backup-retention-period 1  --storage-type gp3
```

### 5. Esperar disponibilidad

```bash
aws rds wait db-instance-available --db-instance-identifier Cheapest-rds
```

### 6. Consultar endpoint de conexion

```bash
aws rds describe-db-instances --db-instance-identifier Cheapest-rds --query "DBInstances[0].Endpoint.{Address:Address,Port:Port}" --output table
```

Con esto obtiene:

- `DB_HOST`
- `DB_PORT` (normalmente 5432)

## 7. Cargar datos base (`npm run db:seed`)

> [!IMPORTANT]
> Esta instancia se crea con `--no-publicly-accessible`, por lo que **no es alcanzable desde su laptop** sin importar las reglas del security group. Correr `npm run db:seed` directamente desde su maquina fallara por timeout, o peor, si no define `DB_HOST` sembrara silenciosamente un Postgres local (el script hace `process.env.DB_HOST ??= '127.0.0.1'`) dandole una falsa sensacion de exito.

Para sembrar esta RDS privada desde su laptop, hagalo temporalmente publica y restrinja el acceso a su propia IP:

```bash
# 1. Anote su IP publica actual
curl -s https://checkip.amazonaws.com

# 2. Haga la instancia temporalmente publica
aws rds modify-db-instance --db-instance-identifier Cheapest-rds --publicly-accessible --apply-immediately

# 3. Espere a que el cambio se aplique (puede tardar 1-2 minutos)
aws rds describe-db-instances --db-instance-identifier Cheapest-rds --query "DBInstances[0].PubliclyAccessible"

# 4. Abra el puerto 5432 SOLO para su IP (no 0.0.0.0/0: expondria credenciales de DB a internet)
aws ec2 authorize-security-group-ingress  --group-id <SG_RDS_ID>  --protocol tcp --port 5432  --cidr <SU_IP_PUBLICA>/32

# 5. Corra el seed apuntando explicitamente a RDS
DB_HOST=<DB_HOST> DB_PORT=5432 DB_USER=postgres DB_PASSWORD=<PASSWORD_SEGURA> DB_NAME=Cheapest npm run db:seed
```

Al terminar, **revierta ambos cambios** para no dejar la base expuesta:

```bash
aws rds modify-db-instance --db-instance-identifier Cheapest-rds --no-publicly-accessible --apply-immediately
aws ec2 revoke-security-group-ingress  --group-id <SG_RDS_ID>  --protocol tcp --port 5432  --cidr <SU_IP_PUBLICA>/32
```

## Resultado final

Al finalizar debe tener:

| Recurso | Nombre sugerido | Estado esperado |
| --- | --- | --- |
| DB Subnet Group | `Cheapest-db-subnet-group` | Creado |
| Security Group RDS | `Cheapest-rds-sg` | 5432 habilitado |
| Instancia RDS | `Cheapest-rds` | `available` |

## Limpiar recursos (opcional)

Si termina el laboratorio y no necesita la base:

```bash
aws rds delete-db-instance  --db-instance-identifier Cheapest-rds  --skip-final-snapshot
```

Luego puede eliminar subnet group y security group si ya no se usan.
