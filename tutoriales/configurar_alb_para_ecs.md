# Configurar un Application Load Balancer (ALB) para servicios de ECS

## Objetivos

- Crear un ALB que reciba el tráfico de los microservicios de Cheapest y lo reparta entre las tareas de cada servicio.
- Tener una **dirección estable** (el DNS del ALB) para llegar a cada servicio, en lugar de depender de la IP de una tarea, que cambia cada vez que la tarea se reinicia.
- Registrar los servicios de ECS en el ALB para que las tareas nuevas reciban tráfico automáticamente cuando se escala.

## Marco conceptual

### Application Load Balancer (ALB)

Un ALB recibe peticiones HTTP y las reenvía a un conjunto de destinos. Tiene tres piezas:

- **Listener:** escucha en un puerto (por ejemplo, 3001) y decide qué hacer con las peticiones que llegan.
- **Target group:** el conjunto de destinos (en este caso, las tareas de un servicio de ECS). Tiene un *health check* con el que el ALB comprueba qué tareas están sanas y solo envía tráfico a esas.
- **Regla del listener:** en este laboratorio, cada listener reenvía todo su tráfico a un target group.

### Por qué se usa con ECS

Cada tarea de Fargate recibe una IP nueva cada vez que se reinicia. Si API Gateway o los otros servicios apuntaran a la IP de una tarea, dejarían de funcionar cuando esta cambie. El ALB tiene un DNS fijo, y ECS registra y retira las IP de las tareas en el target group automáticamente. Además, cuando un servicio tiene varias tareas, el ALB reparte las peticiones entre ellas: por eso el escalamiento horizontal (más tareas) sí aumenta la capacidad del servicio.

### Diseño del laboratorio

Se crea **un solo ALB** con **tres listeners**, uno por servicio, cada uno en el mismo puerto en que corre el servicio:

| Servicio | Puerto del listener | Target group | Puerto del contenedor |
| --- | --- | --- | --- |
| Logística | 3001 | `tg-Cheapest-logistica` | 3001 |
| Inventario | 3002 | `tg-Cheapest-inventario` | 3002 |
| Ventas | 3003 | `tg-Cheapest-ventas` | 3003 |

Así, la dirección de cada servicio es `http://<ALB_DNS>:<PUERTO>`, la misma forma que antes tenía con la IP de la tarea.

## Prerrequisitos

- El clúster de ECS y el Security Group de las tareas (`SG_ECS_ID`), que se usan en el [tutorial de ECS](./crear_instancia_ecs.md).
- La VPC y **dos subredes en zonas de disponibilidad distintas** (un ALB lo exige). Son las mismas que identificó en el [tutorial de RDS](./crear_instancia_rds.md) (paso 1). Deben ser subredes públicas: en la VPC por defecto lo son.

## Tutorial CloudShell (AWS CLI)

### 1. Crear el Security Group del ALB

```bash
aws ec2 create-security-group --group-name Cheapest-alb-sg --description "ALB de Cheapest" --vpc-id <VPC_ID>
```

Guarde el `GroupId` devuelto (`SG_ALB_ID`). Permita el tráfico entrante en los puertos de los tres listeners:

```bash
aws ec2 authorize-security-group-ingress --group-id <SG_ALB_ID> --protocol tcp --port 3001-3003 --cidr 0.0.0.0/0
```

### 2. Permitir que el ALB llegue a las tareas

En el Security Group de las tareas (`SG_ECS_ID`), permita el tráfico entrante en los puertos de los servicios **solo desde el ALB**:

```bash
aws ec2 authorize-security-group-ingress --group-id <SG_ECS_ID> --protocol tcp --port 3001-3003 --source-group <SG_ALB_ID>
```

Así, las tareas ya no necesitan estar abiertas a todo internet: reciben tráfico únicamente a través del ALB.

### 3. Crear el ALB

```bash
aws elbv2 create-load-balancer --name Cheapest-alb --type application --scheme internet-facing --subnets <SUBNET_A> <SUBNET_B> --security-groups <SG_ALB_ID> --query "LoadBalancers[0].[LoadBalancerArn,DNSName]" --output text
```

Guarde el ARN (`ALB_ARN`) y el DNS (`ALB_DNS`, algo como `Cheapest-alb-123456789.us-east-1.elb.amazonaws.com`). Espere a que esté disponible (puede tardar unos minutos):

```bash
aws elbv2 wait load-balancer-available --load-balancer-arns <ALB_ARN>
```

### 4. Crear un target group por servicio

Las tareas de Fargate se registran por IP, por lo que el tipo de destino debe ser `ip`. El health check consulta `/health`, el endpoint de salud de cada microservicio. Repita el comando para cada servicio con su nombre y su puerto:

```bash
aws elbv2 create-target-group --name tg-Cheapest-logistica --protocol HTTP --port 3001 --vpc-id <VPC_ID> --target-type ip --health-check-path /health --query "TargetGroups[0].TargetGroupArn" --output text
```

Guarde el ARN de cada uno (`TG_LOGISTICA_ARN`, `TG_INVENTARIO_ARN`, `TG_VENTAS_ARN`) usando los nombres y puertos de la tabla del diseño.

### 5. Crear un listener por servicio

Cada listener recibe en el puerto del servicio y reenvía a su target group. Repita el comando para los tres:

```bash
aws elbv2 create-listener --load-balancer-arn <ALB_ARN> --protocol HTTP --port 3001 --default-actions Type=forward,TargetGroupArn=<TG_LOGISTICA_ARN>
```

### 6. Registrar el servicio de ECS en el ALB

Los servicios de ECS se registran en el target group **al crearlos**, con el parámetro `--load-balancers`. Ejemplo para Logística:

```bash
aws ecs create-service --cluster Cheapest-cluster --service-name svc-Cheapest-logistica --task-definition td-Cheapest-logistica --desired-count 1 --launch-type FARGATE --network-configuration "awsvpcConfiguration={subnets=[<SUBNET_A>],securityGroups=[<SG_ECS_ID>],assignPublicIp=ENABLED}" --load-balancers targetGroupArn=<TG_LOGISTICA_ARN>,containerName=<NOMBRE_CONTENEDOR>,containerPort=3001 --health-check-grace-period-seconds 60
```

- `containerName` debe ser el `name` del contenedor definido en el `task-definition.json`, y `containerPort` el puerto del contenedor.
- `--health-check-grace-period-seconds` le da un margen al contenedor para arrancar antes de que el ALB lo declare no sano.

A partir de ahí, ECS registra en el target group la IP de cada tarea que arranca y la retira cuando la tarea se detiene.

### 7. Verificar

Consulte el estado de las tareas en el target group (puede tardar uno o dos minutos en pasar a `healthy`):

```bash
aws elbv2 describe-target-health --target-group-arn <TG_LOGISTICA_ARN> --query "TargetHealthDescriptions[].{Ip:Target.Id,Estado:TargetHealth.State}" --output table
```

Cuando el estado sea `healthy`, pruebe el servicio a través del ALB:

```bash
curl http://<ALB_DNS>:3001/health
```

Estados posibles: `initial` (registrándose), `healthy` (recibe tráfico), `unhealthy` (falla el health check: revise el Security Group de las tareas y que el contenedor responda en `/health`) y `draining` (se está retirando).

## Resultado final

Al finalizar debe tener:

| Recurso | Nombre sugerido | Estado esperado |
| --- | --- | --- |
| Security Group del ALB | `Cheapest-alb-sg` | 3001-3003 habilitados |
| ALB | `Cheapest-alb` | `active` |
| Target groups | `tg-Cheapest-logistica`, `tg-Cheapest-inventario`, `tg-Cheapest-ventas` | Con las tareas en `healthy` |
| Listeners | 3001, 3002, 3003 | Reenviando a su target group |

## Limpiar recursos (opcional)

Elimine primero los servicios de ECS y luego, en este orden:

```bash
aws elbv2 delete-load-balancer --load-balancer-arn <ALB_ARN>
aws elbv2 delete-target-group --target-group-arn <TG_ARN>
aws ec2 delete-security-group --group-id <SG_ALB_ID>
```

Repita `delete-target-group` para cada target group. Si el Security Group aún está en uso, espere un par de minutos a que termine de eliminarse el ALB.
