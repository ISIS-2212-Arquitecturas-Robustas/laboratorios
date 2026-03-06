# Lab 3 — (Pre) Pruebas de Carga en AWS para el Monolito de Chiper

> Este pre-laboratorio prepara la infraestructura en AWS para ejecutar el **Lab 3**.
> El Lab 3 es una continuación del **Lab 2**: se mantiene el **backend monolítico de Chiper (NestJS + PostgreSQL)** y el enfoque sigue siendo **encontrar el punto de inflexión** frente a los ASRs definidos.
>
> **IMPORTANTE:** En este documento se dejan *placeholders* para imágenes/capturas.


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

### 1.1 Acceso a AWS Academy

1. Ingrese a AWS Academy con su cuenta institucional.
2. Inicie el **Learning Lab** (esto habilita los créditos del curso).

TODO
- `[Imagen 1: AWS Academy / Learning Lab iniciado]`

### 1.2 Herramientas locales

- Un cliente SSH (Terminal en Mac/Linux o PowerShell/WSL en Windows).
- Llave `.pem` descargada desde AWS al crear la instancia.

> Si es su primera vez usando llaves SSH, tenga presente que el archivo `.pem` debe tener permisos restringidos:
> - `chmod 400 <archivo>.pem`


## 2. Arquitectura de despliegue objetivo

**Objetivo:** separar App y DB en dos máquinas distintas:

- **EC2 chiper-db**: PostgreSQL
- **EC2 chiper-app**: NestJS (monolito)
- Cliente: su computador (JMeter se usará el día del laboratorio)

TODO
- `[Imagen 2: Diagrama de despliegue (cliente -> chiper-app -> chiper-db)]`


## 3. Configuración de seguridad (Security Groups)

> Nota práctica: use nombres **sin tildes** y sin caracteres especiales.

Cree los siguientes Security Groups en EC2 (VPC por defecto del lab):

### 3.1 Security Group 1 — SSH

| Parámetro | Valor |
|---|---|
| Nombre | `chiper-ssh` |
| Descripción | Acceso SSH a instancias |
| Inbound rule | SSH (22) desde `Anywhere-IPv4` |

TODO
- `[Imagen 3: Security Group chiper-ssh creado con regla 22]`

### 3.2 Security Group 2 — PostgreSQL

| Parámetro | Valor |
|---|---|
| Nombre | `chiper-db` |
| Descripción | Acceso a PostgreSQL |
| Inbound rule | TCP 5432 desde `Anywhere-IPv4` |

> En un entorno real, 5432 **no** se abre a todo internet. Para el laboratorio lo haremos así por simplicidad.

TODO
- `[Imagen 4: Security Group chiper-db creado con regla 5432]`

### 3.3 Security Group 3 — HTTP API (Chiper)

| Parámetro | Valor |
|---|---|
| Nombre | `chiper-http` |
| Descripción | Acceso HTTP al monolito (API) |
| Inbound rule | TCP 3000 desde `Anywhere-IPv4` |

> Si su backend corre en otro puerto, ajuste esta regla para que coincida con su configuración.

TODO
- `[Imagen 5: Security Group chiper-http creado con regla 3000]`


## 4. Crear instancia EC2 para Base de Datos (PostgreSQL)

Cree una instancia EC2 con los parámetros:

| Parámetro | Valor |
|---|---|
| Nombre | `chiper-db` |
| AMI | Ubuntu Server 24.04 LTS |
| Tipo de instancia | `t2.nano` |
| IP pública | Habilitar |
| Security Groups | `chiper-ssh` + `chiper-db` |
| Almacenamiento | 8 GB |

TODO
- `[Imagen 6: Instancia EC2 chiper-db creada (resumen)]`

### 4.1 Conexión por SSH

Conéctese a la instancia:
```bash
ssh -i <archivo>.pem ubuntu@<IP_PUBLICA_DB>
```

TODO
- `[Imagen 7: Conexión SSH exitosa a chiper-db]`

### 4.2 Ejecutar la base de datos (chiper-db)

> En este laboratorio la base de datos corre en **Docker** dentro de la instancia `chiper-db`.

1. Conéctese por SSH a `chiper-db`.
2. Verifique que Docker está instalado y corriendo:
``` bash
docker --version
sudo service docker status
```

3. Levante PostgreSQL con Docker (si no existe el contenedor, créelo; si existe, inícielo):
``` bash
# Opción A: crear y levantar (primera vez)
docker run --name chiper-db \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=chiper \
  -p 5432:5432 \
  -d postgres

# Opción B: si ya existe, solo iniciar
docker start chiper-db
```

4. Verifique que está arriba:
``` bash
docker ps
```

TODO
- `[Imagen X: docker ps mostrando chiper-db (postgres) activo]`
### 4.3 Ejecutar el monolito (chiper-app)
1. Conéctese por SSH.
2. Entre al repo.
3. Verifique variables de entorno/archivo `.env`:

- `DB_HOST` debe apuntar a la **IP privada** de `chiper-db`
- `PORT=3000` (o el puerto que use el backend)

4. Levante la app: 

``` bash
npm install
npm run start:dev
```

> Si su repo está listo para producción, puede usar `npm run start`.

TODO
- `[Imagen 4: logs del backend levantado en 0.0.0.0:3000]`
### 4.4 Verificación rápida desde el navegador

En su computador:
- `http://<IP_PUBLICA_APP>:3000/health`

**Placeholder imagen**
TODO
- `[Imagen 5: /health OK]`
## 5. Crear instancia EC2 para la App (Chiper Monolito)

Cree una instancia EC2 con los parámetros:

| Parámetro | Valor |
|---|---|
| Nombre | `chiper-app` |
| AMI | Ubuntu Server 24.04 LTS |
| Tipo de instancia | `t2.nano` |
| IP pública | Habilitar |
| Security Groups | `chiper-ssh` + `chiper-http` |
| Almacenamiento | 8 GB |

TODO
- `[Imagen 9: Instancia EC2 chiper-app creada (resumen)]`

### 5.1 Conexión por SSH

```bash
ssh -i <archivo>.pem ubuntu@<IP_PUBLICA_APP>
```

TODO
- `[Imagen 10: Conexión SSH exitosa a chiper-app]`

### 5.2 Instalación de Node.js (LTS), npm y Git

```bash
sudo apt update
sudo apt install -y git curl

# Node.js LTS (vía NodeSource)
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs

node -v
npm -v
```

TODO
- `[Imagen 11: node -v y npm -v en chiper-app]`

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

> Si su proyecto usa TypeORM con `ormconfig` o `TypeOrmModule.forRoot`, ajuste donde corresponda.

TODO
- `[Imagen 12: Configuración DB_HOST apuntando a IP privada de chiper-db]`

### 5.5 Migraciones / seed de datos (si aplica)

Ejecute los comandos que su proyecto defina para crear tablas y datos.

Ejemplos (ajuste a su repo):

```bash
# Ejemplo A: migraciones TypeORM
npm run migration:run

# Ejemplo B: sync automático (si lo tienen habilitado)
# (no recomendado en prod, aceptable para laboratorio)
```

> El Lab 3 asume que el backend ya tiene datos suficientes para ejecutar las pruebas del Lab 2 (consulta con JOINs y escritura de entidad grande).

## 6. Checklist de cierre del pre-lab

Antes de terminar:

- [ ] Confirmé que `chiper-app` se conecta a `chiper-db` usando **IP privada**.
- [ ] Confirmé que el endpoint `/health` responde por IP pública.
- [ ] Dejé anotadas:
  - IP pública de `chiper-app`
  - IP privada de `chiper-db`
  - Usuario/DB/password
- [ ] **DETENER** (no eliminar) las instancias para conservar créditos.

**Acción final (obligatoria):**
- Detenga `chiper-db` y `chiper-app` desde la consola EC2.

TODO
- `[Imagen 15: Instancias detenidas (stopped)]`


## Notas para el día del laboratorio
- El Lab 3 usará esta infraestructura para correr pruebas de carga (JMeter) y encontrar el punto de inflexión de los endpoints del Lab 2.
- Si cambia el puerto o rutas del backend, actualice el Security Group `chiper-http` y los targets del plan de pruebas en JMeter.

