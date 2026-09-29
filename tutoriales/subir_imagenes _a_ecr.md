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

En cloudshell debe clonar el repositorio de Cheapest-api. La implementación basada en microservicios se encuentra en la rama `microservicios`.

AWS documenta que el cliente Docker debe autenticarse con ECR usando un token temporal generado con AWS CLI. Ese token tiene validez limitada (revise la [Documentación AWS](https://docs.aws.amazon.com/AmazonECR/latest/userguide/docker-push-ecr-image.html?utm_source=chatgpt.com "push a Docker image to an Amazon ECR repository") para más detalles).

## 4. Escenario del laboratorio

En esta guía se explicarán los pasos con la imagen del servicio llamado `inventario-service` en el repositorio `cheapest-inventario` con el tag `0.0.1`. 
Luego, debe extrapolar los pasos a los otros servicios que se usan en el laboratorio.
Para `inventario-service`, se asumirán los siguientes valores de configuración:

```bash
REGION=us-east-1
ACCOUNT_ID=123456789012
REPO_NAME=cheapest-inventario 
IMAGE_TAG=0.0.1
```

Recuerde cambiar el valor de ACCOUNT_ID por sus valores reales.

## 5. Paso 1: crear el repositorio en Amazon ECR

Primero se crea un repositorio privado en ECR. AWS permite hacerlo desde consola o por CLI.

```bash
aws ecr create-repository --repository-name cheapest-inventario --region us-east-1
```

Este comando crea un repositorio privado llamado `cheapest-inventario` dentro de ECR en la región indicada. Ese repositorio será el destino donde se almacenará la imagen Docker.

Usted verá el URI del repositorio, este se ve de la siguiente forma `123456789012.dkr.ecr.us-east-1.amazonaws.com`

Donde:

- `123456789012` es el account id
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

En la consola de AWS, entre al repositorio en Amazon ECR: la sección **Images** lista la imagen con el tag que acaba de subir (por ejemplo `0.0.1`), su tamaño y su *digest*.

![Imágenes de un repositorio en la consola de ECR](./recursos/ecr_image.png)

## 11. Usar la imagen en ECS

A partir de este momento usted podrá seguir el [tutorial para levantar instancias ECS](./crear_instancia_ecs.md)

Cuando vaya a crear una task definition de ECS, en el campo `image` del contenedor debe poner la URI exacta de la imagen publicada:

```text
123456789012.dkr.ecr.us-east-1.amazonaws.com/cheapest-inventario:0.0.1
```

AWS establece que la task definition especifica la imagen que ECS debe ejecutar.

## 12. Permisos necesarios en ECS

Antes de crear las tareas en ECS conviene entender un concepto que AWS usa en todos sus servicios: los **permisos**. En este laboratorio no tiene que configurar nada, pero cuando algo falla por permisos el error puede ser confuso si no sabe cómo funcionan.

### ¿Por qué AWS necesita permisos?

En AWS, ningún servicio puede hacer nada sobre otro servicio a menos que alguien le haya dado permiso explícito. Por defecto todo está prohibido. Por ejemplo, el hecho de que ECS y ECR estén en su misma cuenta no significa que ECS pueda leer las imágenes de ECR: hay que autorizarlo. Esto protege su cuenta: si un componente se compromete, solo puede hacer lo que se le permitió.

El servicio de AWS que administra estos permisos se llama **IAM** (*Identity and Access Management*, "gestión de identidades y accesos"). Usted ya lo ha usado sin saberlo: cuando corre comandos con la AWS CLI, sus credenciales son una identidad de IAM y lo que puede hacer depende de los permisos que esa identidad tenga.

### Política y rol

- **Política (*policy*):** una lista de acciones permitidas, por ejemplo "descargar imágenes de ECR" o "escribir logs". Es solo la lista; por sí sola no le da permisos a nadie.
- **Rol (*role*):** una identidad a la que se le pueden adjuntar políticas. Los permisos de un rol son los de todas las políticas que tenga adjuntas. Un servicio de AWS (como ECS) puede "asumir" un rol, es decir, actuar con los permisos de ese rol.

Una analogía: la política es la lista de puertas que se pueden abrir, y el rol es la credencial que se le entrega a alguien para que abra esas puertas.

### ¿Qué permisos necesita una tarea de ECS?

Cuando ECS lanza una tarea, antes de que su contenedor arranque debe hacer dos cosas por su cuenta:

1. **Descargar (*pull*) la imagen** del repositorio de ECR donde usted la subió.
2. **Enviar los logs** del contenedor a CloudWatch, para que usted pueda verlos.

Ninguna de las dos las hace su contenedor ni su usuario: las hace ECS, y para eso necesita permisos. El rol que se le da a ECS para esto se llama **task execution role** (rol de ejecución de la tarea). Una política de AWS ya viene hecha con justo esos permisos: `AmazonECSTaskExecutionRolePolicy`.

### ¿Qué rol usa este laboratorio?

En su cuenta del laboratorio ya existe un rol llamado **`LabRole`** que tiene los permisos necesarios (entre ellos los de esa política). **Todos deben usar `LabRole`**: no hay que crear ningún rol ni adjuntar ninguna política.

Solo debe indicarle a ECS que use ese rol. Eso se hace en el archivo `task-definition.json` (paso 2 del [tutorial para levantar instancias ECS](./crear_instancia_ecs.md)), en el campo `executionRoleArn`, que lleva la dirección (ARN) del rol:

```json
"executionRoleArn": "arn:aws:iam::<ACCOUNT_ID>:role/LabRole"
```

`<ACCOUNT_ID>` es el número de 12 dígitos de su cuenta. Si no lo recuerda, obtenga el ARN completo del rol con:

```bash
aws iam get-role --role-name LabRole --query "Role.Arn" --output text
```

### ¿Cómo me doy cuenta de que falta el rol o los permisos?

Si `executionRoleArn` no está, o el rol no puede descargar la imagen, la tarea no llega a `RUNNING`: se queda en `PENDING` o pasa a `STOPPED`. Para ver la causa, describa la tarea (paso 8 del tutorial de ECS) y mire el campo `stoppedReason`. Un mensaje del tipo `CannotPullContainerError` o `pull access denied` indica que ECS no pudo descargar la imagen, y lo primero que debe revisar es que la task definition tenga el `executionRoleArn` con `LabRole`.
