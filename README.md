# Guía de Implementación: Multi-Cloud Platform Infrastructure with OpenTofu

## Introducción

Esta guía te llevará paso a paso por el proceso de desarrollo e implementación de una plataforma multi-cloud basada en herramientas open source. Está diseñada para ser exhaustiva y "a prueba de tontos", detallando cada fase del proyecto, desde la configuración inicial de tu repositorio hasta el despliegue completo de la infraestructura.

## Tabla de Contenidos

1. [Preparación del Entorno](#fase-1-preparación-del-entorno)
2. [Configuración del Repositorio](#fase-2-configuración-del-repositorio)
3. [Desarrollo de Infraestructura Base](#fase-3-desarrollo-de-infraestructura-base)
4. [Implementación de Plataforma de Contenedores](#fase-4-implementación-de-plataforma-de-contenedores)
5. [Configuración del Pipeline DevOps](#fase-5-configuración-del-pipeline-devops)
6. [Implementación del Sistema de Observabilidad](#fase-6-implementación-del-sistema-de-observabilidad)
7. [Implementación de Capa de Seguridad](#fase-7-implementación-de-capa-de-seguridad)
8. [Documentación y Diagramas](#fase-8-documentación-y-diagramas)
9. [Pruebas y Validación](#fase-9-pruebas-y-validación)
10. [Extensión del Proyecto](#fase-10-extensión-del-proyecto)

---

## Fase 1: Preparación del Entorno

### 1.1 Instalación de Herramientas Esenciales

Antes de comenzar, necesitarás instalar varias herramientas clave en tu estación de trabajo local.

#### Para Linux/macOS

```bash
# Instalar Homebrew (macOS)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Instalar OpenTofu (antes Terraform Open Source)
brew update
brew install opentofu

# Instalar kubectl
brew install kubectl

# Instalar Docker
# Para macOS: Instalar Docker Desktop desde la web oficial
# Para Linux (Ubuntu):
sudo apt-get update
sudo apt-get install apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
sudo apt-get update
sudo apt-get install docker-ce docker-ce-cli containerd.io

# Instalar multipass para pruebas locales
brew install --cask multipass

# Instalar Git
brew install git
```

#### Para Windows

1. Instalar WSL2 (Windows Subsystem for Linux) siguiendo las instrucciones oficiales de Microsoft
2. Instalar Ubuntu desde la Microsoft Store
3. Seguir las instrucciones para Linux dentro de WSL2

### 1.2 Configurar credenciales para proveedores cloud

#### AWS

```bash
# Instalar AWS CLI
pip install awscli --upgrade --user

# Configurar credenciales AWS
aws configure
# Ingresar Access Key ID
# Ingresar Secret Access Key
# Ingresar Default region name (ej. us-west-2)
# Ingresar Default output format (json)
```

#### DigitalOcean

```bash
# Instalar doctl (DigitalOcean CLI)
brew install doctl

# Autenticar con token de API
doctl auth init
# Ingresar el Personal Access Token generado en tu cuenta de DigitalOcean
```

### 1.3 Crear entorno local para pruebas

```bash
# Crear VM con multipass para pruebas locales
multipass launch --name k3s-dev --memory 4G --disk 20G

# Entrar en la VM
multipass shell k3s-dev

# Instalar herramientas básicas
sudo apt update
sudo apt install -y git curl wget unzip

# Salir de la VM
exit

# O usar Lima para macOS (alternativa a multipass)
brew install lima
limactl start default
```

### 1.4 Verificar instalaciones

```bash
# Verificar OpenTofu
tofu version

# Verificar Docker
docker --version

# Verificar kubectl
kubectl version --client
```

---

## Fase 2: Configuración del Repositorio

### 2.1 Crear un nuevo repositorio en GitHub

1. Accede a [GitHub](https://github.com) e inicia sesión
2. Haz clic en el botón "+" en la esquina superior derecha y selecciona "New repository"
3. Nombra tu repositorio: `multi-cloud-platform-opentofu`
4. Agrega una descripción: "Multi-cloud platform infrastructure using OpenTofu and open source tools"
5. Selecciona "Public" (o "Private" si prefieres)
6. Marca "Add a README file"
7. Selecciona la licencia MIT (o la que prefieras)
8. Haz clic en "Create repository"

### 2.2 Clonar el repositorio localmente

```bash
# Clonar el repositorio
git clone https://github.com/tu-usuario/multi-cloud-platform-opentofu.git
cd multi-cloud-platform-opentofu
```

### 2.3 Establecer la estructura inicial del proyecto

```bash
# Crear estructura de directorios básica
mkdir -p docs/diagrams docs/decision-records
mkdir -p infrastructure/modules/{compute,networking,storage}
mkdir -p infrastructure/{aws,digitalocean}
mkdir -p platform/kubernetes/{cilium,monitoring,storage}
mkdir -p platform/applications/{gitea,drone,vault}
mkdir -p policies/{opa,network}
mkdir -p scripts

# Crear archivos README iniciales
echo "# Multi-Cloud Platform with OpenTofu" > README.md
echo "Este proyecto implementa una arquitectura multi-cloud utilizando OpenTofu y herramientas open source." >> README.md

echo "# Infrastructure Modules" > infrastructure/modules/README.md
echo "# AWS Infrastructure" > infrastructure/aws/README.md
echo "# DigitalOcean Infrastructure" > infrastructure/digitalocean/README.md

echo "# Kubernetes Platform" > platform/kubernetes/README.md
echo "# Platform Applications" > platform/applications/README.md

echo "# Security Policies" > policies/README.md

echo "# Project Scripts" > scripts/README.md
```

### 2.4 Crear un archivo .gitignore básico

```bash
cat > .gitignore << 'EOF'
# OpenTofu
**/.terraform/*
*.tfstate
*.tfstate.*
crash.log
crash.*.log
*.tfvars
*.tfvars.json
override.tf
override.tf.json
*_override.tf
*_override.tf.json
.terraformrc
terraform.rc
.terraform.lock.hcl

# Secrets
*.pem
*.key
*.p12
*.pfx
.env
secrets/
kubeconfig
*.kubeconfig

# OS specific
.DS_Store
Thumbs.db

# IDEs and editors
.idea/
.vscode/
*.swp
*.swo
*~
EOF
```

### 2.5 Primer commit y push

```bash
git add .
git commit -m "Initial project structure"
git push origin main
```

---

## Fase 3: Desarrollo de Infraestructura Base

### 3.1 Crear módulos reutilizables de OpenTofu

Primero, vamos a desarrollar los módulos base que serán utilizados por múltiples proveedores.

#### 3.1.1 Módulo de Networking

```bash
# Crear archivos del módulo de networking
mkdir -p infrastructure/modules/networking/vpc
cat > infrastructure/modules/networking/vpc/main.tf << 'EOF'
variable "name" {
  description = "Name to be used on all the resources as identifier"
  type        = string
}

variable "cidr" {
  description = "The CIDR block for the VPC"
  type        = string
}

variable "azs" {
  description = "A list of availability zones in the region"
  type        = list(string)
  default     = []
}

variable "private_subnets" {
  description = "A list of private subnets inside the VPC"
  type        = list(string)
  default     = []
}

variable "public_subnets" {
  description = "A list of public subnets inside the VPC"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}

# Outputs will be different for each cloud provider
# This is just a template
output "vpc_id" {
  description = "The ID of the VPC"
  value       = "PROVIDER_SPECIFIC"
}

output "private_subnet_ids" {
  description = "List of IDs of private subnets"
  value       = []
}

output "public_subnet_ids" {
  description = "List of IDs of public subnets"
  value       = []
}
EOF

cat > infrastructure/modules/networking/security-groups/main.tf << 'EOF'
variable "name" {
  description = "Name to be used on all the resources as identifier"
  type        = string
}

variable "vpc_id" {
  description = "The ID of the VPC"
  type        = string
}

variable "ingress_rules" {
  description = "List of ingress rules"
  type = list(object({
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = list(string)
    description = string
  }))
  default = []
}

variable "egress_rules" {
  description = "List of egress rules"
  type = list(object({
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = list(string)
    description = string
  }))
  default = [
    {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
      description = "Allow all outbound traffic"
    }
  ]
}

# Provider-specific implementation will go here

output "security_group_id" {
  description = "The ID of the security group"
  value       = "PROVIDER_SPECIFIC"
}
EOF
```

#### 3.1.2 Módulo de Compute

```bash
# Crear archivos del módulo de compute
mkdir -p infrastructure/modules/compute/virtual-machines
cat > infrastructure/modules/compute/virtual-machines/main.tf << 'EOF'
variable "name" {
  description = "Name to be used on all the resources as identifier"
  type        = string
}

variable "instance_count" {
  description = "Number of instances to launch"
  type        = number
  default     = 1
}

variable "instance_type" {
  description = "The type of instance to start"
  type        = string
}

variable "subnet_ids" {
  description = "The VPC Subnet IDs to launch in"
  type        = list(string)
}

variable "security_group_ids" {
  description = "A list of security group IDs to associate with"
  type        = list(string)
  default     = []
}

variable "user_data" {
  description = "The user data to provide when launching the instance"
  type        = string
  default     = ""
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}

# Provider-specific implementation will go here

output "instance_ids" {
  description = "List of IDs of instances"
  value       = []
}

output "public_ips" {
  description = "List of public IP addresses assigned to the instances"
  value       = []
}
EOF
```

#### 3.1.3 Módulo de Storage

```bash
# Crear archivos del módulo de storage
mkdir -p infrastructure/modules/storage/object-storage
cat > infrastructure/modules/storage/object-storage/main.tf << 'EOF'
variable "name" {
  description = "Name to be used for the bucket"
  type        = string
}

variable "versioning_enabled" {
  description = "Whether to enable versioning"
  type        = bool
  default     = false
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}

# Provider-specific implementation will go here

output "bucket_id" {
  description = "The ID of the bucket"
  value       = "PROVIDER_SPECIFIC"
}

output "bucket_arn" {
  description = "The ARN of the bucket"
  value       = "PROVIDER_SPECIFIC"
}
EOF
```

### 3.2 Implementar módulos específicos para AWS

#### 3.2.1 Proveedor de AWS

```bash
# Crear archivo de configuración del proveedor AWS
cat > infrastructure/aws/providers.tf << 'EOF'
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
  # Si usas el backend S3, descomentar lo siguiente:
  # backend "s3" {
  #   bucket = "your-terraform-state-bucket"
  #   key    = "multi-cloud-platform/terraform.tfstate"
  #   region = "us-west-2"
  # }
}

provider "aws" {
  region = var.aws_region

  # Default tags applied to all resources
  default_tags {
    tags = {
      Environment = var.environment
      Project     = "multi-cloud-platform"
      ManagedBy   = "opentofu"
    }
  }
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}
EOF
```

#### 3.2.2 VPC en AWS

```bash
# Crear modulo VPC para AWS
cat > infrastructure/aws/vpc.tf << 'EOF'
module "vpc" {
  source = "../modules/networking/vpc"

  name = "${var.environment}-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["${var.aws_region}a", "${var.aws_region}b", "${var.aws_region}c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  tags = {
    Terraform   = "true"
    Environment = var.environment
  }
}

resource "aws_vpc" "main" {
  cidr_block           = module.vpc.cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = module.vpc.name
  }
}

resource "aws_subnet" "private" {
  count = length(module.vpc.private_subnets)

  vpc_id            = aws_vpc.main.id
  cidr_block        = module.vpc.private_subnets[count.index]
  availability_zone = module.vpc.azs[count.index]

  tags = {
    Name = "${module.vpc.name}-private-${count.index}"
  }
}

resource "aws_subnet" "public" {
  count = length(module.vpc.public_subnets)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = module.vpc.public_subnets[count.index]
  availability_zone       = module.vpc.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${module.vpc.name}-public-${count.index}"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${module.vpc.name}-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${module.vpc.name}-public-rt"
  }
}

resource "aws_route" "public_internet_gateway" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  vpc = true

  tags = {
    Name = "${module.vpc.name}-nat-eip"
  }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name = "${module.vpc.name}-nat-gw"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${module.vpc.name}-private-rt"
  }
}

resource "aws_route" "private_nat_gateway" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main.id
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
EOF
```

#### 3.2.3 EC2 en AWS

```bash
# Crear módulo EC2 para AWS
cat > infrastructure/aws/ec2.tf << 'EOF'
module "ec2_cluster" {
  source = "../modules/compute/virtual-machines"

  name           = "${var.environment}-k3s-cluster"
  instance_count = 3
  instance_type  = "t3.medium"
  subnet_ids     = aws_subnet.private[*].id
  security_group_ids = [
    aws_security_group.k3s.id
  ]

  user_data = <<-EOF
    #!/bin/bash
    export INSTALL_K3S_VERSION=v1.25.5+k3s1
    curl -sfL https://get.k3s.io | sh -
  EOF

  tags = {
    Terraform   = "true"
    Environment = var.environment
  }
}

resource "aws_instance" "k3s_server" {
  count = module.ec2_cluster.instance_count

  ami           = "ami-0c55b159cbfafe1f0" # Amazon Linux 2 AMI (replace with the latest)
  instance_type = module.ec2_cluster.instance_type
  subnet_id     = module.ec2_cluster.subnet_ids[count.index % length(module.ec2_cluster.subnet_ids)]

  vpc_security_group_ids = module.ec2_cluster.security_group_ids

  user_data = module.ec2_cluster.user_data

  root_block_device {
    volume_size = 50
    volume_type = "gp3"
  }

  tags = merge(
    {
      Name = "${module.ec2_cluster.name}-${count.index}"
    },
    module.ec2_cluster.tags
  )
}

resource "aws_security_group" "k3s" {
  name        = "${var.environment}-k3s-sg"
  description = "Security group for K3s cluster"
  vpc_id      = aws_vpc.main.id

  # Allow all internal traffic
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_vpc.main.cidr_block]
    description = "Allow all internal traffic"
  }

  # SSH from bastion
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
    description     = "SSH from bastion"
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name        = "${var.environment}-k3s-sg"
    Terraform   = "true"
    Environment = var.environment
  }
}

resource "aws_security_group" "bastion" {
  name        = "${var.environment}-bastion-sg"
  description = "Security group for bastion host"
  vpc_id      = aws_vpc.main.id

  # SSH from anywhere (you might want to restrict this)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH from anywhere"
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name        = "${var.environment}-bastion-sg"
    Terraform   = "true"
    Environment = var.environment
  }
}

resource "aws_instance" "bastion" {
  ami           = "ami-0c55b159cbfafe1f0" # Amazon Linux 2 AMI (replace with the latest)
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.public[0].id

  vpc_security_group_ids = [aws_security_group.bastion.id]

  associate_public_ip_address = true

  key_name = aws_key_pair.deployer.key_name

  tags = {
    Name        = "${var.environment}-bastion"
    Terraform   = "true"
    Environment = var.environment
  }
}

resource "aws_key_pair" "deployer" {
  key_name   = "${var.environment}-deployer-key"
  public_key = file("~/.ssh/id_rsa.pub") # Make sure this file exists!

  tags = {
    Terraform   = "true"
    Environment = var.environment
  }
}

output "bastion_public_ip" {
  description = "Public IP of the bastion host"
  value       = aws_instance.bastion.public_ip
}

output "k3s_server_private_ips" {
  description = "Private IPs of K3s servers"
  value       = aws_instance.k3s_server[*].private_ip
}
EOF
```

#### 3.2.4 S3 en AWS

```bash
# Crear módulo S3 para AWS
cat > infrastructure/aws/s3.tf << 'EOF'
module "state_bucket" {
  source = "../modules/storage/object-storage"

  name               = "${var.environment}-state-bucket"
  versioning_enabled = true

  tags = {
    Terraform   = "true"
    Environment = var.environment
  }
}

resource "aws_s3_bucket" "state_bucket" {
  bucket = "${var.environment}-state-bucket-${data.aws_caller_identity.current.account_id}"

  tags = module.state_bucket.tags
}

resource "aws_s3_bucket_versioning" "state_bucket" {
  bucket = aws_s3_bucket.state_bucket.id
  versioning_configuration {
    status = module.state_bucket.versioning_enabled ? "Enabled" : "Disabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state_bucket" {
  bucket = aws_s3_bucket.state_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

data "aws_caller_identity" "current" {}

output "state_bucket_name" {
  description = "The name of the S3 bucket for state storage"
  value       = aws_s3_bucket.state_bucket.bucket
}
EOF
```

### 3.3 Implementar módulos específicos para DigitalOcean

#### 3.3.1 Proveedor de DigitalOcean

```bash
# Crear archivo de configuración del proveedor DigitalOcean
cat > infrastructure/digitalocean/providers.tf << 'EOF'
terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }
  # Si usas el backend S3, descomentar lo siguiente:
  # backend "s3" {
  #   bucket = "your-terraform-state-bucket"
  #   key    = "multi-cloud-platform/do/terraform.tfstate"
  #   region = "us-west-2"
  # }
}

provider "digitalocean" {
  # Token is loaded from DIGITALOCEAN_TOKEN environment variable or in variables.tf
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "region" {
  description = "DigitalOcean region"
  type        = string
  default     = "nyc3"
}

variable "do_token" {
  description = "DigitalOcean API token"
  type        = string
  sensitive   = true
}
EOF
```

#### 3.3.2 VPC en DigitalOcean

```bash
# Crear módulo VPC para DigitalOcean
cat > infrastructure/digitalocean/vpc.tf << 'EOF'
resource "digitalocean_vpc" "main" {
  name        = "${var.environment}-vpc"
  region      = var.region
  description = "${var.environment} VPC"
  ip_range    = "10.10.0.0/16"
}

output "vpc_id" {
  description = "The ID of the VPC"
  value       = digitalocean_vpc.main.id
}

output "vpc_ip_range" {
  description = "The range of IP addresses for the VPC"
  value       = digitalocean_vpc.main.ip_range
}
EOF
```

#### 3.3.3 Droplets en DigitalOcean

```bash
# Crear módulo Droplets para DigitalOcean
cat > infrastructure/digitalocean/droplets.tf << 'EOF'
data "digitalocean_ssh_key" "deployer" {
  name = "deployer-key" # Make sure this key exists in your DO account!
}

resource "digitalocean_droplet" "k3s_server" {
  count = 3

  image     = "ubuntu-20-04-x64"
  name      = "${var.environment}-k3s-server-${count.index}"
  region    = var.region
  size      = "s-2vcpu-4gb"
  vpc_uuid  = digitalocean_vpc.main.id
  ssh_keys  = [data.digitalocean_ssh_key.deployer.id]
  monitoring = true

  user_data = <<-EOF
    #!/bin/bash
    export INSTALL_K3S_VERSION=v1.25.5+k3s1
    curl -sfL https://get.k3s.io | sh -
  EOF

  tags = ["${var.environment}", "k3s", "server"]
}

resource "digitalocean_droplet" "bastion" {
  image     = "ubuntu-20-04-x64"
  name      = "${var.environment}-bastion"
  region    = var.region
  size      = "s-1vcpu-1gb"
  vpc_uuid  = digitalocean_vpc.main.id
  ssh_keys  = [data.digitalocean_ssh_key.deployer.id]
  monitoring = true

  tags = ["${var.environment}", "bastion"]
}

resource "digitalocean_firewall" "k3s" {
  name = "${var.environment}-k3s-firewall"

  tags = ["${var.environment}", "k3s"]

  # Allow internal VPC traffic
  inbound_rule {
    protocol         = "tcp"
    port_range       = "1-65535"
    source_addresses = [digitalocean_vpc.main.ip_range]
  }

  inbound_rule {
    protocol         = "udp"
    port_range       = "1-65535"
    source_addresses = [digitalocean_vpc.main.ip_range]
  }

  # Allow SSH from bastion
  inbound_rule {
    protocol           = "tcp"
    port_range         = "22"
    source_droplet_ids = [digitalocean_droplet.bastion.id]
  }

  # Allow all outbound traffic
  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "icmp"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}

resource "digitalocean_firewall" "bastion" {
  name = "${var.environment}-bastion-firewall"

  tags = ["${var.environment}", "bastion"]

  # Allow SSH from anywhere
  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Allow all outbound traffic
  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "icmp"
    destination_
