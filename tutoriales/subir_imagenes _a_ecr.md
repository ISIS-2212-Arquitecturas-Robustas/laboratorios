# Subir imágenes Docker a Amazon ECR

## 1. Objetivo

Aprender a construir una imagen Docker de un servicio, crear un repositorio en Amazon Elastic Container Registry (ECR), autenticar Docker contra AWS y subir la imagen para que luego pueda ser usada desde Amazon ECS.

## 2. Marco conceptual

### ¿Qué es Amazon ECR?

Amazon Elastic Container Registry (ECR) es el servicio de AWS para almacenar imágenes de contenedores. Funciona como un registro privado o público de imágenes Docker y OCI. AWS lo integra de forma nativa con ECS, por lo que es la opción más común cuando se despliegan contenedores en AWS. ([Documentación AWS](https://docs.aws.amazon.com/AmazonECR/latest/userguide/Repositories.html?utm_source=chatgpt.com "Amazon ECR private repositories"))

### ¿Por qué se usa junto con ECS?

ECS ejecuta contenedores, pero necesita una imagen como fuente. Esa imagen normalmente se almacena en ECR. Luego, en la definición de tarea de ECS, se referencia la URI completa de la imagen que quedó publicada en ECR. ([Documentación AWS](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_execution_IAM_role.html?utm_source=chatgpt.com "Amazon ECS task execution IAM role - AWS Documentation"))

### Flujo general

El flujo básico es:

1. crear el repositorio en ECR
2. construir la imagen Docker
3. autenticar Docker contra ECR
4. etiquetar la imagen con la URI del repositorio
5. hacer push de la imagen
6. usar esa URI en ECS ([Documentación AWS](https://docs.aws.amazon.com/AmazonECR/latest/userguide/docker-push-ecr-image.html?utm_source=chatgpt.com "push a Docker image to an Amazon ECR repository"))

## 3. Prerrequisitos

Para facilitar el tutorial vamos a seguir usando Cloudshell. Este servicio tiene integrado docker por lo que desde acá vamos a generar las imágenes.

En cloudshell debe clonar el repositorio de Cheapest-api. La implementación basada en microservicios se encuentra en la rama `microservicios`

AWS documenta que el cliente Docker debe autenticarse con ECR usando un token temporal generado con AWS CLI. Ese token tiene validez limitada. ([Documentación AWS](https://docs.aws.amazon.com/AmazonECR/latest/userguide/docker-push-ecr-image.html?utm_source=chatgpt.com "push a Docker image to an Amazon ECR repository"))

## 4. Escenario del laboratorio

En este ejemplo se subirá la imagen del servicio llamado `inventario-service` en el repositorio `cheapest-inventario` con el tag `0.0.1`

Se asumirán los siguientes valores de configuración:

```bash
REGION=us-east-1
ACCOUNT_ID=123456789012
REPO_NAME=cheapest-inventario 
IMAGE_TAG=0.0.1
```

Recuerde cambiar estos valores por sus valores reales

## 5. Paso 1: crear el repositorio en Amazon ECR

Primero se crea un repositorio privado en ECR. AWS permite hacerlo desde consola o por CLI.

```bash
aws ecr create-repository --repository-name cheapest-inventario --region us-east-1
```

Este comando crea un repositorio privado llamado `cheapest-inventario` dentro de ECR en la región indicada. Ese repositorio será el destino donde se almacenará la imagen Docker.

Usted verá el URI del repositorio, este se ve de la siguiente forma `449642781982.dkr.ecr.us-east-1.amazonaws.com`

Donde:

- `449642781982` es el account id
- `us-east-1` es la región

## 6. Paso 2: autenticar Docker contra ECR

Docker no puede hacer push a ECR sin autenticación previa. AWS recomienda usar `get-login-password` para obtener una contraseña temporal y pasarla al comando `docker login` a través de un pipe

```bash
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 123456789012.dkr.ecr.us-east-1.amazonaws.com
```

Este comando:

- le pide a AWS un token temporal de autenticación
- se lo entrega a Docker
- autentica al cliente Docker contra su registro privado de ECR

Si sale bien, Docker mostrará un mensaje parecido a:

```bash
Login Succeeded
```

## 7. Paso 3: construir la imagen Docker

> [!WARNING]
> ECS Fargate ejecuta las tareas sobre arquitectura `linux/amd64`. Si construye la imagen con `docker build` normal en una máquina con otra arquitectura (por ejemplo un Mac con chip M1/M2/M3, o un runner ARM), la imagen quedará compilada para esa arquitectura y ECS fallará al arrancar el contenedor. Para evitar esto, todas las imágenes de este tutorial se deben construir con `docker buildx build` forzando la plataforma `linux/amd64`, sin importar desde qué máquina esté construyendo.

> [!IMPORTANT]
> El `Dockerfile` de cada servicio en Cheapest-api vive en `apps/<nombre_servicio>/Dockerfile`, pero copia `package*.json` y el código fuente desde la **raíz** del repositorio (`COPY package*.json ./` y `COPY . .`). Por eso el build **no** se hace parado dentro de `apps/<servicio>`, sino desde la raíz del repositorio, apuntando al Dockerfile con `-f`.

Ubíquese en la raíz del repositorio (donde está el `package.json` principal) y ejecute:

```bash
docker buildx build --platform linux/amd64 -f apps/inventario/Dockerfile -t inventario-service:0.0.1 --load .
```

Este comando construye una imagen local para la arquitectura `linux/amd64` usando el `Dockerfile` del servicio `inventario`, y le asigna el nombre `inventario-service:0.0.1`. La bandera `--load` carga la imagen resultante en el daemon local de Docker para que quede disponible con `docker images` y pueda etiquetarla y subirla en los siguientes pasos.

Para los otros servicios, reemplace `inventario` por `logistica` o `ventas` tanto en `-f apps/<servicio>/Dockerfile` como en el nombre de la imagen.

Si quiere construir y etiquetar en un solo paso, puede hacerlo así:

```bash
docker buildx build --platform linux/amd64 -f apps/inventario/Dockerfile -t 123456789012.dkr.ecr.us-east-1.amazonaws.com/cheapest-inventario:0.0.1 --load .
```

## 8. Paso 4: etiquetar la imagen con la URI de ECR

Para subir la imagen a ECR, debe etiquetarla con la URI completa del repositorio. AWS usa el formato (URI del primer paso) para identificar la imagen:

```text
<account-id>.dkr.ecr.<region>.amazonaws.com/<repository>:<tag>
```

Ejemplo:

```bash
docker tag inventario-service:0.0.1 123456789012.dkr.ecr.us-east-1.amazonaws.com/cheapest-inventario:0.0.1
```

Aquí está creando una nueva referencia para la misma imagen local, pero ahora con el nombre exacto que ECR espera para poder recibirla.

## 9. Paso 5: subir la imagen a ECR

Una vez autenticado Docker y correctamente etiquetada la imagen, haga el push:

```bash
docker push 123456789012.dkr.ecr.us-east-1.amazonaws.com/cheapest-inventario:0.0.1
```

Este comando publica la imagen en el repositorio privado de Amazon ECR. Cuando termine, la imagen quedará disponible para ser usada por ECS u otros servicios compatibles.

AWS indica que ECR soporta imágenes Docker, imágenes OCI y otros artefactos compatibles.

## 10. Verificar que la imagen quedó publicada

Puede verificarlo desde la consola de AWS o por la terminal.

```bash
aws ecr describe-images --repository-name cheapest-inventario --region us-east-1
```

Este comando lista las imágenes que existen dentro del repositorio y permite confirmar que el push fue exitoso.

TODO Agregar como se ve en la UI

## 11. Usar la imagen en ECS

A partir de este momento usted podrá seguir el [tutorial para levantar instancias ECS](./crear_instancia_ecs)

Cuando vaya a crear una task definition de ECS, en el campo `image` del contenedor debe poner la URI exacta de la imagen publicada:

```text
123456789012.dkr.ecr.us-east-1.amazonaws.com/cheapest-inventario:0.0.1
```

AWS establece que la task definition especifica la imagen que ECS debe ejecutar.

## 12. Permisos necesarios en ECS

Si luego ECS va a descargar la imagen desde ECR, la tarea o el agente necesita permisos de ejecución. AWS documenta que el **task execution role** se usa para que ECS pueda hacer llamadas a AWS en nombre de la tarea, incluyendo el pull desde ECR.

En la práctica, suele usarse la política administrada:

```text
AmazonECSTaskExecutionRolePolicy
```

Esa política incluye los permisos básicos requeridos para descargar imágenes y enviar logs, según la documentación de AWS.