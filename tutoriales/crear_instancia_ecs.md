# Crear un servicio en Amazon ECS

## 1. Objetivo

Aprender a crear un servicio en Amazon ECS, a partir de una imagen previamente publicada en Amazon ECR. Al finalizar, usted tendrá un clúster, una task definition y un servicio ejecutándose en ECS con AWS Fargate.

## 2. Imágenes en ECR

En el tutorial anterior usted publicó una imagen Docker en Amazon ECR. En este laboratorio se parte de ese resultado para desplegar dicha imagen en Amazon ECS.

En este flujo:
- **ECR** almacena la imagen
- **ECS** ejecuta la imagen

AWS define una **task definition** como la especificación que describe cómo debe ejecutarse su contenedor, incluyendo imagen, CPU, memoria y red.

## 3. Marco conceptual

### ¿Qué es un clúster en ECS?

Un clúster de Amazon ECS es una agrupación lógica donde se ejecutan tareas y servicios. Aunque use Fargate, sigue necesitando un clúster para organizar la ejecución de sus contenedores. :contentReference[oaicite:2]{index=2}

### ¿Qué es una task definition?

Una task definition describe cómo debe correr su aplicación: imagen, CPU, memoria, puertos, compatibilidad con Fargate y modo de red. Para Fargate, AWS exige `requiresCompatibilities=FARGATE` y `networkMode=awsvpc`. 

### ¿Qué es un servicio en ECS?
Un servicio mantiene ejecutándose el número deseado de tareas. Si una tarea falla o se detiene, ECS lanza otra automáticamente. Esto lo hace apropiado para microservicios o APIs que deben quedar activos.

## 4. Prerrequisitos

Se asume que usted ya completó el tutorial anterior y que ya dispone de:
- una imagen publicada en Amazon ECR
- AWS CLI instalado y configurado
- permisos para usar ECS, IAM, EC2 networking y ECR
- una VPC existente
- al menos una subnet
- un security group

También se asumirá que ya existe una imagen como esta:

```text
123456789012.dkr.ecr.us-east-1.amazonaws.com/inventario_service:v1
````

## 5. Escenario del laboratorio

En este ejemplo se desplegará el servicio:

```bash
inventario_service
```

Se usará la siguiente información de ejemplo:

```text
Región: us-east-1
Nombre del clúster: Cheapest-cluster
Familia de la tarea: inventario-task
Nombre del servicio: inventario-service
Nombre del contenedor: inventario-container
Imagen: 123456789012.dkr.ecr.us-east-1.amazonaws.com/inventario_service:v1
Puerto del contenedor: 3000
Subnet: subnet-xxxxxxxx
Security Group: sg-xxxxxxxx
```

Recuerde reemplazar esos valores por los de su cuenta.

## 6.1 Paso 0: configurar el security group para los puertos de la aplicación

> [!IMPORTANT]
> En este laboratorio los servicios van detrás de un **Application Load Balancer** (ver el [tutorial del ALB](./configurar_alb_para_ecs.md)), que es quien recibe el tráfico de API Gateway y de los otros servicios. Si el security group de las tareas no permite tráfico entrante desde el ALB en el puerto del contenedor, la tarea queda `RUNNING` en ECS pero el ALB la marca `unhealthy` y no le envía tráfico, por lo que los healthchecks de API Gateway también fallan aunque la integración esté bien configurada.

Antes de crear el servicio, verifique o cree el security group que usarán las tareas y agregue una regla de entrada por cada puerto de contenedor (3001, 3002, 3003) **con origen el security group del ALB** (paso 2 del tutorial del ALB).

## 7. Paso 1: crear el clúster

Ahora cree el clúster de ECS:

```bash
aws ecs create-cluster --cluster-name Cheapest-cluster --region us-east-1
```

Este comando crea el clúster lógico donde se ejecutará el servicio.

## 8. Paso 2: crear el archivo de task definition

Cree un archivo llamado `task-definition.json` con el siguiente contenido:

```json
{
  "family": "inventario-task",
  "requiresCompatibilities": ["FARGATE"],
  "networkMode": "awsvpc",
  "cpu": "512",
  "memory": "1024",
  "executionRoleArn": "arn:aws:iam::449642781982:role/LabRole",
  "containerDefinitions": [
    {
      "name": "inventario-container",
      "image": "123456789012.dkr.ecr.us-east-1.amazonaws.com/inventario_service:v1",
      "essential": true,
      "environment": [
        { "name": "PORT", "value": "3000" },
        { "name": "DB_HOST", "value": "Cheapest-rds.xxxxx.us-east-1.rds.amazonaws.com" },
        { "name": "DB_PORT", "value": "5432" },
        { "name": "DB_NAME", "value": "Cheapest" },
        { "name": "DB_USERNAME", "value": "postgres" },
        { "name": "DB_PASSWORD", "value": "postgres" },
        { "name": "DB_SYNCHRONIZE", "value": "true" }
      ],
      "portMappings": [
        {
          "containerPort": 3000,
          "protocol": "tcp"
        }
      ]
    }
  ]
}
```

### Explicación

Esta definición indica que:

- la tarea correrá en **Fargate**
- usará el modo de red **awsvpc**
- tendrá **0.5 vCPU**
- tendrá **1 GB de memoria**
- ejecutará la imagen publicada en ECR
- expondrá el puerto `3000`
- usará el rol indicado en `executionRoleArn` (`LabRole`) para descargar la imagen de ECR y enviar logs

AWS indica que, para Fargate con `awsvpc`, la task definition debe incluir compatibilidad con Fargate y el modo de red `awsvpc`

En ECS, las variables de entorno del contenedor se definen en `containerDefinitions`:

- `environment`: variables en texto plano (no sensibles).
- `secrets`: variables sensibles referenciadas desde SSM Parameter Store o Secrets Manager.

> Por simplicidad vamos a agregar la contraseña de la DB como una variable de entorno, sin embargo **en un entorno real debería ser un secret**

## 9. Paso 3: registrar la task definition

Una vez creado el archivo, registre la definición de tarea:

```bash
aws ecs register-task-definition --cli-input-json file://task-definition.json --region us-east-1
```

Este comando registra la definición en ECS para que luego pueda ser usada por un servicio. AWS documenta precisamente este flujo para Fargate usando AWS CLI.

## 10. Paso 4: crear el servicio

Ahora cree el servicio dentro del clúster:

```bash
aws ecs create-service  --cluster Cheapest-cluster  --service-name inventario-service  --task-definition inventario-task  --desired-count 1  --launch-type FARGATE  --network-configuration "awsvpcConfiguration={subnets=[subnet-xxxxxxxx],securityGroups=[sg-xxxxxxxx],assignPublicIp=ENABLED}"  --region us-east-1
```

### Explicación

Este comando crea un servicio que:

- usa el clúster `Cheapest-cluster`
- ejecuta la task definition `inventario-task`
- mantiene **1 tarea activa**
- usa **Fargate**
- usa la subnet y el security group indicados
- asigna IP pública a la tarea

AWS documenta que las tareas Fargate usan red `awsvpc`, por lo que requieren configuración de red al crear el servicio.

Si el servicio va detrás de un ALB (como en el laboratorio), agregue al comando el parámetro `--load-balancers targetGroupArn=<TG_ARN>,containerName=<NOMBRE_CONTENEDOR>,containerPort=<PUERTO>` para que ECS registre las tareas en el target group del ALB (ver el paso 6 del [tutorial del ALB](./configurar_alb_para_ecs.md#6-registrar-el-servicio-de-ecs-en-el-alb)).

## 11. Paso 5: listar los servicios del clúster

Para verificar que el servicio fue creado, ejecute:

```bash
aws ecs list-services --cluster Cheapest-cluster --region us-east-1
```

Este comando muestra los servicios registrados en el clúster. Si todo salió bien, verá el ARN del servicio recién creado.

## 12. Paso 6: describir el servicio

Para ver el estado detallado del servicio, ejecute:

```bash
aws ecs describe-services --cluster Cheapest-cluster --services inventario-service --region us-east-1
```

Este comando permite revisar el estado del servicio, la cantidad deseada de tareas y la cantidad que realmente está corriendo. Le sirve para confirmar que ECS ya intentó lanzar el contenedor.

## 13. Paso 7: listar las tareas del servicio

Para ver las tareas creadas por el servicio, ejecute:

```bash
aws ecs list-tasks --cluster Cheapest-cluster --service-name inventario-service --region us-east-1
```


Este comando muestra las tareas asociadas al servicio. Si la tarea arrancó correctamente, luego podrá inspeccionarla en detalle.

## 14. Paso 8: describir la tarea en ejecución

Copie el ARN de la tarea devuelto en el paso anterior y úselo aquí:

```bash
aws ecs describe-tasks --cluster Cheapest-cluster --tasks <task-arn> --region us-east-1
```

Este comando le permite revisar si la tarea está en estado `RUNNING`, si falló al iniciar, o si fue detenida por algún problema de red, permisos o arranque del contenedor.

## 15. Cómo obtener la IP pública de la tarea

Las tareas de Fargate no tienen una IP fija: cada vez que una tarea arranca (o se reinicia) recibe una IP pública y una IP privada nuevas. Si el servicio está detrás de un ALB no necesita estas IP para configurar API Gateway ni los otros servicios, pero le sirven para **diagnosticar** una tarea concreta. Se obtienen en dos pasos porque la IP no aparece en la descripción de la tarea, sino en su **interfaz de red**.

**Qué está pasando.** Con el modo de red `awsvpc`, cada tarea de Fargate recibe su propia interfaz de red (ENI, *Elastic Network Interface*), y es esa interfaz la que tiene las IP. Por eso:

1. `aws ecs describe-tasks` le dice **cuál es la interfaz de red** de la tarea (su `networkInterfaceId`, algo como `eni-0abc...`), además de su estado (`lastStatus`: `RUNNING`, `PENDING`, `STOPPED`).
2. `aws ec2 describe-network-interfaces` le dice **qué IP tiene esa interfaz**: la IP privada (`PrivateIpAddress`, válida dentro de la VPC) y la IP pública (`Association.PublicIp`, válida desde internet).

**Paso 1: obtener la interfaz de red de la tarea.** Use el ARN de la tarea del paso 7 (`list-tasks`):

```bash
aws ecs describe-tasks --cluster Cheapest-cluster --tasks <TASK_ARN> --region us-east-1 --query "tasks[0].attachments[0].details[?name=='networkInterfaceId'].value" --output text
```

El resultado es el identificador de la interfaz, por ejemplo `eni-0abc123def4567890`.

**Paso 2: obtener las IP de esa interfaz:**

```bash
aws ec2 describe-network-interfaces --network-interface-ids <ENI_ID> --region us-east-1 --query "NetworkInterfaces[0].{IpPublica:Association.PublicIp,IpPrivada:PrivateIpAddress}" --output table
```

Anote la IP pública (la usará en las integraciones de API Gateway y para probar con `curl http://<IP_PUBLICA>:<PUERTO>/health`) y la IP privada (la usan otros servicios dentro de la VPC). Si `IpPublica` sale vacía, la tarea no recibió IP pública: revise que el servicio se creó con `assignPublicIp=ENABLED`. Para probar la tarea directamente, el security group también debe permitir el puerto de la aplicación.

> [!NOTE]
> La IP cambia cada vez que la tarea se reinicia. Con un ALB delante, eso no afecta a API Gateway ni a los demás servicios, porque ECS actualiza el target group automáticamente.

## 19. Limpiar el servicio ECS creado

Si desea eliminar el servicio, ejecute primero:

```bash
aws ecs update-service --cluster Cheapest-cluster --service inventario-service --desired-count 0 --region us-east-1
```

Luego:

```bash
aws ecs delete-service --cluster Cheapest-cluster --service inventario-service --force --region us-east-1
```

Si desea desregistrar la task definition, puede hacerlo con la revisión específica, por ejemplo:

```bash
aws ecs deregister-task-definition --task-definition inventario-task:1 --region us-east-1
```

Y si desea eliminar el clúster:

```bash
aws ecs delete-cluster --cluster Cheapest-cluster --region us-east-1
```
