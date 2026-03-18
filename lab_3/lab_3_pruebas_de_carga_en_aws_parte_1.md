# Lab 3 — Pruebas de Carga en AWS para el Monolito de Chiper Parte 1

> Este laboratorio prepara la infraestructura en AWS para ejecutar la parte 2 del **Lab 3**.
> El Lab 3 es una continuación del **Lab 2**: se mantiene el **backend monolítico de Chiper (NestJS + PostgreSQL)** y el enfoque sigue siendo **encontrar el punto de inflexión** frente a los ASRs definidos.

## Objetivos
- Preparar infraestructura en AWS para desplegar el **monolito de Chiper** y su **PostgreSQL** en máquinas separadas.
- Configurar **red** (Security Groups) y acceso **SSH**.
- Dejar listas dos instancias **EC2** (App y DB) para que el día del laboratorio solo sea necesario **iniciarlas**.
## Índice
- [1. Pre-requisitos](#1-pre-requisitos)
- [2. Arquitectura de despliegue objetivo](#2-arquitectura-de-despliegue-objetivo)
- [3. Configuración de seguridad (Security Groups)](#3-configuración-de-seguridad-security-groups)
- [4. Crear instancia EC2 para Base de Datos (PostgreSQL)](#4-crear-instancia-ec2-para-base-de-datos-postgresql)
- [5. Crear instancia EC2 para la App (Chiper Monolito)](#5-crear-instancia-ec2-para-la-app-chiper-monolito)
- [6. Checklist de cierre del pre-lab](#6-checklist-de-cierre-del-pre-lab)


## 1. Pre-requisitos

La consola de administración de AWS es una plataforma web que unifica el acceso y manejo de todos los servicios ofrecidos por AWS. Usaremos la consola para desarrollar los laboratorios que son propios del curso y el proyecto. La mayoría de los servicios de nube se cobran por demanda y se pueden detener cuando usted lo necesite. En este curso se hará uso de AWS Academy que proporciona créditos para poder acceder a los recursos de AWS. Estos créditos son limitados así que úselos de forma consciente.

### 1.1 Acceso a AWS Academy

La invitación a AWS Academy debió haber llegado a su correo Uniandes con el asunto: “Invitación al curso”. De lo contrario, revise en correo no deseado o informe al personal docente. Dentro del correo oprima el botón de “Comenzar” y siga las instrucciones para iniciar sesión como estudiante.

![](recursos/Pasted%20image%2020260310214121.png)

Cuando ingrese a la plataforma de AWS Academy podrá observar la sección “Módulos”. Bajo el módulo “Bienvenida e información general sobre el curso” entre a “Guía del estudiante del Laboratorio de aprendizaje de AWS Academy”.

![](./recursos/Pasted%20image%2020260310214319.png)

Inicie el **Learning Lab** (esto habilita los créditos del curso). Usted debe ver algo así
![](recursos/Pasted%20image%2020260310214359.png)

## 2. Arquitectura de despliegue objetivo
**Objetivo:** separar App y DB en dos máquinas distintas:

- **EC2 chiper-db**: PostgreSQL
- **EC2 chiper-app**: NestJS (monolito)
- Cliente: su computador (JMeter se usará el día del laboratorio)

![[recursos/Diagrama de componentes.png]]

> [! WARNING]
> Para este laboratorio y los siguientes se van a crear en múltiples oportunidades elementos comunes de infraestructura. Para esto usted tendrá disponibles los tutoriales de AWS, estos le presentarán dos formas de crear los recursos, con la herramienta Cloudshell o a través de la consola de AWS, usted puede escoger cualquiera de las dos formas sin embargo **es importante que sepa como usar la UI (consola de AWS) ya que sus evidencias deben ser capturas de pantalla de la misma en donde se vea la infraestructura desplegada.** Se recomienda que use ambas formas de usar AWS al menos una vez y después escoja la que más le convenga

## 3. Configuración de seguridad (Security Groups)

> Nota práctica: use nombres **sin tildes** y sin caracteres especiales.

Cree los siguientes Security Groups (VPC por defecto del lab):

- [Tutorial para crear Security Groups en AWS](security_groups.md)
### 3.1 Security Group 1 — SSH

| Parámetro    | Valor                          |
| ------------ | ------------------------------ |
| Nombre       | `chiper-ssh`                   |
| Descripción  | Acceso SSH a instancias        |
| Inbound rule | SSH (22) desde `Anywhere-IPv4` |
### 3.2 Security Group 2 — PostgreSQL

| Parámetro    | Valor                          |
| ------------ | ------------------------------ |
| Nombre       | `chiper-db`                    |
| Descripción  | Acceso a PostgreSQL            |
| Inbound rule | TCP 5432 desde `Anywhere-IPv4` |

> En un entorno real, 5432 **no** se abre a todo internet. Para el laboratorio lo haremos así por simplicidad.

### 3.3 Security Group 3 — HTTP API (Chiper)

| Parámetro    | Valor                          |
| ------------ | ------------------------------ |
| Nombre       | `chiper-http`                  |
| Descripción  | Acceso HTTP al monolito (API)  |
| Inbound rule | TCP 3000 desde `Anywhere-IPv4` |

> Si su backend corre en otro puerto, ajuste esta regla para que coincida con su configuración.

Usted debe ver algo así
![](recursos/Pasted%20image%2020260310223827.png)
## 4. Crear instancia EC2 para Base de Datos (PostgreSQL)

- [Tutorial para crear instancias de EC2 en AWS](ec2_instances.md)

Cree una instancia EC2 con los parámetros:

| Parámetro         | Valor                      |
| ----------------- | -------------------------- |
| Nombre            | `chiper-db`                |
| AMI               | Ubuntu Server 24.04 LTS    |
| Tipo de instancia | `t2.nano`                  |
| IP pública        | Habilitar                  |
| Security Groups   | `chiper-ssh` + `chiper-db` |
| Almacenamiento    | 8 GB                       |

### 4.1 Conexión por SSH
Conéctese a la instancia:
```bash
ssh -i <archivo>.pem ubuntu@<IP_PUBLICA_DB>
```
### 4.2 Ejecutar la base de datos (chiper-db)
1. Conéctese por SSH a `chiper-db`.
2. Verifique que Docker está instalado y corriendo ([Tutorial para instalar docker](instalar_docker_en_una_maquina_EC2.md)):
``` bash
sudo docker --version
sudo service docker status
```
3. Levante PostgreSQL con Docker (si no existe el contenedor, créelo; si existe, inícielo):
``` bash
# Opción A: crear y levantar (primera vez)
sudo docker run --name chiper-db \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=chiper \
  -p 5432:5432 \
  -d postgres

# Opción B: si ya existe, solo iniciar
sudo docker start chiper-db
```
4. Verifique que está arriba:
``` bash
sudo docker ps
```

![](./recursos/Pasted%20image%2020260311000750.png)
## 5. Crear instancia EC2 para la App (Chiper Monolito)
Cree una instancia EC2 con los parámetros:

| Parámetro         | Valor                        |
| ----------------- | ---------------------------- |
| Nombre            | `chiper-app`                 |
| AMI               | Ubuntu Server 24.04 LTS      |
| Tipo de instancia | `t2.nano`                    |
| IP pública        | Habilitar                    |
| Security Groups   | `chiper-ssh` + `chiper-http` |
| Almacenamiento    | 8 GB                         |
### 5.1 Conexión por SSH
```bash
ssh -i <archivo>.pem ubuntu@<IP_PUBLICA_APP>
```

	### 5.2 Instalación de Node.js (LTS), npm y Git

```bash
# Dependencias básicas
sudo apt update
sudo apt install -y git curl

# Instalar NVM
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash

# Cargar NVM en la sesión actual
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# Instalar Node LTS
nvm install --lts

# Usar la versión LTS por defecto
nvm alias default 'lts/*'
nvm use default

# Verificar instalación
node -v
npm -v
```

### 5.3 Clonar el repositorio del backend
Clone el repositorio del backend de su proyecto (reemplace la URL):
```bash
git clone <URL_REPO_BACKEND_CHIPER>
cd <CARPETA_REPO>
```

Instale dependencias:
```bash
npm install
```

### 5.4 Configuración de conexión a la base de datos

Configure variables de entorno o archivo `.env` (según cómo esté el proyecto). La idea es que **HOST** apunte a la **IP privada** de `chiper-db` (misma VPC).

Ejemplo de variables típicas:

```bash
DB_HOST=<IP_PRIVADA_DB>
DB_PORT=5432
DB_USER=chiper_user
DB_PASSWORD=chiper_pwd
DB_NAME=chiper_db
PORT=3000
```

### 5.5 Migraciones / seed de datos (si aplica)

Ejecute los comandos que su proyecto defina para crear tablas y datos.

Ejemplos (ajuste a su repo):

```bash
# Ejemplo A: migraciones TypeORM
npm run migration:run
```

> El Lab 3 asume que el backend ya tiene datos suficientes para ejecutar las pruebas del Lab 2 (consulta con JOINs y escritura de entidad grande).

### 5.6 Verificación rápida desde el navegador

En su computador:
- `http://<IP_PUBLICA_APP>:3000/health`

# [Parte 2](./lab_3_pruebas_de_carga_en_aws_parte_2.md)

