# Crear una instancia RDS PostgreSQL para Chiper

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
| Identificador DB | `chiper-rds` |
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
aws rds create-db-subnet-group  --db-subnet-group-name chiper-db-subnet-group  --db-subnet-group-description "Subnet group para RDS de Chiper"  --subnet-ids <SUBNET_1> <SUBNET_2>
```

### 3. Crear Security Group para RDS

Cree un security group que permita trafico en el puerto 5432:

### 4. Crear la instancia RDS PostgreSQL

```bash
aws rds create-db-instance  --db-instance-identifier chiper-rds  --db-instance-class db.t3.micro --db-name chiper  --engine postgres  --engine-version 18.2  --master-username postgres  --master-user-password <PASSWORD_SEGURA>  --allocated-storage 20  --db-subnet-group-name chiper-db-subnet-group  --vpc-security-group-ids <SG_RDS_ID>  --no-publicly-accessible  --backup-retention-period 1  --storage-type gp3
```

### 5. Esperar disponibilidad

```bash
aws rds wait db-instance-available --db-instance-identifier chiper-rds
```

### 6. Consultar endpoint de conexion

```bash
aws rds describe-db-instances --db-instance-identifier chiper-rds --query "DBInstances[0].Endpoint.{Address:Address,Port:Port}" --output table
```

Con esto obtiene:

- `DB_HOST`
- `DB_PORT` (normalmente 5432)

## Resultado final

Al finalizar debe tener:

| Recurso | Nombre sugerido | Estado esperado |
| --- | --- | --- |
| DB Subnet Group | `chiper-db-subnet-group` | Creado |
| Security Group RDS | `chiper-rds-sg` | 5432 habilitado |
| Instancia RDS | `chiper-rds` | `available` |

## Limpiar recursos (opcional)

Si termina el laboratorio y no necesita la base:

```bash
aws rds delete-db-instance  --db-instance-identifier chiper-rds  --skip-final-snapshot
```

Luego puede eliminar subnet group y security group si ya no se usan.
