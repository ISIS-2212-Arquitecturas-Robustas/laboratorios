#!/bin/bash

set -e

echo "Actualizando paquetes..."
sudo apt update

echo "Instalando dependencias..."
sudo apt install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

echo "Agregando clave GPG de Docker..."
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
 | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo "Agregando repositorio oficial de Docker..."
echo \
  "deb [arch=$(dpkg --print-architecture) \
  signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

echo "Actualizando repositorios..."
sudo apt update

echo "Instalando Docker..."
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "Agregando usuario actual al grupo docker..."
sudo usermod -aG docker $USER

echo "Habilitando servicio Docker..."
sudo systemctl enable docker
sudo systemctl start docker

echo "Instalación finalizada."
echo "Cierra sesión y vuelve a entrar para usar docker sin sudo."

echo "Prueba Docker con:"
echo "docker run hello-world"