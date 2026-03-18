# Crear un grupo de seguridad con la AWS console

## Objetivos
Crear un grupo de seguridad con reglas de entrada para permitir tráfico necesario a instancias EC2 dentro de AWS.
## Marco conceptual
### Grupos de seguridad
Los grupos de seguridad en AWS son un conjunto de reglas para restringir el tráfico desde y hacía instancias de EC2 u otros recursos de AWS. En otras palabras, un grupo de seguridad funciona como un firewall para las instancias EC2. Las reglas buscan proteger a las instancias de accesos no permitidos. Las reglas pueden especificar protocolos y puertos. Se pueden asociar varios grupos de seguridad a una instancia EC2 y varias instancias a un grupo.

Más información en: [Grupos de seguridad de Amazon EC2 para instancias EC2](https://docs.aws.amazon.com/es_es/AWSEC2/latest/UserGuide/ec2-security-groups.html)

## Tutorial consola AWS
El siguiente tutorial usará la herramienta CloudShell para crear los grupos de seguridad, de igual forma si desea usar la consola de AWS puede seguir el siguiente [tutorial]([https://uniandes.sharepoint.com/:w:/s/isis2503/Edx0xHcn-3xJjIcaO-TIuWkBR8WqJ5l4q1yw2UR1znQY1g?e=YDVIcv](https://docs.aws.amazon.com/es_es/AWSEC2/latest/UserGuide/creating-security-group.html))


En este tutorial se creará un **Security Group** para permitir acceso **SSH (puerto 22)** a instancias EC2 usando **AWS CloudShell**, evitando configurar credenciales locales.

## Tutorial Cloudshell

### 0. VPC a crear
La VPC que vamos a crear en el tutorial está definida en la siguiente tabla

| Parámetro    | Valor                          |
| ------------ | ------------------------------ |
| Nombre       | `chiper-ssh`                   |
| Descripción  | Acceso SSH a instancias        |
| Inbound rule | SSH (22) desde `Anywhere-IPv4` |
### 1. Abrir AWS CloudShell

1. Inicie sesión en la **AWS Console**.
2. En la barra superior seleccione el ícono de **CloudShell**.

El ícono luce así:
![](Pasted%20image%2020260310221313.png)
3. Espere a que se abra la terminal.

CloudShell ya incluye:
- AWS CLI
- Credenciales configuradas automáticamente
- Acceso a la cuenta actual
### 2. Identificar el VPC

Los **Security Groups se crean dentro de un VPC**.

Para listar los VPC disponibles:

``` bash
aws ec2 describe-vpcs --query "Vpcs[*].{VpcId:VpcId,Cidr:CidrBlock}"
```

Ejemplo de salida:

``` json
[
    {
        "VpcId": "vpc-0add8539168166c0f",
        "Cidr": "172.31.0.0/16"
    }
]
```

El **VpcId** es el identificador de su nube privada, que es donde se creará el grupo de seguridad. Debe guardarlo para los pasos siguientes

### 3. Crear el Security Group

Ejecute el siguiente comando:

``` bash
aws ec2 create-security-group --group-name <NOMBRE_GRUPO> --description "Descripción breve del SG" --vpc-id <SU_VPCID>
```

Salida esperada:
``` json
{
    "GroupId": "sg-06e0bebff7c164598",
    "SecurityGroupArn": "arn:aws:ec2:us-east-1:449642781982:security-group/sg-06e0bebff7c164598"
}
```

Guarde el **GroupId**.
### 4. Crear la regla de acceso SSH
Ahora agregaremos la regla **Inbound** para permitir SSH desde cualquier IP.

``` bash
aws ec2 authorize-security-group-ingress --group-id <SU_SECURITY_GROUP_ID> --protocol <SU_PROTOCOLO> --port <SU_PUERTO> --cidr <SU_CIDR>
```

Recuerde que el CIDR representa una porción de red, en este caso la que queremos que tenga acceso a través de esta regla (`0.0.0.0/0` es el CIDR que cubre todas las direcciones IPv)
# 5. Verificar el Security Group

Para confirmar que se creó correctamente:

``` bash
aws ec2 describe-security-groups --group-ids <SU_SECURITY_GROUP_ID>
```
Debe aparecer algo similar a:

``` json
{
    "SecurityGroups": [
        {
            "GroupId": "sg-06e0bebff7c164598",
            "IpPermissionsEgress": [
                {
                    "IpProtocol": "-1",
                    "UserIdGroupPairs": [],
                    "IpRanges": [
                        {
                            "CidrIp": "0.0.0.0/0"
                        }
                    ],
                    "Ipv6Ranges": [],
                    "PrefixListIds": []
                }
            ],
            "VpcId": "vpc-0add8539168166c0f",
            "SecurityGroupArn": "arn:aws:ec2:us-east-1:449642781982:security-group/sg-06e0bebff7c164598",
            "OwnerId": "449642781982",
            "GroupName": "chiper-ssh",
            "Description": "Acceso SSH a instancias",
            "IpPermissions": [
                {
                    "IpProtocol": "tcp",
                    "FromPort": 22,
                    "ToPort": 22,
                    "UserIdGroupPairs": [],
                    "IpRanges": [
                        {
                            "CidrIp": "0.0.0.0/0"
                        }
                    ],
                    "Ipv6Ranges": [],
                    "PrefixListIds": []
                }
            ]
        }
    ]
}
```
---

# 6. Resultado final

El Security Group creado tiene la siguiente configuración:

|Parámetro|Valor|
|---|---|
|Nombre|`chiper-ssh`|
|Descripción|Acceso SSH a instancias|
|Inbound rule|SSH (22) desde `0.0.0.0/0`|
En la AWS console

![](Pasted%20image%2020260310223442.png)