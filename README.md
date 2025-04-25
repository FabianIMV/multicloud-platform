# Implementación Multi-Cloud con OpenTofu: Versión sin costo

Esta guía adaptada te permitirá implementar la arquitectura multi-cloud con herramientas open source sin incurrir en costos, y posteriormente escalarla fácilmente a entornos cloud cuando estés listo (aprovechando tus créditos de AWS).

## Tabla de Contenidos

1. [Preparación del Entorno Local](#1-preparación-del-entorno-local)
2. [Configuración del Repositorio](#2-configuración-del-repositorio)
3. [Infraestructura Local con K3d](#3-infraestructura-local-con-k3d)
4. [Plataforma de Contenedores](#4-plataforma-de-contenedores)
5. [Pipeline DevOps Local](#5-pipeline-devops-local)
6. [Sistema de Observabilidad](#6-sistema-de-observabilidad)
7. [Capa de Seguridad](#7-capa-de-seguridad)
8. [Documentación y Diagramas](#8-documentación-y-diagramas)
9. [Migración a AWS](#9-migración-a-aws)
10. [Extensiones Avanzadas](#10-extensiones-avanzadas)

## 1. Preparación del Entorno Local

### 1.1 Instalar herramientas esenciales

```bash
# Instalar Docker
# Para Linux (Ubuntu):
sudo apt update
sudo apt install docker.io docker-compose
sudo usermod -aG docker $USER
# Para macOS: Instalar Docker Desktop desde la web oficial
# Para Windows: Instalar Docker Desktop con WSL2

# Instalar OpenTofu
# Linux
curl -Lo tofu.zip https://github.com/opentofu/opentofu/releases/download/v1.6.0/tofu_1.6.0_linux_amd64.zip
unzip tofu.zip && rm tofu.zip
sudo mv tofu /usr/local/bin/
# macOS
brew install opentofu/tap/opentofu

# Instalar kubectl
# Linux
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
# macOS
brew install kubectl

# Instalar K3d (K3s en Docker - mucho más ligero que minikube)
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

# Instalar Helm
# Linux
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
# macOS
brew install helm
```

### 1.2 Verificar instalaciones

```bash
docker --version
tofu version
kubectl version --client
k3d version
helm version
```

## 2. Configuración del Repositorio

### 2.1 Crear repositorio en GitHub

1. Accede a [GitHub](https://github.com) e inicia sesión
2. Crea un nuevo repositorio llamado `multi-cloud-platform-opentofu`
3. Marca "Add a README file" y elige la licencia MIT

### 2.2 Clonar y estructurar el repositorio

```bash
# Clonar el repositorio
git clone https://github.com/tu-usuario/multi-cloud-platform-opentofu.git
cd multi-cloud-platform-opentofu

# Crear estructura de directorios
mkdir -p docs/diagrams docs/decision-records
mkdir -p local-dev/k3d
mkdir -p infrastructure/modules/{compute,networking,storage}
mkdir -p infrastructure/{local,aws}
mkdir -p platform/kubernetes/{cilium,monitoring,storage}
mkdir -p platform/applications/{gitea,drone,vault}
mkdir -p policies/opa
mkdir -p scripts

# Crear README principal
cat > README.md << 'EOF'
# Multi-Cloud Platform Infrastructure

Este proyecto implementa una arquitectura multi-cloud usando OpenTofu y herramientas open source:

## Componentes principales

- **OpenTofu**: Infraestructura como código
- **K3d/K3s**: Kubernetes ligero para desarrollo y producción
- **Cilium**: Networking y service mesh
- **MinIO**: Almacenamiento compatible con S3
- **Gitea**: Git self-hosted
- **Drone CI**: Pipelines de CI/CD
- **Grafana/Prometheus/Loki**: Stack de observabilidad
- **Vault**: Gestión de secretos
- **OPA**: Políticas de seguridad

## Características

- Comienza con costo $0 en entorno local
- Migra fácilmente a proveedores cloud
- Arquitectura completamente open source
- Documentación exhaustiva y buenas prácticas

## Estructura
...
EOF

# Crear .gitignore
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

# Kubernetes
kubeconfig*
*.kubeconfig

# Secrets
*.pem
*.key
*.p12
*.pfx
.env
secrets/

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

# Commit inicial
git add .
git commit -m "Estructura inicial del proyecto"
git push origin main
```

## 3. Infraestructura Local con K3d

### 3.1 Configurar entorno Kubernetes local

```bash
# Crear archivo de configuración K3d
cat > local-dev/k3d/cluster.yaml << 'EOF'
apiVersion: k3d.io/v1alpha4
kind: Simple
metadata:
  name: multi-cloud-cluster
servers: 1
agents: 2
image: rancher/k3s:v1.27.4-k3s1
ports:
  - port: 80:80
    nodeFilters:
      - loadbalancer
  - port: 443:443
    nodeFilters:
      - loadbalancer
options:
  k3d:
    wait: true
    timeout: "60s"
  k3s:
    extraArgs:
      - arg: --disable=traefik
        nodeFilters:
          - server:*
registries:
  create:
    name: registry.localhost
    host: "0.0.0.0"
    hostPort: "5000"
EOF

# Script para crear el cluster
cat > scripts/create-local-cluster.sh << 'EOF'
#!/bin/bash
set -e

echo "Creando cluster K3d..."
k3d cluster create --config local-dev/k3d/cluster.yaml

echo "Esperando que el cluster esté listo..."
kubectl wait --for=condition=Ready nodes --all --timeout=120s

echo "Configurando kubectl y contexto..."
kubectl config use-context k3d-multi-cloud-cluster

echo "Cluster K3d listo y configurado!"
kubectl get nodes
EOF

# Otorgar permisos de ejecución
chmod +x scripts/create-local-cluster.sh

# Crear el cluster local
./scripts/create-local-cluster.sh
```

### 3.2 Definir modelos de infraestructura con OpenTofu

```bash
# Crear definición para entorno local
cat > infrastructure/local/main.tf << 'EOF'
terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.21"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.10"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
  }
}

provider "kubernetes" {
  config_path = "~/.kube/config"
  config_context = "k3d-multi-cloud-cluster"
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
    config_context = "k3d-multi-cloud-cluster"
  }
}

provider "kubectl" {
  config_path = "~/.kube/config"
  config_context = "k3d-multi-cloud-cluster"
}

resource "kubernetes_namespace" "platform" {
  metadata {
    name = "platform"
  }
}

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
  }
}

resource "kubernetes_namespace" "security" {
  metadata {
    name = "security"
  }
}

output "kubernetes_namespaces" {
  value = [
    kubernetes_namespace.platform.metadata[0].name,
    kubernetes_namespace.monitoring.metadata[0].name,
    kubernetes_namespace.security.metadata[0].name
  ]
}
EOF

# Inicializar y aplicar
cd infrastructure/local
tofu init
tofu apply -auto-approve
cd ../..
```

### 3.3 Crear módulos base compatibles con cloud

```bash
# Crear módulos reutilizables que funcionarán tanto en local como en cloud
cat > infrastructure/modules/kubernetes/namespace/main.tf << 'EOF'
variable "name" {
  description = "Namespace name"
  type        = string
}

variable "labels" {
  description = "Labels to apply to the namespace"
  type        = map(string)
  default     = {}
}

variable "annotations" {
  description = "Annotations to apply to the namespace"
  type        = map(string)
  default     = {}
}

resource "kubernetes_namespace" "this" {
  metadata {
    name        = var.name
    labels      = var.labels
    annotations = var.annotations
  }
}

output "name" {
  description = "The name of the namespace"
  value       = kubernetes_namespace.this.metadata[0].name
}
EOF

# Crear módulo de almacenamiento
cat > infrastructure/modules/storage/object-storage/main.tf << 'EOF'
variable "name" {
  description = "Storage name identifier"
  type        = string
}

variable "provider_type" {
  description = "Type of provider (local, aws, digitalocean)"
  type        = string
  default     = "local"
}

variable "size" {
  description = "Storage size (for local PVC)"
  type        = string
  default     = "10Gi"
}

# Este módulo implementará diferentes recursos según el provider_type
# Ejemplo para local sería un PVC, para AWS sería S3, etc.

# Para entorno local (K3d)
resource "kubernetes_persistent_volume_claim" "local_storage" {
  count = var.provider_type == "local" ? 1 : 0
  
  metadata {
    name = "${var.name}-pvc"
    namespace = "platform"
  }
  
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = var.size
      }
    }
    storage_class_name = "local-path"
  }
}

# Dummy para AWS - se expandirá cuando migremos
# resource "aws_s3_bucket" "s3_storage" {
#   count = var.provider_type == "aws" ? 1 : 0
#   bucket = var.name
# }

output "storage_id" {
  description = "ID of the created storage"
  value = var.provider_type == "local" ? (
    length(kubernetes_persistent_volume_claim.local_storage) > 0 ? 
    kubernetes_persistent_volume_claim.local_storage[0].metadata[0].name : ""
  ) : ""
}
EOF
```

## 4. Plataforma de Contenedores

### 4.1 Instalar Cilium para networking

```bash
# Crear manifest para Cilium
cat > platform/kubernetes/cilium/values.yaml << 'EOF'
ipam:
  mode: kubernetes
operator:
  replicas: 1
hubble:
  enabled: true
  relay:
    enabled: true
  ui:
    enabled: true
EOF

# Crear script de instalación
cat > scripts/install-cilium.sh << 'EOF'
#!/bin/bash
set -e

echo "Instalando Cilium mediante Helm..."
helm repo add cilium https://helm.cilium.io/
helm repo update

helm upgrade --install cilium cilium/cilium \
  --version 1.14.1 \
  --namespace kube-system \
  -f platform/kubernetes/cilium/values.yaml

echo "Esperando que Cilium esté listo..."
kubectl -n kube-system wait --for=condition=Ready pod -l k8s-app=cilium-operator --timeout=120s
kubectl -n kube-system wait --for=condition=Ready pod -l k8s-app=cilium --timeout=120s

echo "Verificando estado de Cilium..."
cilium_status=$(kubectl -n kube-system exec -ti ds/cilium -- cilium status)
echo "$cilium_status"

echo "Cilium instalado correctamente!"
EOF

chmod +x scripts/install-cilium.sh
./scripts/install-cilium.sh
```

### 4.2 Configurar almacenamiento persistente con Longhorn

```bash
# Crear valores para Longhorn
cat > platform/kubernetes/storage/values.yaml << 'EOF'
defaultSettings:
  defaultReplicaCount: 1  # Para entorno local es suficiente con 1 réplica
  createDefaultDiskLabeledNodes: true
persistence:
  defaultClassReplicaCount: 1
  reclaimPolicy: Retain
EOF

# Script de instalación
cat > scripts/install-longhorn.sh << 'EOF'
#!/bin/bash
set -e

echo "Instalando Longhorn mediante Helm..."
kubectl create namespace longhorn-system --dry-run=client -o yaml | kubectl apply -f -

helm repo add longhorn https://charts.longhorn.io
helm repo update

helm upgrade --install longhorn longhorn/longhorn \
  --namespace longhorn-system \
  -f platform/kubernetes/storage/values.yaml

echo "Esperando que Longhorn esté listo..."
kubectl -n longhorn-system wait --for=condition=Ready pod -l app=longhorn-manager --timeout=180s

echo "Configurando Longhorn como storage class por defecto..."
kubectl patch storageclass longhorn -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

echo "Longhorn instalado correctamente!"
kubectl get storageclass
EOF

chmod +x scripts/install-longhorn.sh
./scripts/install-longhorn.sh
```

### 4.3 Implementar MinIO como alternativa a S3

```bash
# Instalar MinIO
cat > platform/applications/minio/values.yaml << 'EOF'
mode: standalone
persistence:
  size: 10Gi
resources:
  requests:
    memory: 512Mi
    cpu: 250m
  limits:
    memory: 1Gi
    cpu: 500m
rootUser: "admin"
rootPassword: "minioadmin"  # Cambiar en entorno real
consoleService:
  type: ClusterIP
service:
  type: ClusterIP
ingress:
  enabled: true
  ingressClassName: nginx
  hostname: minio.local
EOF

# Configuración con OpenTofu
cat > infrastructure/local/storage.tf << 'EOF'
resource "helm_release" "minio" {
  name       = "minio"
  repository = "https://charts.min.io/"
  chart      = "minio"
  version    = "5.0.7"
  namespace  = kubernetes_namespace.platform.metadata[0].name

  values = [
    file("../../platform/applications/minio/values.yaml")
  ]
}

output "minio_service" {
  value = "minio.${kubernetes_namespace.platform.metadata[0].name}.svc.cluster.local"
}
EOF

# Actualizar configuración
cd infrastructure/local
tofu init
tofu apply -auto-approve
cd ../..
```

## 5. Pipeline DevOps Local

### 5.1 Instalar Gitea como sistema de control de versiones

```bash
# Configuración de Gitea
cat > platform/applications/gitea/values.yaml << 'EOF'
gitea:
  admin:
    username: gitea_admin
    password: gitea_admin  # Cambiar en entorno real
    email: "admin@example.com"

persistence:
  enabled: true
  size: 5Gi

service:
  http:
    type: ClusterIP

ingress:
  enabled: true
  className: nginx
  hosts:
    - host: gitea.local
      paths:
        - path: /
          pathType: Prefix
EOF

# Archivo OpenTofu para Gitea
cat > infrastructure/local/gitea.tf << 'EOF'
resource "helm_release" "gitea" {
  name       = "gitea"
  repository = "https://dl.gitea.io/charts/"
  chart      = "gitea"
  version    = "8.3.0"
  namespace  = kubernetes_namespace.platform.metadata[0].name

  values = [
    file("../../platform/applications/gitea/values.yaml")
  ]
}

output "gitea_service" {
  value = "gitea-http.${kubernetes_namespace.platform.metadata[0].name}.svc.cluster.local"
}
EOF

# Aplicar cambios
cd infrastructure/local
tofu apply -auto-approve
cd ../..
```

### 5.2 Instalar Drone CI para pipelines

```bash
# Crear valores para Drone
cat > platform/applications/drone/values.yaml << 'EOF'
service:
  type: ClusterIP

sourceControl:
  provider: gitea
  gitea:
    server: http://gitea-http.platform.svc.cluster.local:3000
    clientID: "client-id-to-update"
    clientSecret: "client-secret-to-update"

server:
  host: drone.local
  adminUser: "gitea_admin"
  
persistence:
  enabled: true
  size: 1Gi

ingress:
  enabled: true
  className: nginx
  hosts:
    - host: drone.local
      paths:
        - path: /
          pathType: Prefix
EOF

# Nota: Para instalar Drone, primero debes crear una aplicación OAuth en Gitea
# y actualizar los valores clientID y clientSecret en el archivo values.yaml

# Crear script para la configuración
cat > scripts/setup-drone.sh << 'EOF'
#!/bin/bash
set -e

echo "Para continuar, primero debes crear una aplicación OAuth en Gitea."
echo "1. Abre Gitea en tu navegador (configura tu archivo hosts o usa port-forward)"
echo "2. Inicia sesión con las credenciales de administrador"
echo "3. Ve a Site Administration -> Applications"
echo "4. Crea una nueva aplicación OAuth con:"
echo "   - Nombre: Drone"
echo "   - Redirect URL: http://drone.local/login"
echo "5. Anota el Client ID y Client Secret"

read -p "¿Has creado la aplicación OAuth? (s/n): " answer
if [ "$answer" != "s" ]; then
  echo "Configura la aplicación OAuth antes de continuar."
  exit 1
fi

read -p "Ingresa el Client ID: " client_id
read -p "Ingresa el Client Secret: " client_secret

# Actualizar valores
sed -i "s/client-id-to-update/$client_id/g" platform/applications/drone/values.yaml
sed -i "s/client-secret-to-update/$client_secret/g" platform/applications/drone/values.yaml

echo "Valores actualizados. Ahora puedes aplicar la configuración con OpenTofu."
EOF

chmod +x scripts/setup-drone.sh

# Archivo OpenTofu para Drone CI
cat > infrastructure/local/drone.tf << 'EOF'
resource "helm_release" "drone" {
  name       = "drone"
  repository = "https://charts.drone.io"
  chart      = "drone"
  version    = "0.5.0"
  namespace  = kubernetes_namespace.platform.metadata[0].name

  values = [
    file("../../platform/applications/drone/values.yaml")
  ]

  depends_on = [
    helm_release.gitea
  ]
}

resource "helm_release" "drone_runner" {
  name       = "drone-runner-kube"
  repository = "https://charts.drone.io"
  chart      = "drone-runner-kube"
  version    = "0.5.0"
  namespace  = kubernetes_namespace.platform.metadata[0].name

  set {
    name  = "env.DRONE_RPC_HOST"
    value = "drone.${kubernetes_namespace.platform.metadata[0].name}.svc.cluster.local"
  }

  set {
    name  = "env.DRONE_RPC_PROTO"
    value = "http"
  }

  set {
    name  = "env.DRONE_RPC_SECRET"
    value = "secret-to-change"  # Cambiar en entorno real
  }

  depends_on = [
    helm_release.drone
  ]
}
EOF
```

## 6. Sistema de Observabilidad

### 6.1 Instalar stack Prometheus, Grafana y Loki

```bash
# Crear valores para Kube Prometheus Stack
cat > platform/kubernetes/monitoring/values.yaml << 'EOF'
grafana:
  persistence:
    enabled: true
    size: 2Gi
  ingress:
    enabled: true
    ingressClassName: nginx
    hosts:
      - grafana.local

prometheus:
  prometheusSpec:
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: longhorn
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 5Gi

alertmanager:
  alertmanagerSpec:
    storage:
      volumeClaimTemplate:
        spec:
          storageClassName: longhorn
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 1Gi
EOF

# Valores para Loki
cat > platform/kubernetes/monitoring/loki-values.yaml << 'EOF'
loki:
  commonConfig:
    replication_factor: 1
  storage:
    type: filesystem
  auth_enabled: false
  
ingress:
  enabled: true
  ingressClassName: nginx
  hosts:
    - host: loki.local
      paths:
        - path: /
          pathType: Prefix
EOF

# Script de instalación
cat > scripts/install-monitoring.sh << 'EOF'
#!/bin/bash
set -e

echo "Instalando Nginx Ingress Controller..."
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-system --create-namespace

echo "Instalando Prometheus Stack..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  -f platform/kubernetes/monitoring/values.yaml

echo "Instalando Loki..."
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
helm upgrade --install loki grafana/loki-stack \
  --namespace monitoring \
  -f platform/kubernetes/monitoring/loki-values.yaml

echo "Stack de monitoreo instalado correctamente!"
echo "Puedes acceder a Grafana en: http://grafana.local"
echo "Usuario por defecto: admin"
echo "Contraseña por defecto: prom-operator"
EOF

chmod +x scripts/install-monitoring.sh
./scripts/install-monitoring.sh
```

### 6.2 Configurar dashboard para la plataforma

```bash
# Crear dashboard de Grafana para la plataforma
cat > platform/kubernetes/monitoring/platform-dashboard.json << 'EOF'
{
  "annotations": {
    "list": [
      {
        "builtIn": 1,
        "datasource": "-- Grafana --",
        "enable": true,
        "hide": true,
        "iconColor": "rgba(0, 211, 255, 1)",
        "name": "Annotations & Alerts",
        "type": "dashboard"
      }
    ]
  },
  "editable": true,
  "gnetId": null,
  "graphTooltip": 0,
  "id": 10,
  "links": [],
  "panels": [
    {
      "datasource": null,
      "fieldConfig": {
        "defaults": {
          "color": {
            "mode": "thresholds"
          },
          "mappings": [],
          "thresholds": {
            "mode": "absolute",
            "steps": [
              {
                "color": "green",
                "value": null
              },
              {
                "color": "red",
                "value": 80
              }
            ]
          }
        },
        "overrides": []
      },
      "gridPos": {
        "h": 9,
        "w": 12,
        "x": 0,
        "y": 0
      },
      "id": 2,
      "options": {
        "orientation": "auto",
        "reduceOptions": {
          "calcs": [
            "lastNotNull"
          ],
          "fields": "",
          "values": false
        },
        "showThresholdLabels": false,
        "showThresholdMarkers": true
      },
      "pluginVersion": "7.5.5",
      "targets": [
        {
          "expr": "sum(kube_pod_container_resource_requests{namespace=~\"platform|monitoring|security\"}) by (namespace)",
          "interval": "",
          "legendFormat": "",
          "refId": "A"
        }
      ],
      "title": "Recursos por Namespace",
      "type": "gauge"
    }
  ],
  "refresh": "10s",
  "schemaVersion": 27,
  "style": "dark",
  "tags": [],
  "templating": {
    "list": []
  },
  "time": {
    "from": "now-6h",
    "to": "now"
  },
  "timepicker": {},
  "timezone": "",
  "title": "Platform Overview",
  "uid": "platform-overview",
  "version": 1
}
EOF

# Script para importar dashboard
cat > scripts/import-dashboards.sh << 'EOF'
#!/bin/bash
set -e

# Obtener pod de Grafana
GRAFANA_POD=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath="{.items[0].metadata.name}")

# Importar dashboard
kubectl cp platform/kubernetes/monitoring/platform-dashboard.json monitoring/$GRAFANA_POD:/tmp/dashboard.json
kubectl exec -n monitoring $GRAFANA_POD -- curl -X POST -H "Content-Type: application/json" -d @/tmp/dashboard.json http://admin:prom-operator@localhost:3000/api/dashboards/db

echo "Dashboard importado correctamente!"
EOF

chmod +x scripts/import-dashboards.sh
```

## 7. Capa de Seguridad

### 7.1 Instalar Vault para gestión de secretos

```bash
# Crear valores para Vault
cat > platform/applications/vault/values.yaml << 'EOF'
server:
  dev:
    enabled: true  # Solo para desarrollo
  
  standalone:
    enabled: true
  
  dataStorage:
    enabled: true
    size: 1Gi
    storageClass: longhorn
  
  service:
    enabled: true

  ingress:
    enabled: true
    ingressClassName: nginx
    hosts:
      - host: vault.local
        paths:
          - path: /
            pathType: Prefix
EOF

# Archivo OpenTofu para Vault
cat > infrastructure/local/vault.tf << 'EOF'
resource "helm_release" "vault" {
  name       = "vault"
  repository = "https://helm.releases.hashicorp.com"
  chart      = "vault"
  version    = "0.25.0"
  namespace  = kubernetes_namespace.security.metadata[0].name

  values = [
    file("../../platform/applications/vault/values.yaml")
  ]
}

output "vault_service" {
  value = "vault.${kubernetes_namespace.security.metadata[0].name}.svc.cluster.local"
}
EOF

# Aplicar cambios
cd infrastructure/local
tofu apply -auto-approve
cd ../..
```

### 7.2 Configurar OPA para políticas

```bash
# Crear valores para OPA/Gatekeeper
cat > platform/kubernetes/opa/values.yaml << 'EOF'
replicas: 1
controllerManager:
  resources:
    limits:
      cpu: 1000m
      memory: 512Mi
    requests:
      cpu: 100m
      memory: 256Mi
audit:
  resources:
    limits:
      cpu: 1000m
      memory: 512Mi
    requests:
      cpu: 100m
      memory: 256Mi
EOF

# Crear una política de ejemplo para OPA
cat > policies/opa/require-labels.yaml << 'EOF'
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: requiredlabels
spec:
  crd:
    spec:
      names:
        kind: RequiredLabels
      validation:
        openAPIV3Schema:
          type: object
          properties:
            labels:
              type: array
              items:
                type: string
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package requiredlabels

        violation[{"msg": msg}] {
          provided := {label | input.review.object.metadata.labels[label]}
          required := {label | label := input.parameters.labels[_]}
          missing := required - provided
          count(missing) > 0
          msg := sprintf("Missing required labels: %v", [missing])
        }
EOF

# Instalar OPA/Gatekeeper
cat > scripts/install-opa.sh << 'EOF'
#!/bin/bash
set -e

echo "Instalando OPA Gatekeeper..."
helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts
helm repo update
helm upgrade --install gatekeeper gatekeeper/gatekeeper \
  --namespace security \
  -f platform/kubernetes/opa/values.yaml

echo "Esperando que OPA esté listo..."
kubectl -n security wait --for=condition=Ready pod -l control-plane=controller-manager --timeout=120s

echo "Aplicando política de ejemplo..."
kubectl apply -f policies/opa/require-labels.yaml

echo "OPA/Gatekeeper instalado correctamente!"
EOF

chmod +x scripts/install-opa.sh
./scripts/install-opa.