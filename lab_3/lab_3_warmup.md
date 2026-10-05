# Warm-up en clase — Lab 3: Pruebas de Carga en AWS para el Monolito de Cheapest

## Contexto

Este laboratorio despliega el monolito de Cheapest en AWS con 4 instancias EC2 (`Cheapest-db` + `Cheapest-app-1/2/3`) detrás de un ALB. Esta sesión cubre la primera parte: los 3 Security Groups y la instancia de base de datos.

## Tarea 

### 1. Configuración de seguridad (Security Groups)

> Nota: use nombres **sin tildes** y sin caracteres especiales.

Cree los siguientes Security Groups (VPC por defecto del lab):
- [Tutorial para crear Security Groups en AWS](../tutoriales/crear_security_groups.md)

**Security Group 1 — SSH**

| Parámetro    | Valor                          |
| ------------ | ------------------------------ |
| Nombre       | `Cheapest-ssh`                   |
| Descripción  | Acceso SSH a instancias        |
| Inbound rule | TCP 22 (SSH) desde `Anywhere-IPv4` |

**Security Group 2 — PostgreSQL**

| Parámetro    | Valor                          |
| ------------ | ------------------------------ |
| Nombre       | `Cheapest-db`                    |
| Descripción  | Acceso a PostgreSQL            |
| Inbound rule | TCP 5432 desde `Anywhere-IPv4` |

> En un entorno real, 5432 **no** se abre a todo internet. Para el laboratorio lo haremos así por simplicidad.

**Security Group 3 — HTTP API (Cheapest)**

| Parámetro    | Valor                          |
| ------------ | ------------------------------ |
| Nombre       | `Cheapest-http`                  |
| Descripción  | Acceso HTTP al monolito (API)  |
| Inbound rule | TCP 3000 desde `Anywhere-IPv4` |

> Si su backend corre en otro puerto, ajuste esta regla para que coincida con su configuración.

### 2. Crear instancia EC2 para Base de Datos (PostgreSQL)

- [Tutorial para crear instancias de EC2 en AWS](../tutoriales/crear_instancia_ec2.md)

Cree una instancia EC2 con los parámetros:

| Parámetro         | Valor                      |
| ----------------- | -------------------------- |
| Nombre            | `Cheapest-db`                |
| AMI               | Ubuntu Server 24.04 LTS    |
| Tipo de instancia | `t2.medium`                  |
| Key pair          | `vockey` (o una llave propia, ver nota) |
| IP pública        | Habilitar                  |
| Security Groups   | `Cheapest-ssh` + `Cheapest-db` |
| Almacenamiento    | 8 GB                       |

> [!IMPORTANT]
> **Key pair (llave SSH):** el archivo `.pem` que se usa en `ssh -i <archivo>.pem ...` es la llave privada del **key pair** que usted seleccione al crear la instancia. El key pair **no se puede cambiar** después de lanzar la instancia.
>
> - **`vockey` (recomendada):** key pair que AWS Academy ya creó en su cuenta. Descargue la llave desde la página del Learner Lab en **AWS Details → SSH key → Download PEM** (archivo `labsuser.pem`; en Windows con PuTTY use **Download PPK**).
> - **Llave propia:** créela antes de lanzar la instancia (**EC2 → Key Pairs → Create key pair**, formato `.pem`, o con el **Paso 2** del [Tutorial para crear instancias de EC2](../tutoriales/crear_instancia_ec2.md)) y guarde el archivo descargado.
>
> En Linux/macOS ejecute `chmod 400 labsuser.pem` antes de usarla. Use el mismo key pair después para las instancias de app.

**Conexión por SSH** (o desde la consola con **Connect → EC2 Instance Connect**):

```bash
ssh -i <archivo>.pem ubuntu@<IP_PUBLICA_DB>
```

**Ejecutar la base de datos (`Cheapest-db`):**

1. Conéctese por SSH a `Cheapest-db`.
2. Instale Docker. La AMI **Ubuntu Server 24.04 LTS no trae Docker preinstalado**: siga los pasos 1 a 7 del [Tutorial para instalar Docker](../tutoriales/instalar_docker_en_una_maquina_EC2.md).
3. Verifique que Docker quedó instalado y el servicio está corriendo (debe mostrar `active (running)`):

```bash
sudo docker --version
sudo service docker status
```

4. Levante PostgreSQL con Docker (si no existe el contenedor, créelo; si existe, inícielo):

```bash
# Opción A: crear y levantar (primera vez)
sudo docker run --name cheapest-db  -e POSTGRES_PASSWORD=postgres  -e POSTGRES_DB=cheapest  -p 5432:5432  -d postgres

# Opción B: si ya existe, solo iniciar
sudo docker start cheapest-db
```

5. Verifique que está arriba:

```bash
sudo docker ps
```

## Cierre de la sesión

Al terminar, cada estudiante debe tener los 3 Security Groups creados y `Cheapest-db` corriendo con PostgreSQL activo (verificado con `docker ps`). Esto es exactamente lo que pide la sección 4.2 y 4.3 del laboratorio — no hay que rehacerlo después, se sigue directamente con las 3 instancias de app.
