# Lab 3 — (Pre) Pruebas de Carga en AWS para el Monolito de Chiper

> Este pre-laboratorio prepara la infraestructura en AWS para ejecutar el **Lab 3**.
> El Lab 3 es una continuación del **Lab 2**: se mantiene el **backend monolítico de Chiper (NestJS + PostgreSQL)** y el enfoque sigue siendo **encontrar el punto de inflexión** frente a los ASRs definidos.
>
> **IMPORTANTE:** En este documento se dejan *placeholders* para imágenes/capturas.

---

## Objetivos

- Preparar infraestructura en AWS para desplegar el **monolito de Chiper** y su **PostgreSQL** en máquinas separadas.
- Configurar **red** (Security Groups) y acceso **SSH**.
- Dejar listas dos instancias **EC2** (App y DB) para que el día del laboratorio solo sea necesario **iniciarlas**.

---

## Índice

- [1. Pre-requisitos](#1-pre-requisitos)
- [2. Arquitectura de despliegue objetivo](#2-arquitectura-de-despliegue-objetivo)
- [3. Configuración de seguridad (Security Groups)](#3-configuración-de-seguridad-security-groups)
- [4. Crear instancia EC2 para Base de Datos (PostgreSQL)](#4-crear-instancia-ec2-para-base-de-datos-postgresql)
- [5. Crear instancia EC2 para la App (Chiper Monolito)](#5-crear-instancia-ec2-para-la-app-chiper-monolito)
- [6. Verificaciones mínimas](#6-verificaciones-mínimas)
- [7. Checklist de cierre del pre-lab](#7-checklist-de-cierre-del-pre-lab)

---

## 1. Pre-requisitos

### 1.1 Acceso a AWS Academy

1. Ingrese a AWS Academy con su cuenta institucional.
2. Inicie el **Learning Lab** (esto habilita los créditos del curso).

**Placeholder imagen**
- `[Imagen 1: AWS Academy / Learning Lab iniciado]`

### 1.2 Herramientas locales

- Un cliente SSH (Terminal en Mac/Linux o PowerShell/WSL en Windows).
- Llave `.pem` descargada desde AWS al crear la instancia.

> Si es su primera vez usando llaves SSH, tenga presente que el archivo `.pem` debe tener permisos restringidos:
> - `chmod 400 <archivo>.pem`

---

## 2. Arquitectura de despliegue objetivo

**Objetivo:** separar App y DB en dos máquinas distintas:

- **EC2 chiper-db**: PostgreSQL
- **EC2 chiper-app**: NestJS (monolito)
- Cliente: su computador (JMeter se usará el día del laboratorio)

**Placeholder imagen**
- `[Imagen 2: Diagrama de despliegue (cliente -> chiper-app -> chiper-db)]`

---

## 3. Configuración de seguridad (Security Groups)

> Nota práctica: use nombres **sin tildes** y sin caracteres especiales.

Cree los siguientes Security Groups en EC2 (VPC por defecto del lab):

### 3.1 Security Group 1 — SSH

| Parámetro | Valor |
|---|---|
| Nombre | `chiper-ssh` |
| Descripción | Acceso SSH a instancias |
| Inbound rule | SSH (22) desde `Anywhere-IPv4` |

**Placeholder imagen**
- `[Imagen 3: Security Group chiper-ssh creado con regla 22]`

### 3.2 Security Group 2 — PostgreSQL

| Parámetro | Valor |
|---|---|
| Nombre | `chiper-db` |
| Descripción | Acceso a PostgreSQL |
| Inbound rule | TCP 5432 desde `Anywhere-IPv4` |

> En un entorno real, 5432 **no** se abre a todo internet. Para el laboratorio lo haremos así por simplicidad.

**Placeholder imagen**
- `[Imagen 4: Security Group chiper-db creado con regla 5432]`

### 3.3 Security Group 3 — HTTP API (Chiper)

| Parámetro | Valor |
|---|---|
| Nombre | `chiper-http` |
| Descripción | Acceso HTTP al monolito (API) |
| Inbound rule | TCP 3000 desde `Anywhere-IPv4` |

> Si su backend corre en otro puerto, ajuste esta regla para que coincida con su configuración.

**Placeholder imagen**
- `[Imagen 5: Security Group chiper-http creado con regla 3000]`

---

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

**Placeholder imagen**
- `[Imagen 6: Instancia EC2 chiper-db creada (resumen)]`

### 4.1 Conexión por SSH

Conéctese a la instancia:

```bash
ssh -i <archivo>.pem ubuntu@<IP_PUBLICA_DB>
```

**Placeholder imagen**
- `[Imagen 7: Conexión SSH exitosa a chiper-db]`

### 4.2 Instalación y configuración de PostgreSQL

Ejecute:

```bash
sudo apt update
sudo apt install postgresql postgresql-contrib -y
```

Entre a psql y cree DB/usuario:

```bash
sudo -u postgres psql
```

En el prompt de postgres:

```sql
CREATE USER chiper_user;
CREATE DATABASE chiper_db OWNER chiper_user;
ALTER USER chiper_user WITH PASSWORD 'chiper_pwd';
\q
```

> El password es de laboratorio. Si desea, cámbielo.

### 4.3 Permitir conexiones remotas

1) Identifique la versión instalada:

```bash
ls /etc/postgresql/
```

2) Edite `pg_hba.conf`:

```bash
sudo nano /etc/postgresql/<VERSION>/main/pg_hba.conf
```

Busque la sección de IPv4 local connections y reemplace la línea:

```text
host    all             all             127.0.0.1/32            md5
```

Por:

```text
host    all             all             0.0.0.0/0               trust
```

3) Edite `postgresql.conf`:

```bash
sudo nano /etc/postgresql/<VERSION>/main/postgresql.conf
```

Asegúrese de:

- Descomentar y poner:

```text
listen_addresses = '*'
```

- Ajustar (opcional para pruebas):

```text
max_connections = 2000
```

4) Reinicie PostgreSQL:

```bash
sudo service postgresql restart
```

**Placeholder imagen**
- `[Imagen 8: Archivos pg_hba.conf y postgresql.conf configurados]`

---

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

**Placeholder imagen**
- `[Imagen 9: Instancia EC2 chiper-app creada (resumen)]`

### 5.1 Conexión por SSH

```bash
ssh -i <archivo>.pem ubuntu@<IP_PUBLICA_APP>
```

**Placeholder imagen**
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

**Placeholder imagen**
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

**Placeholder imagen**
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

---

## 6. Verificaciones mínimas

### 6.1 Verificar que la DB responde

Desde `chiper-app`, instale `psql` para probar conexión:

```bash
sudo apt install -y postgresql-client
psql -h <IP_PRIVADA_DB> -U chiper_user -d chiper_db
```

Si logra entrar, salga con:

```text
\q
```

**Placeholder imagen**
- `[Imagen 13: Conexión exitosa a PostgreSQL desde chiper-app]`

### 6.2 Levantar la aplicación y probar healthcheck

Levante la app (ajuste a su repo):

```bash
npm run start:dev
```

En su navegador, pruebe:

- `http://<IP_PUBLICA_APP>:3000/health`

**Placeholder imagen**
- `[Imagen 14: /health respondiendo OK]`

---

## 7. Checklist de cierre del pre-lab

Antes de terminar:

- [ ] Confirmé que `chiper-app` se conecta a `chiper-db` usando **IP privada**.
- [ ] Confirmé que el endpoint `/health` responde por IP pública.
- [ ] Dejé anotadas:
  - IP pública de `chiper-app`
  - IP privada de `chiper-db`
  - Usuario/DB/password
- [ ] **DETENGO** (no elimino) las instancias para conservar créditos.

**Acción final (obligatoria):**
- Detenga `chiper-db` y `chiper-app` desde la consola EC2.

**Placeholder imagen**
- `[Imagen 15: Instancias detenidas (stopped)]`

---

## Notas para el día del laboratorio

- El Lab 3 usará esta infraestructura para correr pruebas de carga (JMeter) y encontrar el punto de inflexión de los endpoints del Lab 2.
- Si cambia el puerto o rutas del backend, actualice el Security Group `chiper-http` y los targets del plan de pruebas en JMeter.

