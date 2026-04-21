# Configurar un Load Balancer para instancias EC2

## Objetivos

- Crear un Application Load Balancer (ALB) en AWS para exponer la API de Chiper.
- Conectar varias instancias EC2 de la aplicacion al balanceador mediante un Target Group.
- Validar que el trafico se distribuya correctamente entre instancias.

## Marco conceptual

### Application Load Balancer (ALB)

Un ALB distribuye trafico HTTP/HTTPS entre multiples destinos (targets), como instancias EC2. Tambien permite configurar health checks para enviar trafico solo a instancias saludables.

Mas informacion en: [Application Load Balancers](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/introduction.html)

### Target Group

Un Target Group agrupa los destinos que recibiran trafico del ALB. En este laboratorio, los destinos seran instancias EC2 donde corre el backend en el puerto 3000.

### Health Check

El health check es una verificacion periodica que hace el ALB para saber si una instancia esta disponible. Si una instancia falla, deja de recibir trafico temporalmente.

## Tutorial consola AWS

Puede seguir este tutorial usando CloudShell o la consola visual de AWS. Si prefiere interfaz grafica, tambien puede apoyarse en la documentacion oficial: [Create an Application Load Balancer](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/create-application-load-balancer.html)

## Tutorial CloudShell

### 0. Arquitectura objetivo

En este tutorial se asume una arquitectura minima:

- `chiper-app-1` (EC2 con backend)
- `chiper-app-2` (EC2 con backend)
- `chiper-app-3` (EC2 con backend)
- `chiper-alb` (Application Load Balancer)

> Si ya tiene una sola instancia (`chiper-app`), cree `chiper-app-2` y `chiper-app-3` para completar el balanceo con 3 targets.

### 1. Abrir AWS CloudShell

1. Inicie sesion en la AWS Console.
2. En la barra superior seleccione el icono de CloudShell.
3. Espere a que se abra la terminal.

### 2. Identificar VPC y subredes

El ALB requiere al menos dos subredes en diferentes zonas de disponibilidad.

```bash
aws ec2 describe-vpcs --query "Vpcs[*].{VpcId:VpcId,Cidr:CidrBlock}" --output table
```

Con el `VpcId` elegido, consulte subredes:

```bash
aws ec2 describe-subnets --filters Name=vpc-id,Values=<VPC_ID> --query "Subnets[*].{SubnetId:SubnetId,AZ:AvailabilityZone,Cidr:CidrBlock}" --output table
```

Guarde:

- `VPC_ID`
- `SUBNET_1`
- `SUBNET_2`

### 3. Crear Security Group del ALB

Este grupo permitira trafico HTTP publico al balanceador.

```bash
aws ec2 create-security-group  --group-name chiper-alb-http  --description "HTTP publico para ALB de Chiper"  --vpc-id <VPC_ID>
```

Salida esperada:

```json
{
	"GroupId": "sg-0abc123def456"
}
```

Agregue regla de entrada HTTP (80):

```bash
aws ec2 authorize-security-group-ingress  --group-id <SG_ALB_ID>  --protocol tcp  --port 80  --cidr 0.0.0.0/0
```

### 4. Ajustar Security Group de las instancias de app

Las instancias no deberian recibir trafico publico directo al puerto 3000 cuando se usa ALB. Lo recomendado es permitir el puerto 3000 solo desde el Security Group del ALB.

Primero identifique el Security Group de app (ejemplo: `chiper-http`):

```bash
aws ec2 describe-security-groups --filters Name=group-name,Values=chiper-http --query "SecurityGroups[*].GroupId" --output text
```

Agregue regla para permitir trafico desde el SG del ALB al puerto 3000:

```bash
aws ec2 authorize-security-group-ingress  --group-id <SG_APP_ID>  --protocol tcp  --port 3000  --source-group <SG_ALB_ID>
```

### 5. Crear Target Group

```bash
aws elbv2 create-target-group  --name chiper-tg  --protocol HTTP  --port 3000  --target-type instance  --vpc-id <VPC_ID>  --health-check-protocol HTTP  --health-check-path /health  --health-check-port traffic-port
```

Guarde el `TargetGroupArn`.

### 6. Registrar instancias EC2 en el Target Group

Obtenga IDs de las instancias de app:

```bash
aws ec2 describe-instances  --filters "Name=tag:Name,Values=chiper-app-1,chiper-app-2,chiper-app-3,chiper-app" "Name=instance-state-name,Values=running"  --query "Reservations[*].Instances[*].InstanceId"  --output text
```

Registre instancias en el Target Group:

```bash
aws elbv2 register-targets  --target-group-arn <TARGET_GROUP_ARN>  --targets Id=<INSTANCE_ID_1> Id=<INSTANCE_ID_2> Id=<INSTANCE_ID_3>
```

> En este laboratorio deben quedar 3 targets registrados y saludables.

### 7. Crear Application Load Balancer

```bash
aws elbv2 create-load-balancer  --name chiper-alb  --type application  --scheme internet-facing  --subnets <SUBNET_1> <SUBNET_2>  --security-groups <SG_ALB_ID>
```

Guarde:

- `LoadBalancerArn`
- `DNSName`

### 8. Crear Listener HTTP (80)

```bash
aws elbv2 create-listener  --load-balancer-arn <LOAD_BALANCER_ARN>  --protocol HTTP  --port 80  --default-actions Type=forward,TargetGroupArn=<TARGET_GROUP_ARN>
```

### 9. Verificar estado de targets

```bash
aws elbv2 describe-target-health --target-group-arn <TARGET_GROUP_ARN>
```

Los targets deben aparecer como `healthy`.

### 10. Probar el balanceador

Use el DNS del ALB en su navegador o con curl:

```bash
curl http://<DNS_ALB>/health
```

Para pruebas de carga (JMeter), use:

- `Server Name or IP`: `<DNS_ALB>`
- `Port`: `80`

## Resultado final

Al finalizar, tendra:

| Recurso | Nombre sugerido | Funcion |
|---|---|---|
| Security Group ALB | `chiper-alb-http` | Permite trafico HTTP publico al ALB |
| Target Group | `chiper-tg` | Agrupa instancias de app en puerto 3000 |
| Load Balancer | `chiper-alb` | Distribuye trafico HTTP hacia instancias saludables |

Con esto, su sistema deja de depender de una sola instancia expuesta publicamente y queda listo para pruebas de carga mas realistas.

## Eliminar recursos (opcional)

Para evitar costos cuando termine, elimine recursos en este orden:

1. Listener
2. Load Balancer
3. Targets registrados (opcional)
4. Target Group
5. Security Group del ALB

Ejemplo para eliminar el ALB:

```bash
aws elbv2 delete-load-balancer --load-balancer-arn <LOAD_BALANCER_ARN>
```
