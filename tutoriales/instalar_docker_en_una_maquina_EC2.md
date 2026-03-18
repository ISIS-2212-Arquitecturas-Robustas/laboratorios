# Instalación de Docker en EC2

## Introducción

Docker Engine es el componente central de Docker que permite crear, ejecutar y gestionar **contenedores**.  En este tutorial se instalará **Docker Engine utilizando el repositorio oficial de Docker para Ubuntu**. Este método es el recomendado porque permite recibir actualizaciones de seguridad y nuevas versiones directamente desde los servidores de Docker.

Los pasos incluyen:

- Preparar el sistema e instalar dependencias    
- Agregar el repositorio oficial de Docker
- Instalar Docker Engine y sus herramientas
- Verificar que la instalación funciona correctamente

## 1. Actualizar el sistema

Primero actualizamos la lista de paquetes del sistema y se instalan las últimas actualizaciones disponibles para evitar conflictos durante la instalación.

```bash
sudo apt update
sudo apt upgrade -y
```

## 2. Instalar dependencias necesarias

Posterior se instalan herramientas básicas que permiten descargar paquetes de repositorios externos y manejar claves de verificación.

```bash
sudo apt install -y ca-certificates curl gnupg
```

## 3. Agregar la clave GPG oficial de Docker

Se agrega la clave criptográfica de Docker para verificar que los paquetes descargados provienen del repositorio oficial.

```bash
sudo install -m 0755 -d /etc/apt/keyrings

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

sudo chmod a+r /etc/apt/keyrings/docker.gpg
```

## 4. Agregar el repositorio oficial de Docker

En este paso se registra el repositorio oficial de Docker en el sistema para que `apt` pueda descargar e instalar Docker desde allí.

```bash
echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu \
$(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
```

## 5. Actualizar el índice de paquetes

Se vuelve a actualizar la lista de paquetes para que el sistema reconozca los paquetes disponibles en el nuevo repositorio agregado.

```bash
sudo apt update
```

## 6. Instalar Docker

Se instala el motor de Docker (Docker Engine) y las herramientas necesarias para construir, ejecutar y administrar contenedores.

```bash
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

## 7. Verificar la instalación

Se ejecuta un contenedor de prueba para confirmar que Docker fue instalado correctamente y puede ejecutar imágenes.

```bash
sudo docker run hello-world
```

## 8. Ejecutar Docker sin sudo (opcional)

Este paso permite ejecutar comandos de Docker sin utilizar `sudo`, agregando el usuario actual al grupo `docker`. (opcional)

```bash
sudo usermod -aG docker $USER
```

Luego cerrar sesión o ejecutar:

```bash
newgrp docker
```

## 9. Verificar el servicio

Se comprueba que el servicio de Docker esté activo y configurado para ejecutarse automáticamente cuando el sistema inicia.

```bash
systemctl status docker
```

Iniciar manualmente si es necesario:

```bash
sudo systemctl start docker
```

Habilitar inicio automático:

```bash
sudo systemctl enable docker
```

## 10. Comandos básicos

Finalmente se muestran algunos comandos simples para verificar la instalación y comenzar a interactuar con Docker.

Ver versión:

```bash
docker --version
```

Listar contenedores:

```bash
docker ps
```

Listar imágenes:

```bash
docker images
```