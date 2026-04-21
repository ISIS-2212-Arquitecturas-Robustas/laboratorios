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
Nombre del clúster: chiper-cluster
Familia de la tarea: inventario-task
Nombre del servicio: inventario-service
Nombre del contenedor: inventario-container
Imagen: 123456789012.dkr.ecr.us-east-1.amazonaws.com/inventario_service:v1
Puerto del contenedor: 3000
Subnet: subnet-xxxxxxxx
Security Group: sg-xxxxxxxx
```

Recuerde reemplazar esos valores por los de su cuenta.

## 7. Paso 1: crear el clúster

Ahora cree el clúster de ECS:

```bash
aws ecs create-cluster --cluster-name chiper-cluster --region us-east-1
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
        { "name": "DB_HOST", "value": "chiper-rds.xxxxx.us-east-1.rds.amazonaws.com" },
        { "name": "DB_PORT", "value": "5432" },
        { "name": "DB_NAME", "value": "chiper" },
        { "name": "DB_USER", "value": "postgres" },
        { "name": "DB_PASSWORD", "value": "postgres" }
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
- usará el rol `ecsTaskExecutionRole` para descargar la imagen

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
aws ecs create-service  --cluster chiper-cluster  --service-name inventario-service  --task-definition inventario-task  --desired-count 1  --launch-type FARGATE  --network-configuration "awsvpcConfiguration={subnets=[subnet-xxxxxxxx],securityGroups=[sg-xxxxxxxx],assignPublicIp=ENABLED}"  --region us-east-1
```

### Explicación

Este comando crea un servicio que:

- usa el clúster `chiper-cluster`
- ejecuta la task definition `inventario-task`
- mantiene **1 tarea activa**
- usa **Fargate**
- usa la subnet y el security group indicados
- asigna IP pública a la tarea

AWS documenta que las tareas Fargate usan red `awsvpc`, por lo que requieren configuración de red al crear el servicio.

## 11. Paso 5: listar los servicios del clúster

Para verificar que el servicio fue creado, ejecute:

```bash
aws ecs list-services --cluster chiper-cluster --region us-east-1
```

Este comando muestra los servicios registrados en el clúster. Si todo salió bien, verá el ARN del servicio recién creado.

## 12. Paso 6: describir el servicio

Para ver el estado detallado del servicio, ejecute:

```bash
aws ecs describe-services --cluster chiper-cluster --services inventario-service --region us-east-1
```

Este comando permite revisar el estado del servicio, la cantidad deseada de tareas y la cantidad que realmente está corriendo. Le sirve para confirmar que ECS ya intentó lanzar el contenedor.

## 13. Paso 7: listar las tareas del servicio

Para ver las tareas creadas por el servicio, ejecute:

```bash
aws ecs list-tasks --cluster chiper-cluster --service-name inventario-service --region us-east-1
```


Este comando muestra las tareas asociadas al servicio. Si la tarea arrancó correctamente, luego podrá inspeccionarla en detalle.

## 14. Paso 8: describir la tarea en ejecución

Copie el ARN de la tarea devuelto en el paso anterior y úselo aquí:

```bash
aws ecs describe-tasks --cluster chiper-cluster --tasks <task-arn> --region us-east-1
```

Este comando le permite revisar si la tarea está en estado `RUNNING`, si falló al iniciar, o si fue detenida por algún problema de red, permisos o arranque del contenedor.

## 15. Cómo obtener la IP pública de la tarea

Una forma sencilla de verificar el despliegue es consultar la interfaz de red asociada a la tarea.

Primero describa la tarea y ubique el `networkInterfaceId`. Luego consulte esa interfaz con:

```bash
aws ec2 describe-network-interfaces --network-interface-ids eni-xxxxxxxx --region us-east-1
```

Si la tarea recibió IP pública, aquí podrá verla. Eso le permitirá probar el contenedor directamente si su aplicación expone un endpoint HTTP y el security group permite acceso al puerto correspondiente.

## 19. Limpiar el servicio ECS creado

Si desea eliminar el servicio, ejecute primero:

```bash
aws ecs update-service --cluster chiper-cluster --service inventario-service --desired-count 0 --region us-east-1
```

Luego:

```bash
aws ecs delete-service --cluster chiper-cluster --service inventario-service --force --region us-east-1
```

Si desea desregistrar la task definition, puede hacerlo con la revisión específica, por ejemplo:

```bash
aws ecs deregister-task-definition --task-definition inventario-task:1 --region us-east-1
```

Y si desea eliminar el clúster:

```bash
aws ecs delete-cluster --cluster chiper-cluster --region us-east-1
```
