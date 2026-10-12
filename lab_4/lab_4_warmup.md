# Warm-up en clase — Lab 4: Pruebas de Carga en AWS para la Arquitectura de Microservicios

## Contexto

Cheapest pasa de monolito a 3 microservicios (Logística, Inventario, Ventas). Los cambios están en la rama `microservicios` del repositorio `Cheapest-api`. Cada microservicio se empaqueta como una imagen Docker, y AWS necesita un lugar de donde descargarla cada vez que arranca un contenedor. Ese lugar es **Amazon ECR** (Elastic Container Registry), un registro privado de imágenes Docker dentro de su cuenta de AWS (el equivalente a Docker Hub, pero en AWS). Antes de crear cualquier otra pieza de la infraestructura, hay que publicar la imagen de cada servicio en su propio repositorio de ECR.

## Tarea 

### Publicar imágenes en ECR

Debe crear un repositorio por servicio.

| Servicio   | Nombre sugerido del repositorio | Nombre de la imagen | Tag imagen |
| ---------- | --------------------------- | ---------- | ---------- |
| Logistica  | `cheapest-logistica`          | `logistica-service`          | `1.0.0`    |
| Inventario | `cheapest-inventario`         | `inventario-service`         | `1.0.0`    |
| Ventas     | `cheapest-ventas`             | `ventas-service`             | `1.0.0`    |

Para cada servicio debe: construir una imagen, etiquetar con el URI del repositorio y publicar en ECR.

Tutorial de apoyo:
- [Subir imágenes Docker a Amazon ECR](../tutoriales/subir_imagenes%20_a_ecr.md)

Al final tendrá que ver algo así:
![](./recursos/ecr_view.png)
Y dentro de cada repositorio
![](./recursos/ecr_image.png)

## Cierre de la sesión

Al terminar, cada estudiante debe tener los 3 repositorios ECR creados con su imagen publicada (verificado con las capturas de arriba). Esto es exactamente el primer paso del despliegue del laboratorio (publicar las imágenes en ECR): no hay que rehacerlo después, se sigue directamente con la creación de la base de datos, el balanceador de carga, los contenedores y el API Gateway.
