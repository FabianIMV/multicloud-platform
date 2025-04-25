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

## 7. Capa de Seguridad (continuación)

### 7.2 Configurar OPA para políticas (continuación)

```bash
# Ejecutar script de instalación
./scripts/install-opa.sh

# Crear una política de aplicación (constraint)
cat > policies/opa/require-app-labels.yaml << 'EOF'
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: RequiredLabels
metadata:
  name: require-app-labels
spec:
  match:
    kinds:
      - apiGroups: ["apps"]
        kinds: ["Deployment", "StatefulSet"]
    namespaces:
      - "platform"
      - "monitoring"
  parameters:
    labels: ["app", "environment"]
EOF

kubectl apply -f policies/opa/require-app-labels.yaml
```

### 7.3 Configurar Cert-Manager para TLS

```bash
# Crear valores para cert-manager
cat > platform/kubernetes/cert-manager/values.yaml << 'EOF'
installCRDs: true
replicaCount: 1
extraArgs:
  - --dns01-recursive-nameservers=8.8.8.8:53,1.1.1.1:53
prometheus:
  enabled: true
  servicemonitor:
    enabled: true
EOF

# Script de instalación
cat > scripts/install-cert-manager.sh << 'EOF'
#!/bin/bash
set -e

echo "Instalando Cert-Manager..."
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace security \
  -f platform/kubernetes/cert-manager/values.yaml

echo "Esperando que cert-manager esté listo..."
kubectl -n security wait --for=condition=Ready pod -l app.kubernetes.io/name=cert-manager --timeout=120s

echo "Configurando emisor de certificados autofirmados..."
cat > platform/kubernetes/cert-manager/self-signed-issuer.yaml << 'EOT'
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: selfsigned-ca
  namespace: security
spec:
  isCA: true
  commonName: local-ca
  secretName: root-secret
  privateKey:
    algorithm: ECDSA
    size: 256
  issuerRef:
    name: selfsigned-issuer
    kind: ClusterIssuer
    group: cert-manager.io
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: local-ca-issuer
spec:
  ca:
    secretName: root-secret
EOT

kubectl apply -f platform/kubernetes/cert-manager/self-signed-issuer.yaml

echo "Cert-Manager instalado correctamente con emisor autofirmado!"
EOF

chmod +x scripts/install-cert-manager.sh
./scripts/install-cert-manager.sh
```

## 8. Documentación y Diagramas

### 8.1 Crear diagrama de arquitectura

Para crear la documentación de la arquitectura, utilizaremos PlantUML o Mermaid para generar diagramas mediante código. Esto facilita mantener los diagramas actualizados al mismo tiempo que el código.

```bash
# Crear directorio para diagramas
mkdir -p docs/diagrams

# Crear un diagrama de arquitectura (usando sintaxis Mermaid)
cat > docs/diagrams/architecture.md << 'EOF'
# Diagrama de Arquitectura

## Arquitectura Global

```mermaid
graph TD
    subgraph "Multi-Cloud Platform"
        subgraph "Local Dev Environment"
            K3D[K3d Cluster]
            K3D --> LocalStorage[Longhorn Storage]
            K3D --> LocalNetworking[Cilium Networking]
            
            subgraph "Core Services"
                MinIO[MinIO S3 Compatible]
                Gitea[Gitea Git Server]
                Drone[Drone CI]
            end
            
            subgraph "Observability"
                Prometheus[Prometheus]
                Grafana[Grafana Dashboards]
                Loki[Loki Logs]
            end
            
            subgraph "Security"
                Vault[HashiCorp Vault]
                OPA[Open Policy Agent]
                CertManager[Cert Manager]
            end
            
            LocalStorage --> MinIO
            LocalNetworking --> K3D
            K3D --> CoreServices
            K3D --> Observability
            K3D --> Security
        end
        
        subgraph "AWS Environment"
            AWSVPC[VPC]
            AWSEC2[EC2 Instances]
            AWSS3[S3 Buckets]
            
            AWSVPC --> AWSEC2
            AWSEC2 --> K3sCluster[K3s Cluster]
            AWSS3 --> ObjectStorage[Object Storage]
        end
        
        subgraph "Migration Path"
            OpenTofu[OpenTofu IaC]
            OpenTofu --> LocalConfig[Local Config]
            OpenTofu --> CloudConfig[Cloud Config]
            
            MigrationStrategy[Migration Strategy]
            LocalConfig --> MigrationStrategy
            MigrationStrategy --> CloudConfig
        end
    end
```

## Componentes detallados

```mermaid
graph LR
    subgraph "Kubernetes Platform"
        K8sAPI[Kubernetes API]
        
        subgraph "Networking"
            Cilium[Cilium]
            Ingress[Nginx Ingress]
        end
        
        subgraph "Storage"
            Longhorn[Longhorn]
            MinIO[MinIO]
        end
        
        subgraph "DevOps"
            Gitea[Gitea]
            Drone[Drone CI]
        end
        
        subgraph "Observability"
            Prometheus[Prometheus]
            Grafana[Grafana]
            Loki[Loki]
            AlertManager[Alert Manager]
        end
        
        subgraph "Security"
            Vault[Vault]
            OPA[OPA/Gatekeeper]
            CertManager[Cert Manager]
        end
        
        K8sAPI --> Networking
        K8sAPI --> Storage
        K8sAPI --> DevOps
        K8sAPI --> Observability
        K8sAPI --> Security
        
        Drone --> K8sAPI
        Gitea --> Drone
        Prometheus --> AlertManager
        Grafana --> Prometheus
        Grafana --> Loki
        OPA --> K8sAPI
    end
```
EOF
```

### 8.2 Crear documentación de la arquitectura

```bash
# Crear documentación principal
cat > docs/architecture.md << 'EOF'
# Arquitectura Multi-Cloud Platform

## Visión general

Esta plataforma está diseñada para funcionar sin costo en un entorno local, con la capacidad de migrar fácilmente a proveedores cloud cuando sea necesario. La arquitectura se enfoca en componentes open source y está estructurada en capas:

1. **Infraestructura**: Kubernetes ligero (K3d/K3s) con abstracciones para múltiples nubes
2. **Plataforma básica**: Networking (Cilium), almacenamiento (Longhorn, MinIO)
3. **DevOps**: Control de versiones (Gitea) y CI/CD (Drone)
4. **Observabilidad**: Monitoreo (Prometheus, Grafana) y logging (Loki)
5. **Seguridad**: Secretos (Vault), políticas (OPA) y certificados (cert-manager)

## Enfoque Cloud-Native

Toda la plataforma sigue principios cloud-native:

- **Infraestructura como código**: Todo definido con OpenTofu
- **Inmutabilidad**: Componentes se reemplazan, no se modifican
- **Observabilidad integrada**: Monitoreo y logging desde el diseño
- **Seguridad por defecto**: Políticas y autenticación en cada nivel

## Componentes principales

### Kubernetes (K3d/K3s)

K3d para desarrollo local y K3s para despliegue en cloud. Ambos son distribuciones ligeras de Kubernetes que requieren menos recursos que Kubernetes completo, lo que los hace ideales para desarrollo y pequeños entornos productivos.

### Cilium

Proporciona networking, security y observabilidad basadas en eBPF. Ventajas:
- Políticas de red avanzadas
- Mejores performance que soluciones tradicionales
- Observabilidad detallada del tráfico

### Longhorn y MinIO

Longhorn proporciona almacenamiento persistente para Kubernetes, mientras que MinIO ofrece almacenamiento compatible con S3. Esto permite:
- Mantener consistencia de APIs entre local y cloud
- Migración sencilla de datos
- Portabilidad de configuraciones

### Gitea y Drone CI

Gitea proporciona un servidor Git completo, mientras que Drone CI ofrece pipelines de CI/CD:
- Completa integración entre ambos
- Configuración como código para pipelines
- Ejecución de pipelines en Kubernetes

### Prometheus, Grafana y Loki

Stack de observabilidad completo:
- Métricas con Prometheus
- Visualización con Grafana
- Logs centralizados con Loki

### Vault, OPA y Cert-Manager

Capa de seguridad:
- Gestión de secretos con Vault
- Políticas como código con OPA/Gatekeeper
- Gestión automatizada de certificados con Cert-Manager

## Estrategia de migración a cloud

La plataforma está diseñada para permitir una migración sencilla a entornos cloud:

1. **Abstracciones de infraestructura**: Los módulos de OpenTofu permiten cambiar el proveedor subyacente
2. **APIs consistentes**: Las mismas APIs se usan en local y cloud (S3, Kubernetes, etc.)
3. **Exportación de estado**: Los datos pueden exportarse y migrarse fácilmente
4. **Configuración separada**: La configuración específica de cada entorno se mantiene separada

## Consideraciones de seguridad

- Entorno local usa configuraciones simplificadas por defecto
- Para producción, habilitar características adicionales de seguridad
- Rotar credenciales y usar gestión de secretos apropiada

## Escalabilidad

La plataforma puede escalar horizontal y verticalmente:
- Añadir más nodos al cluster
- Escalar componentes individuales
- Migrar a proveedores cloud para mayor capacidad
EOF
```

### 8.3 Crear documentos ADR (Architecture Decision Records)

```bash
# Crear un ADR de ejemplo
cat > docs/decision-records/0001-kubernetes-distribution.md << 'EOF'
# ADR 0001: Selección de distribución Kubernetes

## Estado

Aceptado

## Contexto

Necesitamos seleccionar una distribución de Kubernetes que funcione tanto para desarrollo local como para despliegue en cloud, con énfasis en bajo consumo de recursos y facilidad de uso.

## Opciones consideradas

1. **Kubernetes completo**
   - Pros: Completamente compatible con todas las características
   - Contras: Alto consumo de recursos, complejo para desarrollo local

2. **K3s/K3d**
   - Pros: Ligero, rápido de iniciar, certificado CNCF
   - Contras: Algunas características avanzadas no disponibles

3. **MicroK8s**
   - Pros: Buena integración con Ubuntu, add-ons
   - Contras: Menos optimizado para entornos muy pequeños

4. **Kind**
   - Pros: Diseñado para testing, liviano
   - Contras: Menos orientado a producción

## Decisión

Utilizaremos K3d para desarrollo local y K3s para despliegue en cloud por las siguientes razones:

1. K3d permite ejecutar K3s en contenedores Docker, lo que facilita el desarrollo local
2. K3s es una distribución certificada CNCF que puede utilizarse en producción
3. Ambas opciones consumen menos recursos que Kubernetes completo
4. Mantienen compatibilidad con las APIs estándar de Kubernetes
5. Permiten una experiencia consistente entre desarrollo y producción

## Consecuencias

- Algunas características muy específicas de Kubernetes podrían no estar disponibles
- Simplifica enormemente el despliegue y mantenimiento
- Reduce los requisitos de recursos, especialmente en desarrollo
- Facilita la migración entre entornos
EOF

# Crear otro ADR
cat > docs/decision-records/0002-multi-cloud-abstraction.md << 'EOF'
# ADR 0002: Abstracción Multi-Cloud

## Estado

Aceptado

## Contexto

Necesitamos diseñar una arquitectura que funcione localmente sin costo pero que sea fácilmente migrabe a múltiples proveedores cloud. Esto requiere un diseño que abstraiga las diferencias entre proveedores y permita una transición suave.

## Opciones consideradas

1. **Abstracción completa de proveedores**
   - Pros: Máxima portabilidad
   - Contras: Funcionalidad reducida al mínimo común denominador

2. **Configuración específica por proveedor**
   - Pros: Aprovecha características específicas de cada proveedor
   - Contras: Código duplicado, baja portabilidad

3. **Abstracción con extensiones específicas**
   - Pros: Balance entre portabilidad y funcionalidad
   - Contras: Mayor complejidad en la implementación

## Decisión

Adoptaremos un enfoque de "Abstracción con extensiones específicas" que:

1. Define interfaces comunes para funcionalidades core (almacenamiento, networking, compute)
2. Implementa estas interfaces para cada proveedor (local, AWS, etc.)
3. Permite extensiones específicas del proveedor cuando sean necesarias
4. Utiliza OpenTofu para gestionar todas las configuraciones

## Consecuencias

- Mayor complejidad inicial en el diseño de módulos
- Mejor portabilidad a largo plazo
- Capacidad de aprovechar características específicas cuando sea necesario
- Facilita pruebas locales antes de desplegar en cloud
EOF
```

## 9. Migración a AWS

### 9.1 Preparación para AWS

```bash
# Crear módulos AWS específicos
mkdir -p infrastructure/aws

# Crear archivo de proveedor AWS
cat > infrastructure/aws/providers.tf << 'EOF'
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.21"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.10"
    }
  }
}

provider "aws" {
  region = var.region
  
  default_tags {
    tags = {
      Environment = var.environment
      Project     = "multi-cloud-platform"
      ManagedBy   = "opentofu"
    }
  }
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}
EOF

# Variables de AWS
cat > infrastructure/aws/variables.tf << 'EOF'
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.small"  # Instancia incluida en free tier
}

variable "k3s_token" {
  description = "K3s cluster token"
  type        = string
  default     = "mysecuretoken"  # Cambiar en producción
  sensitive   = true
}
EOF

# Configuración de VPC
cat > infrastructure/aws/vpc.tf << 'EOF'
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.environment}-vpc"
  }
}

resource "aws_subnet" "public" {
  count                   = length(var.availability_zones)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.environment}-public-${var.availability_zones[count.index]}"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.environment}-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.environment}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
EOF

# Configuración de grupo de seguridad
cat > infrastructure/aws/security.tf << 'EOF'
resource "aws_security_group" "k3s" {
  name        = "${var.environment}-k3s-sg"
  description = "Security group for K3s cluster"
  vpc_id      = aws_vpc.main.id

  # SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Restringe este rango en producción
  }

  # Kubernetes API
  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Restringe este rango en producción
  }

  # HTTP/HTTPS
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Comunicación interna del cluster
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  # Todo el tráfico saliente
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment}-k3s-sg"
  }
}
EOF

# Configuración EC2
cat > infrastructure/aws/ec2.tf << 'EOF'
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_key_pair" "deployer" {
  key_name   = "${var.environment}-deployer-key"
  public_key = file("~/.ssh/id_rsa.pub")  # Asegúrate de que esta clave exista

  tags = {
    Name = "${var.environment}-deployer-key"
  }
}

resource "aws_instance" "k3s_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [aws_security_group.k3s.id]
  subnet_id              = aws_subnet.public[0].id
  
  root_block_device {
    volume_size = 20
    volume_type = "gp2"
  }
  
  user_data = <<-EOF
    #!/bin/bash
    export K3S_TOKEN=${var.k3s_token}
    curl -sfL https://get.k3s.io | sh -s - server \
      --no-deploy traefik \
      --write-kubeconfig-mode 644
  EOF
  
  tags = {
    Name = "${var.environment}-k3s-server"
  }
}

resource "aws_instance" "k3s_agent" {
  count                  = 1  # Solo un agente en Free Tier
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [aws_security_group.k3s.id]
  subnet_id              = aws_subnet.public[1 % length(aws_subnet.public)].id
  
  root_block_device {
    volume_size = 20
    volume_type = "gp2"
  }
  
  user_data = <<-EOF
    #!/bin/bash
    export K3S_TOKEN=${var.k3s_token}
    export K3S_URL=https://${aws_instance.k3s_server.private_ip}:6443
    curl -sfL https://get.k3s.io | sh -s - agent
  EOF
  
  depends_on = [aws_instance.k3s_server]
  
  tags = {
    Name = "${var.environment}-k3s-agent-${count.index}"
  }
}

# Salidas
output "k3s_server_public_ip" {
  value = aws_instance.k3s_server.public_ip
}

output "k3s_agent_public_ips" {
  value = aws_instance.k3s_agent[*].public_ip
}
EOF
```

### 9.2 Crear script para recuperar kubeconfig

```bash
# Script para obtener kubeconfig desde AWS
cat > scripts/get-aws-kubeconfig.sh << 'EOF'
#!/bin/bash
set -e

# Verificar que OpenTofu ya ha sido aplicado
if [ ! -f infrastructure/aws/terraform.tfstate ]; then
  echo "Primero debes aplicar la configuración de OpenTofu en AWS"
  exit 1
fi

# Obtener IP del servidor K3s
SERVER_IP=$(cd infrastructure/aws && tofu output -raw k3s_server_public_ip)
echo "Servidor K3s: $SERVER_IP"

# Crear directorio para kubeconfig
mkdir -p ~/.kube

# Copiar kubeconfig desde el servidor
echo "Copiando kubeconfig desde el servidor..."
scp -o StrictHostKeyChecking=no ubuntu@$SERVER_IP:/etc/rancher/k3s/k3s.yaml ~/.kube/aws-config

# Actualizar servidor en kubeconfig
sed -i "s/127.0.0.1/$SERVER_IP/g" ~/.kube/aws-config

# Exportar KUBECONFIG
echo "export KUBECONFIG=~/.kube/aws-config" >> ~/.bashrc
export KUBECONFIG=~/.kube/aws-config

echo "Kubeconfig configurado correctamente!"
echo "Para usar: export KUBECONFIG=~/.kube/aws-config"
echo "Verificando nodos..."
kubectl get nodes
EOF

chmod +x scripts/get-aws-kubeconfig.sh
```

### 9.3 Migrar configuración desde local a AWS

```bash
# Script para migrar configuración
cat > scripts/migrate-to-aws.sh << 'EOF'
#!/bin/bash
set -e

echo "Este script migrará la plataforma desde local a AWS."
echo "Asegúrate de tener aplicada la configuración de AWS y configurado el kubeconfig."

# Verificar kubeconfig
if [ -z "$KUBECONFIG" ] || [ ! -f "$KUBECONFIG" ]; then
  echo "KUBECONFIG no configurado o archivo no encontrado."
  echo "Ejecuta primero scripts/get-aws-kubeconfig.sh"
  exit 1
fi

# Verificar conexión al cluster AWS
if ! kubectl get nodes &> /dev/null; then
  echo "No se puede conectar al cluster de AWS. Verifica tu kubeconfig."
  exit 1
fi

echo "Migrando configuración a AWS..."

# Crear namespaces
kubectl create namespace platform --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace security --dry-run=client -o yaml | kubectl apply -f -

# Instalar Nginx Ingress
echo "Instalando Nginx Ingress..."
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-system --create-namespace

# Instalar stack de monitoreo
echo "Instalando stack de monitoreo..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  -f platform/kubernetes/monitoring/values.yaml

helm upgrade --install loki grafana/loki-stack \
  --namespace monitoring \
  -f platform/kubernetes/monitoring/loki-values.yaml

# Instalar MinIO
echo "Instalando MinIO..."
helm repo add minio https://charts.min.io/
helm repo update
helm upgrade --install minio minio/minio \
  --namespace platform \
  -f platform/applications/minio/values.yaml

# Instalar Longhorn
echo "Instalando Longhorn..."
kubectl create namespace longhorn-system --dry-run=client -o yaml | kubectl apply -f -
helm repo add longhorn https://charts.longhorn.io
helm repo update
helm upgrade --install longhorn longhorn/longhorn \
  --namespace longhorn-system \
  -f platform/kubernetes/storage/values.yaml

# Establecer Longhorn como clase de almacenamiento por defecto
kubectl patch storageclass longhorn -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

echo "Migración básica completada. Ahora puedes continuar con la instalación de Gitea, Drone, etc."
echo "Recuerda actualizar tus DNS o archivo hosts para apuntar a la nueva IP de AWS."
EOF

chmod +x scripts/migrate-to-aws.sh
```

## 10. Extensiones Avanzadas

### 10.1 Mini-aplicación de ejemplo: Sistema de Procesamiento de Datos

Para completar tu proyecto, puedes implementar una mini-aplicación que demuestre las capacidades de la plataforma:

```bash
# Crear directorio de la aplicación
mkdir -p demo-app

# Crear archivo docker-compose para desarrollo local
cat > demo-app/docker-compose.yml << 'EOF'
version: '3'

services:
  postgres:
    image: postgres:14
    environment:
      POSTGRES_PASSWORD: postgres
      POSTGRES_USER: postgres
      POSTGRES_DB: demo
    ports:
      - "5432:5432"
    volumes:
      - postgres-data:/var/lib/postgresql/data

  redis:
    image: redis:alpine
    ports:
      - "6379:6379"

  api:
    build:
      context: ./api
    ports:
      - "3000:3000"
    environment:
      - DB_HOST=postgres
      - DB_USER=postgres
      - DB_PASS=postgres
      - DB_NAME=demo
      - REDIS_HOST=redis
    depends_on:
      - postgres
      - redis

  worker:
    build:
      context: ./worker
    environment:
      - REDIS_HOST=redis
    depends_on:
      - redis

volumes:
  postgres-data:
EOF

# Estructura básica de la API
mkdir -p demo-app/api
cat > demo-app/api/Dockerfile << 'EOF'
FROM node:16-alpine

WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm install

COPY . .

EXPOSE 3000
CMD ["node", "index.js"]
EOF

cat > demo-app/api/package.json << 'EOF'
{
  "name": "demo-api",
  "version": "1.0.0",
  "main": "index.js",
  "dependencies": {
    "express": "^4.18.2",
    "pg": "^8.11.0",
    "redis": "^4.6.6"
  }
}
EOF

cat > demo-app/api/index.js << 'EOF'
const express = require('express');
const { Pool } = require('pg');
const redis = require('redis');

const app = express();
const port = 3000;

// Conexión a Postgres
const pool = new Pool({
  host: process.env.DB_HOST || 'localhost',
  user: process.env.DB_USER || 'postgres',
  password: process.env.DB_PASS || 'postgres',
  database: process.env.DB_NAME || 'demo',
});

// Conexión a Redis
const redisClient = redis.createClient({
  url: `redis://${process.env.REDIS_HOST || 'localhost'}:6379`
});

(async () => {
  await redisClient.connect();
  
  // Crear tabla si no existe
  await pool.query(`
    CREATE TABLE IF NOT EXISTS messages (
      id SERIAL PRIMARY KEY,
      content TEXT NOT NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
  `);
})();

app.use(express.json());

# Implementación Multi-Cloud con OpenTofu: Versión sin costo (Parte 3)

## 10. Extensiones Avanzadas (continuación)

### 10.1 Mini-aplicación de ejemplo (continuación)

Continuamos con el archivo API para nuestra mini-aplicación de demostración:

```javascript
// demo-app/api/index.js (continuación)
app.post('/messages', async (req, res) => {
  try {
    const { content } = req.body;
    
    if (!content) {
      return res.status(400).json({ error: 'Content is required' });
    }
    
    // Insertar en la base de datos
    const result = await pool.query(
      'INSERT INTO messages (content) VALUES ($1) RETURNING id',
      [content]
    );
    
    const id = result.rows[0].id;
    
    // Publicar mensaje en Redis para procesamiento
    await redisClient.publish('message-queue', JSON.stringify({
      id,
      content,
      timestamp: new Date().toISOString()
    }));
    
    res.status(201).json({ id, content });
  } catch (error) {
    console.error('Error creating message:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Obtener todos los mensajes
app.get('/messages', async (req, res) => {
  try {
    const result = await pool.query('SELECT * FROM messages ORDER BY created_at DESC');
    res.json(result.rows);
  } catch (error) {
    console.error('Error fetching messages:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Endpoint para healthcheck
app.get('/health', (req, res) => {
  res.json({ status: 'ok' });
});

app.listen(port, () => {
  console.log(`API running on port ${port}`);
});
```

Ahora creamos el worker que procesará los mensajes:

```bash
# Estructura del worker
mkdir -p demo-app/worker
cat > demo-app/worker/Dockerfile << 'EOF'
FROM node:16-alpine

WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm install

COPY . .

CMD ["node", "index.js"]
EOF

cat > demo-app/worker/package.json << 'EOF'
{
  "name": "demo-worker",
  "version": "1.0.0",
  "main": "index.js",
  "dependencies": {
    "redis": "^4.6.6"
  }
}
EOF

cat > demo-app/worker/index.js << 'EOF'
const redis = require('redis');

// Conexión a Redis
const redisClient = redis.createClient({
  url: `redis://${process.env.REDIS_HOST || 'localhost'}:6379`
});

const subscriber = redisClient.duplicate();

async function start() {
  await redisClient.connect();
  await subscriber.connect();
  
  console.log('Worker started and connected to Redis');
  
  // Suscribirse al canal de mensajes
  await subscriber.subscribe('message-queue', (message) => {
    try {
      const data = JSON.parse(message);
      console.log(`Processing message ${data.id}: ${data.content}`);
      
      // Simular procesamiento
      processMessage(data);
    } catch (error) {
      console.error('Error processing message:', error);
    }
  });
}

async function processMessage(data) {
  // Simular procesamiento de datos
  console.log(`Analyzing message: ${data.content}`);
  
  // Añadir un retraso artificial para simular procesamiento
  await new Promise(resolve => setTimeout(resolve, 1000));
  
  // Almacenar resultado en Redis
  const result = {
    id: data.id,
    original: data.content,
    processed: true,
    wordCount: data.content.split(' ').length,
    sentiment: Math.random() > 0.5 ? 'positive' : 'negative',
    processedAt: new Date().toISOString()
  };
  
  await redisClient.set(`result:${data.id}`, JSON.stringify(result));
  console.log(`Processed message ${data.id}`);
}

start().catch(console.error);
EOF
```

Ahora definimos el manifiesto Kubernetes para desplegar la aplicación:

```bash
# Manifiestos Kubernetes
mkdir -p demo-app/kubernetes

# ConfigMap
cat > demo-app/kubernetes/configmap.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: demo-app-config
  namespace: platform
data:
  DB_HOST: postgres
  DB_USER: postgres
  DB_NAME: demo
  REDIS_HOST: redis
EOF

# Secret
cat > demo-app/kubernetes/secret.yaml << 'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: demo-app-secret
  namespace: platform
type: Opaque
data:
  DB_PASS: cG9zdGdyZXM=  # 'postgres' en base64
EOF

# PostgreSQL
cat > demo-app/kubernetes/postgres.yaml << 'EOF'
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
  namespace: platform
spec:
  serviceName: postgres
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
        - name: postgres
          image: postgres:14
          ports:
            - containerPort: 5432
          env:
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: demo-app-secret
                  key: DB_PASS
            - name: POSTGRES_USER
              valueFrom:
                configMapKeyRef:
                  name: demo-app-config
                  key: DB_USER
            - name: POSTGRES_DB
              valueFrom:
                configMapKeyRef:
                  name: demo-app-config
                  key: DB_NAME
          volumeMounts:
            - name: postgres-data
              mountPath: /var/lib/postgresql/data
          resources:
            requests:
              memory: "256Mi"
              cpu: "100m"
            limits:
              memory: "512Mi"
              cpu: "500m"
  volumeClaimTemplates:
    - metadata:
        name: postgres-data
      spec:
        accessModes: [ "ReadWriteOnce" ]
        resources:
          requests:
            storage: 1Gi
---
apiVersion: v1
kind: Service
metadata:
  name: postgres
  namespace: platform
spec:
  selector:
    app: postgres
  ports:
    - port: 5432
      targetPort: 5432
EOF

# Redis
cat > demo-app/kubernetes/redis.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis
  namespace: platform
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
    spec:
      containers:
        - name: redis
          image: redis:alpine
          ports:
            - containerPort: 6379
          resources:
            requests:
              memory: "128Mi"
              cpu: "100m"
            limits:
              memory: "256Mi"
              cpu: "200m"
---
apiVersion: v1
kind: Service
metadata:
  name: redis
  namespace: platform
spec:
  selector:
    app: redis
  ports:
    - port: 6379
      targetPort: 6379
EOF

# API
cat > demo-app/kubernetes/api.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo-api
  namespace: platform
spec:
  replicas: 2
  selector:
    matchLabels:
      app: demo-api
  template:
    metadata:
      labels:
        app: demo-api
    spec:
      containers:
        - name: api
          image: ${DOCKER_REGISTRY}/demo-api:latest
          imagePullPolicy: Always
          ports:
            - containerPort: 3000
          env:
            - name: DB_HOST
              valueFrom:
                configMapKeyRef:
                  name: demo-app-config
                  key: DB_HOST
            - name: DB_USER
              valueFrom:
                configMapKeyRef:
                  name: demo-app-config
                  key: DB_USER
            - name: DB_PASS
              valueFrom:
                secretKeyRef:
                  name: demo-app-secret
                  key: DB_PASS
            - name: DB_NAME
              valueFrom:
                configMapKeyRef:
                  name: demo-app-config
                  key: DB_NAME
            - name: REDIS_HOST
              valueFrom:
                configMapKeyRef:
                  name: demo-app-config
                  key: REDIS_HOST
          readinessProbe:
            httpGet:
              path: /health
              port: 3000
            initialDelaySeconds: 5
            periodSeconds: 10
          resources:
            requests:
              memory: "128Mi"
              cpu: "100m"
            limits:
              memory: "256Mi"
              cpu: "200m"
---
apiVersion: v1
kind: Service
metadata:
  name: demo-api
  namespace: platform
spec:
  selector:
    app: demo-api
  ports:
    - port: 80
      targetPort: 3000
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: demo-api-ingress
  namespace: platform
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
    - host: api.demo.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: demo-api
                port:
                  number: 80
EOF

# Worker
cat > demo-app/kubernetes/worker.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo-worker
  namespace: platform
spec:
  replicas: 2
  selector:
    matchLabels:
      app: demo-worker
  template:
    metadata:
      labels:
        app: demo-worker
    spec:
      containers:
        - name: worker
          image: ${DOCKER_REGISTRY}/demo-worker:latest
          imagePullPolicy: Always
          env:
            - name: REDIS_HOST
              valueFrom:
                configMapKeyRef:
                  name: demo-app-config
                  key: REDIS_HOST
          resources:
            requests:
              memory: "128Mi"
              cpu: "100m"
            limits:
              memory: "256Mi"
              cpu: "200m"
EOF
```

### 10.2 Pipeline CI/CD para la aplicación

Ahora crearemos un pipeline para la aplicación con Drone CI:

```bash
# Crear archivo .drone.yml en la aplicación demo
cat > demo-app/.drone.yml << 'EOF'
kind: pipeline
name: demo-app

steps:
  - name: test-api
    image: node:16
    commands:
      - cd api
      - npm install
      - echo "Running tests..."

  - name: test-worker
    image: node:16
    commands:
      - cd worker
      - npm install
      - echo "Running tests..."

  - name: build-api
    image: plugins/docker
    settings:
      registry: registry.localhost
      repo: registry.localhost:5000/demo-api
      tags:
        - latest
        - ${DRONE_COMMIT_SHA:0:8}
      dockerfile: api/Dockerfile
      context: api/
    when:
      branch:
        - main

  - name: build-worker
    image: plugins/docker
    settings:
      registry: registry.localhost
      repo: registry.localhost:5000/demo-worker
      tags:
        - latest
        - ${DRONE_COMMIT_SHA:0:8}
      dockerfile: worker/Dockerfile
      context: worker/
    when:
      branch:
        - main

  - name: deploy-to-k8s
    image: bitnami/kubectl:latest
    commands:
      - sed -i 's#\${DOCKER_REGISTRY}#registry.localhost:5000#g' kubernetes/*.yaml
      - kubectl apply -f kubernetes/configmap.yaml
      - kubectl apply -f kubernetes/secret.yaml
      - kubectl apply -f kubernetes/postgres.yaml
      - kubectl apply -f kubernetes/redis.yaml
      - kubectl apply -f kubernetes/api.yaml
      - kubectl apply -f kubernetes/worker.yaml
    environment:
      KUBECONFIG:
        from_secret: kubeconfig
    when:
      branch:
        - main
EOF
```

### 10.3 Monitoreo específico para la aplicación

Configuraremos un dashboard de Grafana específico para la aplicación:

```bash
# Crear archivo de configuración para ServiceMonitor
cat > demo-app/kubernetes/service-monitor.yaml << 'EOF'
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: demo-api-monitor
  namespace: platform
  labels:
    release: prometheus
spec:
  selector:
    matchLabels:
      app: demo-api
  endpoints:
    - port: http
      path: /metrics
      interval: 15s
  namespaceSelector:
    matchNames:
      - platform
EOF

# Crear configuración para dashboard de Grafana
cat > platform/kubernetes/monitoring/demo-app-dashboard.json << 'EOF'
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
  "id": 11,
  "links": [],
  "panels": [
    {
      "datasource": null,
      "fieldConfig": {
        "defaults": {
          "color": {
            "mode": "palette-classic"
          },
          "custom": {
            "axisLabel": "",
            "axisPlacement": "auto",
            "barAlignment": 0,
            "drawStyle": "line",
            "fillOpacity": 10,
            "gradientMode": "none",
            "hideFrom": {
              "legend": false,
              "tooltip": false,
              "viz": false
            },
            "lineInterpolation": "linear",
            "lineWidth": 1,
            "pointSize": 5,
            "scaleDistribution": {
              "type": "linear"
            },
            "showPoints": "never",
            "spanNulls": true,
            "stacking": {
              "group": "A",
              "mode": "none"
            },
            "thresholdsStyle": {
              "mode": "off"
            }
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
          },
          "unit": "short"
        },
        "overrides": []
      },
      "gridPos": {
        "h": 8,
        "w": 12,
        "x": 0,
        "y": 0
      },
      "id": 2,
      "options": {
        "legend": {
          "calcs": [],
          "displayMode": "list",
          "placement": "bottom"
        },
        "tooltip": {
          "mode": "single"
        }
      },
      "pluginVersion": "7.5.5",
      "targets": [
        {
          "expr": "sum(rate(http_requests_total{namespace=\"platform\", pod=~\"demo-api.*\"}[5m])) by (status)",
          "interval": "",
          "legendFormat": "{{status}}",
          "refId": "A"
        }
      ],
      "title": "API Request Rate",
      "type": "timeseries"
    },
    {
      "datasource": null,
      "fieldConfig": {
        "defaults": {
          "color": {
            "mode": "palette-classic"
          },
          "custom": {
            "axisLabel": "",
            "axisPlacement": "auto",
            "barAlignment": 0,
            "drawStyle": "line",
            "fillOpacity": 10,
            "gradientMode": "none",
            "hideFrom": {
              "legend": false,
              "tooltip": false,
              "viz": false
            },
            "lineInterpolation": "linear",
            "lineWidth": 1,
            "pointSize": 5,
            "scaleDistribution": {
              "type": "linear"
            },
            "showPoints": "never",
            "spanNulls": true,
            "stacking": {
              "group": "A",
              "mode": "none"
            },
            "thresholdsStyle": {
              "mode": "off"
            }
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
          },
          "unit": "s"
        },
        "overrides": []
      },
      "gridPos": {
        "h": 8,
        "w": 12,
        "x": 12,
        "y": 0
      },
      "id": 3,
      "options": {
        "legend": {
          "calcs": [],
          "displayMode": "list",
          "placement": "bottom"
        },
        "tooltip": {
          "mode": "single"
        }
      },
      "pluginVersion": "7.5.5",
      "targets": [
        {
          "expr": "histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket{namespace=\"platform\", pod=~\"demo-api.*\"}[5m])) by (le))",
          "interval": "",
          "legendFormat": "95th percentile",
          "refId": "A"
        },
        {
          "expr": "histogram_quantile(0.50, sum(rate(http_request_duration_seconds_bucket{namespace=\"platform\", pod=~\"demo-api.*\"}[5m])) by (le))",
          "interval": "",
          "legendFormat": "50th percentile",
          "refId": "B"
        }
      ],
      "title": "API Response Time",
      "type": "timeseries"
    }
  ],
  "refresh": "10s",
  "schemaVersion": 27,
  "style": "dark",
  "tags": ["demo-app"],
  "templating": {
    "list": []
  },
  "time": {
    "from": "now-1h",
    "to": "now"
  },
  "timepicker": {},
  "timezone": "",
  "title": "Demo App Dashboard",
  "uid": "demo-app",
  "version": 1
}
EOF
```

## 11. Consideraciones Finales y Mejores Prácticas

### 11.1 Optimizaciones para entorno sin costo

```bash
# Crear guía de optimizaciones
cat > docs/zero-cost-optimizations.md << 'EOF'
# Optimizaciones para Entorno Sin Costo

Esta guía proporciona recomendaciones para mantener tu plataforma sin costos y optimizar recursos.

## Recursos del Host

### Requisitos mínimos recomendados
- **CPU**: 2 núcleos
- **RAM**: 4 GB
- **Almacenamiento**: 20 GB

### Reducir consumo de recursos

1. **Configurar limits estrictos**
   - Todos los componentes tienen configurados límites de CPU y memoria
   - Mantén CPU request por debajo de 1 core para la mayoría de servicios

2. **Escalado adecuado**
   - Usa 1 réplica para la mayoría de servicios en desarrollo
   - Escala solo los componentes críticos

3. **Hibernación automática**
   - Configura los clusters para apagarse cuando no estén en uso
   - Usa scripts para reiniciar servicios bajo demanda

## Transición a Cloud

### AWS Free Tier
- **EC2**: t2.micro (1 vCPU, 1 GB RAM) - 750 horas gratis/mes por 12 meses
- **S3**: 5 GB de almacenamiento por 12 meses
- **RDS**: db.t2.micro (750 horas/mes) por 12 meses

### Oracle Cloud Siempre Gratuito
- **Compute**: 2 VMs con 1/8 OCPU y 1 GB RAM cada una
- **Storage**: 100 GB total
- **Alternativa recomendada**: 4 ARM Ampere A1 cores y 24 GB de RAM

### Estrategias de migración gradual
1. **Enfoque híbrido**: Mantén algunos componentes locales y otros en cloud
2. **Migración selectiva**: Migra primero los componentes más importantes
3. **Usar créditos estratégicamente**: Aprovecha los créditos AWS para pruebas de carga

## Mantenimiento y Actualizaciones

### Actualización de componentes
- Actualiza regularmente para aprovechar mejoras de rendimiento
- Revisa changelog en cada actualización por cambios que afecten al rendimiento

### Monitoreo
- Configura alertas de uso de recursos
- Analiza tendencias de consumo para identificar ineficiencias

### Datos
- Implementa políticas de retención de datos
- Usa compresión donde sea posible
EOF
```

### 11.2 Integración con otros sistemas y extensiones

```bash
# Crear guía de extensiones
cat > docs/extensions.md << 'EOF'
# Extensiones y Sistemas Adicionales

Esta guía cubre extensiones opcionales que puedes añadir a la plataforma.

## Sistemas de Mensajería

### RabbitMQ
```yaml
# Valores básicos para RabbitMQ
image: rabbitmq:3.9-management-alpine
persistence:
  enabled: true
  size: 1Gi
resources:
  requests:
    memory: 256Mi
    cpu: 100m
  limits:
    memory: 512Mi
    cpu: 500m
replicas: 1  # Para desarrollo
```

### NATS (Alternativa Ligera)
```yaml
# Valores básicos para NATS
nats:
  image: nats:2.8.4-alpine
  jetstream:
    enabled: true
    memStorage:
      enabled: true
      size: 1Gi
  resources:
    requests:
      memory: 128Mi
      cpu: 100m
    limits:
      memory: 256Mi
      cpu: 200m
```

## Bases de Datos

### PostgreSQL
La configuración ya está incluida en la mini-app. Para otros casos:

```yaml
# Valores optimizados
resources:
  requests:
    memory: 256Mi
    cpu: 100m
  limits:
    memory: 512Mi
    cpu: 500m
persistence:
  size: 1Gi
```

### Redis
La configuración ya está incluida en la mini-app. Para otros casos:

```yaml
# Valores optimizados
resources:
  requests:
    memory: 128Mi
    cpu: 50m
  limits:
    memory: 256Mi
    cpu: 200m
```

## Herramientas de Desarrollo

### JupyterHub para Data Science
```yaml
# Valores básicos para JupyterHub
hub:
  resources:
    requests:
      cpu: 200m
      memory: 512Mi
    limits:
      cpu: 1
      memory: 1Gi
singleuser:
  memory:
    limit: 1G
    guarantee: 512M
  cpu:
    limit: 1
    guarantee: 0.5
```

### CodeServer (VS Code en el Navegador)
```yaml
# Configuración básica
image: codercom/code-server:latest
resources:
  requests:
    memory: 512Mi
    cpu: 500m
  limits:
    memory: 1Gi
    cpu: 1
persistence:
  enabled: true
  size: 1Gi
```

## APIs y Herramientas de Integración

### Kong API Gateway
```yaml
# Configuración optimizada
resources:
  requests:
    memory: 256Mi
    cpu: 100m
  limits:
    memory: 512Mi
    cpu: 500m
postgresql:
  enabled: false  # Usar PostgreSQL compartido
```

### Elastic Stack (ELK)
Alternativa a Loki para entornos más exigentes:

```yaml
# Configuración mínima
elasticsearch:
  replicas: 1
  resources:
    requests:
      cpu: 500m
      memory: 1Gi
    limits:
      cpu: 1
      memory: 2Gi
kibana:
  resources:
    requests:
      cpu: 100m
      memory: 512Mi
    limits:
      cpu: 500m
      memory: 1Gi
```
EOF
```

### 11.3 Limpieza y troubleshooting

```bash
# Crear script de limpieza
cat > scripts/cleanup.sh << 'EOF'
#!/bin/bash
set -e

echo "Este script limpiará todos los recursos del cluster K3d local."
echo "ADVERTENCIA: Esto eliminará TODOS los datos. Esta acción no se puede deshacer."
read -p "¿Estás seguro de que deseas continuar? (s/N): " confirm

if [[ $confirm != "s" && $confirm != "S" ]]; then
  echo "Operación cancelada."
  exit 0
fi

echo "Eliminando namespaces y recursos..."

# Eliminar namespaces
kubectl delete namespace platform monitoring security longhorn-system ingress-system --ignore-not-found

# Eliminar PVs
kubectl delete pv --all

# Esperar que se completen las eliminaciones
echo "Esperando que se completen las eliminaciones..."
sleep 10

echo "Eliminando cluster K3d..."
k3d cluster delete multi-cloud-cluster

echo "Limpieza completa. Para recrear el entorno, ejecuta los scripts de instalación."
EOF

chmod +x scripts/cleanup.sh

# Crear guía de troubleshooting
cat > docs/troubleshooting.md << 'EOF'
# Guía de Troubleshooting

## Problemas Comunes y Soluciones

### 1. Cluster K3d no inicia correctamente

**Síntoma**: Errores al crear cluster o nodos que no aparecen.

**Soluciones**:
```bash
# Verificar estado de Docker
docker info

# Eliminar y recrear el cluster
k3d cluster delete multi-cloud-cluster
./scripts/create-local-cluster.sh

# Verificar recursos disponibles
free -m
df -h
```

### 2. Problemas con persistencia de datos

**Síntoma**: PVCs en estado Pending, pods que no inician por volúmenes.

**Soluciones**:
```bash
# Verificar StorageClass
kubectl get sc

# Verificar PVCs
kubectl get pvc -A

# Revisar eventos
kubectl get events -A | grep -i volume

# Si usas Longhorn, revisar su estado
kubectl -n longhorn-system get pods
```

### 3. Problemas de networking

**Síntoma**: Servicios no accesibles, problemas con DNS.

**Soluciones**:
```bash
# Verificar servicios y endpoints
kubectl get svc -A
kubectl get endpoints -A

# Probar DNS desde un pod temporal
kubectl run -it --rm debug --image=busybox -- sh
# Dentro del pod:
nslookup kubernetes.default.svc.cluster.local

# Verificar Ingress
kubectl get ingress -A
```

### 4. Problemas de recursos

**Síntoma**: Pods en estado Pending o con reinicios frecuentes.

**Soluciones**:
```bash
# Verificar eventos
kubectl get events -A

# Verificar uso de recursos
kubectl top nodes
kubectl top pods -A

# Descripción detallada de pods
kubectl describe pod <nombre-del-pod> -n <namespace>
```

### 5. Problemas con OpenTofu

**Síntoma**: Errores al aplicar configuraciones.

**Soluciones**:
```bash
# Reiniciar desde cero
cd infrastructure/local
rm -rf .terraform .terraform.lock.hcl terraform.tfstate*
tofu init
tofu apply

# Verificar versiones
tofu version
```

### 6. Problemas con aplicaciones específicas

#### Gitea

```bash
# Verificar estado
kubectl -n platform get pods -l app=gitea
kubectl -n platform describe pod -l app=gitea

# Verificar logs
kubectl -n platform logs -l app=gitea
```

#### MinIO

```bash
# Verificar estado
kubectl -n platform get pods -l app=minio
kubectl -n platform describe pod -l app=minio

# Acceder a la consola
kubectl -n platform port-forward svc/minio-console 9001:9001
# Navega a http://localhost:9001
```

#### Prometheus/Grafana

```bash
# Verificar estado
kubectl -n monitoring get pods

# Acceder a Grafana
kubectl -n monitoring port-forward svc/prometheus-grafana 3000:80
# Navega a http://localhost:3000
```

## Comandos Útiles para Diagnóstico

```bash
# Ver todos los recursos en un namespace
kubectl get all -n <namespace>

# Ver logs de un pod
kubectl logs <pod-name> -n <namespace>

# Ejecutar un shell en un pod
kubectl exec -it <pod-name> -n <namespace> -- /bin/sh

# Ver información detallada de un recurso
kubectl describe <tipo> <nombre> -n <namespace>

# Ver uso de recursos
kubectl top pods -n <namespace>
```
EOF
```

# Implementación Multi-Cloud con OpenTofu: Versión sin costo (Parte 4)

## 12. Guía de Migración a AWS (continuación)

```markdown
# Guía de Migración a AWS (continuación)

## Prerrequisitos

1. **Cuenta AWS** con créditos disponibles
2. **AWS CLI** configurado con credenciales
3. **OpenTofu** instalado localmente
4. **kubectl** instalado localmente

## Paso 1: Preparar Infraestructura en AWS

### 1.1 Inicializar y aplicar configuración OpenTofu

```bash
# Navegar al directorio de AWS
cd infrastructure/aws

# Inicializar OpenTofu
tofu init

# Ver los cambios que se aplicarán
tofu plan

# Aplicar la configuración
tofu apply
```

Esto creará:
- VPC y subredes
- Grupos de seguridad
- Instancias EC2 con K3s

### 1.2 Obtener kubeconfig

```bash
# Ejecutar script para obtener kubeconfig
../../scripts/get-aws-kubeconfig.sh

# Verificar conexión al cluster
export KUBECONFIG=~/.kube/aws-config
kubectl get nodes
```

## Paso 2: Migrar Datos

### 2.1 Configurar MinIO en AWS

```bash
# Instalar MinIO en el cluster AWS
kubectl create namespace platform --dry-run=client -o yaml | kubectl apply -f -
helm repo add minio https://charts.min.io/
helm repo update
helm install minio minio/minio \
  --namespace platform \
  -f platform/applications/minio/values.yaml
```

### 2.2 Migrar datos entre instancias de MinIO

```bash
# Instalar cliente MinIO (mc)
wget https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x mc
sudo mv mc /usr/local/bin/

# Configurar acceso a MinIO local
mc alias set minio-local http://localhost:9000 admin minioadmin

# Configurar acceso a MinIO AWS (obtener IP del servicio)
MINIO_AWS_IP=$(kubectl get svc -n platform minio -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
mc alias set minio-aws http://$MINIO_AWS_IP:9000 admin minioadmin

# Sincronizar datos
mc mirror minio-local/mybucket minio-aws/mybucket
```

### 2.3 Exportar e importar bases de datos

```bash
# Para bases de datos PostgreSQL
# Exportar desde local
kubectl exec -it -n platform postgres-0 -- pg_dump -U postgres demo > demo-backup.sql

# Importar en AWS
kubectl cp demo-backup.sql platform/postgres-0:/tmp/
kubectl exec -it -n platform postgres-0 -- psql -U postgres -d demo -f /tmp/demo-backup.sql
```

## Paso 3: Desplegar Aplicaciones

### 3.1 Instalar componentes de infraestructura

```bash
# Ejecutar script de migración
./scripts/migrate-to-aws.sh
```

### 3.2 Configurar GitOps

```bash
# Actualizar repositorio con configuración de AWS
git add infrastructure/aws
git commit -m "Add AWS infrastructure configuration"
git push

# Configurar Drone CI para desplegar en AWS
# 1. Crear un secret en Drone con el KUBECONFIG de AWS
# 2. Actualizar pipeline para usar este secret
```

### 3.3 Actualizar DNS

Si tienes un dominio propio:

```bash
# Crear zona en Route53
aws route53 create-hosted-zone --name mydomain.com --caller-reference $(date +%s)

# Obtener la IP pública del ELB/ingress
INGRESS_IP=$(kubectl get svc -n ingress-system ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Crear registro A
aws route53 change-resource-record-sets \
  --hosted-zone-id ZXXXXXXXXX \
  --change-batch '{
    "Changes": [
      {
        "Action": "CREATE",
        "ResourceRecordSet": {
          "Name": "*.mydomain.com",
          "Type": "A",
          "TTL": 300,
          "ResourceRecords": [
            {
              "Value": "'"$INGRESS_IP"'"
            }
          ]
        }
      }
    ]
  }'
```

## Paso 4: Validación y Pruebas

### 4.1 Verificar servicios

```bash
# Verificar que todos los pods estén en estado Running
kubectl get pods -A

# Verificar ingress
kubectl get ingress -A
```

### 4.2 Probar aplicaciones

1. Actualiza tus registros DNS o archivo /etc/hosts para apuntar a la nueva IP
2. Accede a las interfaces web:
   - Grafana: https://grafana.mydomain.com
   - MinIO: https://minio.mydomain.com
   - Gitea: https://gitea.mydomain.com
   - Drone: https://drone.mydomain.com

### 4.3 Ejecutar pruebas de carga

```bash
# Instalar hey (herramienta de pruebas de carga)
go get -u github.com/rakyll/hey

# Ejecutar prueba básica
hey -n 1000 -c 50 https://api.mydomain.com/health
```

## Paso 5: Optimización de Costos para AWS

### 5.1 Optimizar recursos

```bash
# Escalar recursos según necesidad
kubectl scale deployment demo-api --replicas=2 -n platform
kubectl scale deployment demo-worker --replicas=1 -n platform
```

### 5.2 Configurar escalado automático

```yaml
# HorizontalPodAutoscaler ejemplo
apiVersion: autoscaling/v2beta2
kind: HorizontalPodAutoscaler
metadata:
  name: demo-api
  namespace: platform
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: demo-api
  minReplicas: 1
  maxReplicas: 3
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 50
```

### 5.3 Monitorear costos

Configurar AWS Cost Explorer y presupuestos:

```bash
# Crear presupuesto mediante AWS CLI
aws budgets create-budget \
  --account-id $(aws sts get-caller-identity --query 'Account' --output text) \
  --budget '{"BudgetName": "Monthly Cloud Platform Budget", "BudgetLimit": {"Amount": "50", "Unit": "USD"}, "TimeUnit": "MONTHLY", "BudgetType": "COST"}' \
  --notifications-with-subscribers '[{"Notification": {"NotificationType": "ACTUAL", "ComparisonOperator": "GREATER_THAN", "Threshold": 80}, "Subscribers": [{"SubscriptionType": "EMAIL", "Address": "you@example.com"}]}]'
```

## Conclusión

Esta guía te ha proporcionado los pasos principales para migrar tu plataforma multi-cloud desde tu entorno local a AWS. Recuerda:

1. Usa instancias del Free Tier cuando sea posible (t2.micro)
2. Monitorea constantemente tus costos
3. Escala hacia abajo cuando no necesites recursos
4. Usa Spot Instances para trabajos por lotes

Al seguir estas prácticas, podrás aprovechar al máximo tus créditos de AWS mientras ganas experiencia con una plataforma cloud real.
```

## 13. Personalización y Expansión del Proyecto

### 13.1 Ideas para componentes adicionales

```markdown
# Expansión del Proyecto Multi-Cloud

## Componentes Adicionales

### 1. APM (Application Performance Monitoring)

Añade monitoreo avanzado de aplicaciones con Elastic APM o Jaeger:

```yaml
# Valores básicos para Jaeger
allInOne:
  enabled: true
  resources:
    limits:
      memory: 1Gi
      cpu: 500m
    requests:
      memory: 512Mi
      cpu: 256m
storage:
  type: memory  # Para entorno de desarrollo
```

### 2. Serverless Framework

Implementa funcionalidades serverless en tu Kubernetes con OpenFaaS o Knative:

```yaml
# Configuración mínima de OpenFaaS
gateway:
  resources:
    requests:
      memory: "120Mi"
      cpu: "50m"
    limits:
      memory: "250Mi"
      cpu: "200m"
```

### 3. Edge Computing

Añade componentes de edge computing con KubeEdge:

```yaml
# Despliegue básico
cloudCore:
  resources:
    requests:
      cpu: 200m
      memory: 512Mi
    limits:
      cpu: 500m
      memory: 1Gi
```

### 4. ML/AI Toolkit

Incorpora herramientas para Machine Learning:

```yaml
# Kubeflow mínimo
apiServerArgs:
  resources:
    limits:
      cpu: 500m
      memory: 512Mi
    requests:
      cpu: 100m
      memory: 256Mi
```

### 5. Blockchain

Despliega tu propio nodo blockchain:

```yaml
# Configuración para Ethereum light node
geth:
  resources:
    requests:
      cpu: 500m
      memory: 1Gi
    limits:
      cpu: 1
      memory: 2Gi
  syncMode: "light"
```

## Casos de Uso Avanzados

### 1. IoT Platform

Extiende tu plataforma para IoT:

- **MQTT Broker**: Mosquitto o EMQ X
- **Device Management**: Node-RED
- **Time Series Database**: InfluxDB
- **Dashboards**: Grafana

### 2. Media Processing

Crea una plataforma de procesamiento de medios:

- **Streaming**: NGINX-RTMP
- **Transcoding**: FFmpeg workers
- **Storage**: MinIO

### 3. Ecommerce Platform

Implementa una plataforma ecommerce completa:

- **Frontend**: Next.js
- **API**: GraphQL con Apollo
- **Pagos**: Stripe API
- **CMS**: Strapi

### 4. Data Science Environment

Entorno para ciencia de datos:

- **Notebooks**: JupyterHub
- **Processing**: Spark
- **Visualization**: Superset
- **ML Pipeline**: MLflow
```

### 13.2 Integración con otros proveedores cloud

```markdown
# Integración con Otros Proveedores Cloud

## Oracle Cloud Infrastructure (OCI)

Oracle Cloud ofrece una capa gratuita permanente muy generosa, ideal para este proyecto.

### Configuración en OpenTofu

```terraform
terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 4.96.0"
    }
  }
}

provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  region           = var.region
}

# VCN (Virtual Cloud Network)
resource "oci_core_vcn" "main" {
  compartment_id = var.compartment_id
  cidr_block     = "10.0.0.0/16"
  display_name   = "main-vcn"
  dns_label      = "mainvcn"
}

# Internet Gateway
resource "oci_core_internet_gateway" "main" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "main-internet-gateway"
}

# Route Table
resource "oci_core_route_table" "main" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "main-route-table"

  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_internet_gateway.main.id
  }
}

# Subnet
resource "oci_core_subnet" "main" {
  cidr_block        = "10.0.0.0/24"
  compartment_id    = var.compartment_id
  vcn_id            = oci_core_vcn.main.id
  display_name      = "main-subnet"
  route_table_id    = oci_core_route_table.main.id
  security_list_ids = [oci_core_security_list.main.id]
  dns_label         = "main"
}

# Security List
resource "oci_core_security_list" "main" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "main-security-list"

  # SSH
  ingress_security_rules {
    protocol  = "6"  # TCP
    source    = "0.0.0.0/0"
    tcp_options {
      min = 22
      max = 22
    }
  }

  # K3s API
  ingress_security_rules {
    protocol  = "6"  # TCP
    source    = "0.0.0.0/0"
    tcp_options {
      min = 6443
      max = 6443
    }
  }

  # HTTP/HTTPS
  ingress_security_rules {
    protocol  = "6"  # TCP
    source    = "0.0.0.0/0"
    tcp_options {
      min = 80
      max = 80
    }
  }

  ingress_security_rules {
    protocol  = "6"  # TCP
    source    = "0.0.0.0/0"
    tcp_options {
      min = 443
      max = 443
    }
  }

  # Allow all outbound traffic
  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }
}

# Compute Instance
resource "oci_core_instance" "k3s_server" {
  availability_domain = var.availability_domain
  compartment_id      = var.compartment_id
  display_name        = "k3s-server"
  shape               = "VM.Standard.A1.Flex"  # Aprovecha ARM Ampere gratuito

  shape_config {
    ocpus         = 4
    memory_in_gbs = 24
  }

  source_details {
    source_type = "image"
    source_id   = var.image_id  # Oracle Linux 8
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.main.id
    assign_public_ip = true
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data = base64encode(<<-EOF
      #!/bin/bash
      export K3S_TOKEN=${var.k3s_token}
      curl -sfL https://get.k3s.io | sh -s - server \
        --no-deploy traefik \
        --write-kubeconfig-mode 644
    EOF
    )
  }
}
```

### Beneficios de Oracle Cloud

- **Always Free**: 4 OCPUs y 24GB RAM (ARM Ampere A1)
- **No expira**: A diferencia de otros proveedores, el free tier de Oracle no tiene fecha de vencimiento
- **Potente**: Los recursos Ampere A1 son suficientes para ejecutar toda la plataforma

## Google Cloud Platform (GCP)

Google Cloud ofrece $300 en créditos para nuevos usuarios.

### Configuración en OpenTofu

```terraform
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.40.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Red VPC
resource "google_compute_network" "vpc" {
  name                    = "main-vpc"
  auto_create_subnetworks = false
}

# Subred
resource "google_compute_subnetwork" "subnet" {
  name          = "main-subnet"
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  network       = google_compute_network.vpc.id
}

# Firewall rules
resource "google_compute_firewall" "k3s" {
  name    = "k3s-firewall"
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
    ports    = ["22", "6443", "80", "443"]
  }

  allow {
    protocol = "udp"
    ports    = ["8472"]
  }

  source_ranges = ["0.0.0.0/0"]
}

# Permitir comunicación interna
resource "google_compute_firewall" "internal" {
  name    = "internal-firewall"
  network = google_compute_network.vpc.id

  allow {
    protocol = "all"
  }

  source_ranges = ["10.0.0.0/24"]
}

# VM para K3s
resource "google_compute_instance" "k3s_server" {
  name         = "k3s-server"
  machine_type = "e2-medium"  # 2 vCPU, 4GB RAM
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2004-lts"
      size  = 20
    }
  }

  network_interface {
    network    = google_compute_network.vpc.id
    subnetwork = google_compute_subnetwork.subnet.id
    access_config {
      # Ephemeral IP
    }
  }

  metadata = {
    ssh-keys = "ubuntu:${file(var.ssh_public_key)}"
  }

  metadata_startup_script = <<-EOF
    #!/bin/bash
    export K3S_TOKEN=${var.k3s_token}
    curl -sfL https://get.k3s.io | sh -s - server \
      --no-deploy traefik \
      --write-kubeconfig-mode 644
  EOF
}
```

## Microsoft Azure

Azure ofrece un tier gratuito y créditos para nuevos usuarios.

### Configuración en OpenTofu

```terraform
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.30.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Grupo de recursos
resource "azurerm_resource_group" "main" {
  name     = "multi-cloud-platform"
  location = var.location
}

# Red virtual
resource "azurerm_virtual_network" "main" {
  name                = "main-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

# Subred
resource "azurerm_subnet" "main" {
  name                 = "main-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]
}

# IP pública
resource "azurerm_public_ip" "main" {
  name                = "main-public-ip"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Dynamic"
}

# Grupo de seguridad de red
resource "azurerm_network_security_group" "main" {
  name                = "main-nsg"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "K3sAPI"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "6443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "HTTP"
    priority                   = 1003
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "HTTPS"
    priority                   = 1004
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Interfaz de red
resource "azurerm_network_interface" "main" {
  name                = "main-nic"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "main-ip-config"
    subnet_id                     = azurerm_subnet.main.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.main.id
  }
}

# Asociar NSG a NIC
resource "azurerm_network_interface_security_group_association" "main" {
  network_interface_id      = azurerm_network_interface.main.id
  network_security_group_id = azurerm_network_security_group.main.id
}

# Máquina virtual
resource "azurerm_linux_virtual_machine" "k3s_server" {
  name                = "k3s-server"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  size                = "Standard_B2s"  # 2 vCPU, 4GB RAM
  admin_username      = "adminuser"

  network_interface_ids = [
    azurerm_network_interface.main.id,
  ]

  admin_ssh_key {
    username   = "adminuser"
    public_key = file(var.ssh_public_key)
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 30
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  custom_data = base64encode(<<-EOF
    #!/bin/bash
    export K3S_TOKEN=${var.k3s_token}
    curl -sfL https://get.k3s.io | sh -s - server \
      --no-deploy traefik \
      --write-kubeconfig-mode 644
  EOF
  )
}
```
```

### 13.3 Integración con herramientas externas

```markdown
# Integración con Herramientas Externas

## Herramientas de CI/CD

### GitHub Actions (alternativa a Drone CI)

Puedes integrar tu proyecto con GitHub Actions creando un flujo de trabajo:

```yaml
# .github/workflows/deploy.yml
name: Deploy to Kubernetes

on:
  push:
    branches: [ main ]

jobs:
  deploy:
    runs-on: ubuntu-latest

    steps:
    - uses: actions/checkout@v2

    - name: Install OpenTofu
      run: |
        curl -Lo tofu.zip https://github.com/opentofu/opentofu/releases/download/v1.6.0/tofu_1.6.0_linux_amd64.zip
        unzip tofu.zip
        sudo mv tofu /usr/local/bin/

    - name: Install kubectl
      run: |
        curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
        chmod +x kubectl
        sudo mv kubectl /usr/local/bin/

    - name: Setup Kubeconfig
      run: |
        echo "${{ secrets.KUBECONFIG }}" > ~/.kube/config
        chmod 600 ~/.kube/config

    - name: Deploy Infrastructure
      working-directory: ./infrastructure/local
      run: |
        tofu init
        tofu apply -auto-approve

    - name: Deploy Demo App
      run: |
        kubectl apply -f demo-app/kubernetes/
```

### GitLab CI/CD

Si prefieres GitLab, puedes usar la siguiente configuración:

```yaml
# .gitlab-ci.yml
stages:
  - test
  - build
  - deploy

test:
  stage: test
  image: node:16
  script:
    - cd demo-app/api
    - npm install
    - echo "Running tests..."

build:
  stage: build
  image: docker:latest
  services:
    - docker:dind
  script:
    - cd demo-app/api
    - docker build -t $CI_REGISTRY_IMAGE/demo-api:$CI_COMMIT_SHA .
    - docker push $CI_REGISTRY_IMAGE/demo-api:$CI_COMMIT_SHA
  only:
    - main

deploy:
  stage: deploy
  image: bitnami/kubectl:latest
  script:
    - echo "$KUBECONFIG" > ~/.kube/config
    - chmod 600 ~/.kube/config
    - kubectl apply -f demo-app/kubernetes/
  only:
    - main
```

## Monitoreo Externo

### Integración con Datadog

Para integrar Datadog con tu cluster K8s, añade esta configuración:

```yaml
# datadog-values.yaml
datadog:
  apiKey: "YOUR_API_KEY"
  logs:
    enabled: true
    containerCollectAll: true
  apm:
    enabled: true
  processAgent:
    enabled: true
  systemProbe:
    enabled: true
  kubelet:
    tlsVerify: false

agents:
  containers:
    agent:
      resources:
        requests:
          cpu: 200m
          memory: 256Mi
        limits:
          cpu: 400m
          memory: 512Mi
```

Instalación:

```bash
helm repo add datadog https://helm.datadoghq.com
helm repo update
helm install datadog -f datadog-values.yaml datadog/datadog --namespace monitoring
```

### Integración con New Relic

```yaml
# newrelic-values.yaml
global:
  licenseKey: "YOUR_LICENSE_KEY"
  cluster: "multi-cloud-platform"

newrelic-infrastructure:
  enabled: true
  resources:
    limits:
      memory: 300Mi
      cpu: 200m
    requests:
      memory: 100Mi
      cpu: 100m

nri-prometheus:
  enabled: true
  resources:
    limits:
      memory: 100Mi
      cpu: 100m
    requests:
      memory: 50Mi
      cpu: 50m
```

Instalación:

```bash
helm repo add newrelic https://helm-charts.newrelic.com
helm repo update
helm install newrelic-bundle -f newrelic-values.yaml newrelic/nri-bundle --namespace monitoring
```

## DevOps y SRE

### Automatización con Ansible

Puedes automatizar tareas operativas con Ansible:

```yaml
# playbook.yml
---
- name: Setup K3s hosts
  hosts: k3s_nodes
  become: true
  tasks:
    - name: Install dependencies
      apt:
        name:
          - curl
          - ca-certificates
        state: present
        update_cache: yes

    - name: Install K3s on server node
      shell: curl -sfL https://get.k3s.io | sh -
      when: inventory_hostname in groups['k3s_servers']

    - name: Get K3s token
      shell: cat /var/lib/rancher/k3s/server/node-token
      register: k3s_token
      when: inventory_hostname in groups['k3s_servers']

    - name: Register token as a fact
      set_fact:
        k3s_token: "{{ hostvars[groups['k3s_servers'][0]]['k3s_token']['stdout'] }}"
      when: inventory_hostname in groups['k3s_agents']

    - name: Install K3s on agent nodes
      shell: >
        curl -sfL https://get.k3s.io | 
        K3S_URL=https://{{ hostvars[groups['k3s_servers'][0]]['ansible_host'] }}:6443 
        K3S_TOKEN={{ k3s_token }} sh -
      when: inventory_hostname in groups['k3s_agents']
```

# Implementación Multi-Cloud con OpenTofu: Versión sin costo (Parte 5)

## 13. Integración con herramientas externas (continuación)

### 13.3 Gestión de Identidad (continuación)

```bash
# Instalación de OAuth2 Proxy
helm install oauth2-proxy -f oauth2-proxy-values.yaml oauth2-proxy/oauth2-proxy --namespace security
```

### 13.4 Backup y Recuperación

```markdown
# Soluciones de Backup y Recuperación

## Velero para Backup de Kubernetes

Velero es una herramienta open source que proporciona backup y recuperación de recursos y volúmenes de Kubernetes.

### Instalación optimizada para entorno local

```yaml
# velero-values.yaml
initContainers:
  - name: velero-plugin-for-aws
    image: velero/velero-plugin-for-aws:v1.5.0
    volumeMounts:
      - mountPath: /target
        name: plugins

configuration:
  provider: aws
  backupStorageLocation:
    name: default
    provider: aws
    bucket: velero-backups
    config:
      region: minio
      s3ForcePathStyle: true
      s3Url: http://minio.platform.svc.cluster.local:9000
  volumeSnapshotLocation:
    name: default
    provider: aws
    config:
      region: minio

deployRestic: true

resources:
  requests:
    cpu: 200m
    memory: 256Mi
  limits:
    cpu: 500m
    memory: 512Mi

# Credenciales para MinIO
credentials:
  useSecret: true
  existingSecret: velero-credentials

# Configurar retención de backups
schedules:
  daily-backup:
    schedule: "0 1 * * *"
    template:
      ttl: "240h"
```

### Configuración de credenciales para MinIO

```bash
# Crear archivo de credenciales
cat > credentials-velero << EOF
[default]
aws_access_key_id = admin
aws_secret_access_key = minioadmin
EOF

# Crear secret de Kubernetes
kubectl create secret generic velero-credentials \
  --from-file=cloud=credentials-velero \
  -n velero
```

### Instalación de Velero

```bash
# Crear namespace
kubectl create namespace velero

# Añadir repo de Helm
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm repo update

# Instalar Velero
helm install velero vmware-tanzu/velero \
  --namespace velero \
  -f velero-values.yaml
```

### Script para backup manual

```bash
# Crear script de backup
cat > scripts/backup.sh << 'EOF'
#!/bin/bash
set -e

BACKUP_NAME="manual-backup-$(date +%Y%m%d-%H%M%S)"

# Crear backup de todos los recursos
echo "Creando backup $BACKUP_NAME..."
velero backup create $BACKUP_NAME --include-namespaces platform,monitoring,security

# Esperar a que el backup complete
echo "Esperando que el backup complete..."
velero backup get

echo "Backup completado. Para restaurar, ejecuta:"
echo "velero restore create --from-backup $BACKUP_NAME"
EOF

chmod +x scripts/backup.sh
```

## Script de Restauración Completa

```bash
# Crear script de restauración
cat > scripts/restore.sh << 'EOF'
#!/bin/bash
set -e

if [ -z "$1" ]; then
  echo "Uso: $0 NOMBRE_DEL_BACKUP"
  echo "Backups disponibles:"
  velero backup get
  exit 1
fi

BACKUP_NAME=$1
RESTORE_NAME="restore-$(date +%Y%m%d-%H%M%S)"

# Crear restore
echo "Iniciando restauración desde backup $BACKUP_NAME..."
velero restore create $RESTORE_NAME --from-backup $BACKUP_NAME

# Esperar a que la restauración complete
echo "Esperando que la restauración complete..."
velero restore get

echo "Restauración completada. Verificando recursos..."
kubectl get pods -A
EOF

chmod +x scripts/restore.sh
```

## Respaldo de Datos Específicos

### Exportar configuraciones de aplicaciones

```bash
# Crear script para exportar configuraciones
cat > scripts/export-config.sh << 'EOF'
#!/bin/bash
set -e

EXPORT_DIR="./backups/$(date +%Y%m%d-%H%M%S)"
mkdir -p $EXPORT_DIR

# Exportar ConfigMaps
echo "Exportando ConfigMaps..."
kubectl get configmaps -A -o yaml > $EXPORT_DIR/configmaps.yaml

# Exportar Secrets (encriptados)
echo "Exportando Secrets..."
kubectl get secrets -A -o yaml | grep -v "token:" > $EXPORT_DIR/secrets.yaml

# Exportar PVCs
echo "Exportando PVCs..."
kubectl get pvc -A -o yaml > $EXPORT_DIR/pvcs.yaml

# Exportar CRDs y recursos personalizados
echo "Exportando CRDs y recursos personalizados..."
kubectl get crd -o yaml > $EXPORT_DIR/crds.yaml

# Exportar recursos de aplicaciones
for ns in platform monitoring security; do
  mkdir -p $EXPORT_DIR/$ns
  kubectl get all -n $ns -o yaml > $EXPORT_DIR/$ns/all.yaml
  
  # Exportar recursos específicos
  for resource in configmaps secrets deployments statefulsets services ingresses; do
    kubectl get $resource -n $ns -o yaml > $EXPORT_DIR/$ns/$resource.yaml
  done
done

echo "Exportación completada en $EXPORT_DIR"
EOF

chmod +x scripts/export-config.sh
```
```

### 13.5 Seguridad Avanzada

```markdown
# Seguridad Avanzada para la Plataforma Multi-Cloud

## Escaneo de Vulnerabilidades

### Instalación de Trivy Operator

Trivy Operator puede escanear continuamente las imágenes y recursos de Kubernetes para detectar vulnerabilidades:

```yaml
# trivy-operator-values.yaml
trivy:
  ignoreUnfixed: true
  resources:
    requests:
      cpu: 100m
      memory: 100Mi
    limits:
      cpu: 500m
      memory: 500Mi

operator:
  vulnerabilityReports:
    enabled: true
  configAuditReports:
    enabled: true
  resources:
    requests:
      cpu: 100m
      memory: 100Mi
    limits:
      cpu: 300m
      memory: 300Mi
```

```bash
# Instalar Trivy Operator
helm repo add aqua https://aquasecurity.github.io/helm-charts/
helm repo update
helm install trivy-operator aqua/trivy-operator \
  --namespace security \
  -f trivy-operator-values.yaml
```

## Políticas de Seguridad Kubernetes (PSPs/PSA)

### Implementar Pod Security Admission (PSA)

```yaml
# pod-security.yaml
apiVersion: apiserver.config.k8s.io/v1
kind: AdmissionConfiguration
plugins:
- name: PodSecurity
  configuration:
    apiVersion: pod-security.admission.config.k8s.io/v1
    kind: PodSecurityConfiguration
    defaults:
      enforce: "baseline"
      enforce-version: "latest"
      audit: "restricted"
      audit-version: "latest"
      warn: "restricted"
      warn-version: "latest"
    exemptions:
      usernames: []
      runtimeClasses: []
      namespaces: [kube-system, security]
```

```bash
# Aplicar políticas por namespace
kubectl label namespace platform \
  pod-security.kubernetes.io/enforce=baseline \
  pod-security.kubernetes.io/warn=restricted \
  pod-security.kubernetes.io/audit=restricted

kubectl label namespace monitoring \
  pod-security.kubernetes.io/enforce=baseline \
  pod-security.kubernetes.io/warn=restricted \
  pod-security.kubernetes.io/audit=restricted
```

## Reglas de Seguridad Avanzadas con OPA/Gatekeeper

```yaml
# require-non-root-user.yaml
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8snonrootuser
spec:
  crd:
    spec:
      names:
        kind: K8sNonRootUser
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8snonrootuser
        
        violation[{"msg": msg}] {
          input.review.object.kind == "Pod"
          container := input.review.object.spec.containers[_]
          not container_has_valid_user(container)
          msg := sprintf("Container %v must set securityContext.runAsNonRoot=true", [container.name])
        }
        
        container_has_valid_user(container) {
          container.securityContext.runAsNonRoot == true
        }
        
        container_has_valid_user(container) {
          container.securityContext.runAsUser > 0
        }
```

```yaml
# apply-non-root-constraint.yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sNonRootUser
metadata:
  name: pods-must-run-as-nonroot
spec:
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
    namespaces:
      - "platform"
      - "monitoring"
```

## Network Policies

```yaml
# default-deny-policy.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
  namespace: platform
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-same-namespace
  namespace: platform
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector: {}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-ingress-controller
  namespace: platform
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: ingress-system
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
  namespace: platform
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    ports:
    - protocol: UDP
      port: 53
```

## Implementación del script de seguridad

```bash
# Crear script para aplicar configuraciones de seguridad
cat > scripts/apply-security.sh << 'EOF'
#!/bin/bash
set -e

echo "Aplicando configuraciones de seguridad..."

# Aplicar Network Policies
kubectl apply -f policies/network/default-deny-policy.yaml

# Aplicar OPA Constraints
kubectl apply -f policies/opa/require-non-root-user.yaml
kubectl apply -f policies/opa/apply-non-root-constraint.yaml

# Aplicar Pod Security Standards
kubectl label namespace platform \
  pod-security.kubernetes.io/enforce=baseline \
  pod-security.kubernetes.io/warn=restricted \
  pod-security.kubernetes.io/audit=restricted

kubectl label namespace monitoring \
  pod-security.kubernetes.io/enforce=baseline \
  pod-security.kubernetes.io/warn=restricted \
  pod-security.kubernetes.io/audit=restricted

echo "Configuraciones de seguridad aplicadas correctamente."
EOF

chmod +x scripts/apply-security.sh
```
```

## 14. Automatización y Herramientas de Productividad

### 14.1 Scripts de Automatización adicionales

```markdown
# Scripts de Automatización para el Proyecto

## Automatización de Despliegue

### Script completo de despliegue

Este script automatiza todo el proceso de despliegue desde cero:

```bash
#!/bin/bash
set -e

ENVIRONMENT=${1:-local}  # Por defecto: local

print_section() {
  echo "======================================================"
  echo ">>> $1"
  echo "======================================================"
}

# Verificar herramientas necesarias
check_tools() {
  print_section "Verificando herramientas necesarias"
  
  for tool in docker kubectl helm tofu k3d
  do
    if ! command -v $tool &> /dev/null
    then
      echo "❌ $tool no está instalado. Por favor instálalo antes de continuar."
      exit 1
    else
      echo "✅ $tool está instalado."
    fi
  done
}

# Desplegar infraestructura
deploy_infrastructure() {
  print_section "Desplegando infraestructura en $ENVIRONMENT"
  
  case $ENVIRONMENT in
    local)
      # Crear cluster local con K3d
      echo "Creando cluster K3d..."
      ./scripts/create-local-cluster.sh
      
      # Desplegar infraestructura base con OpenTofu
      echo "Desplegando infraestructura base..."
      cd infrastructure/local
      tofu init
      tofu apply -auto-approve
      cd ../..
      ;;
    aws)
      # Verificar credenciales AWS
      if ! aws sts get-caller-identity &> /dev/null; then
        echo "❌ Credenciales de AWS no configuradas. Ejecuta 'aws configure' primero."
        exit 1
      fi
      
      # Desplegar infraestructura AWS
      echo "Desplegando infraestructura en AWS..."
      cd infrastructure/aws
      tofu init
      tofu apply -auto-approve
      cd ../..
      
      # Obtener kubeconfig
      echo "Configurando kubeconfig para AWS..."
      ./scripts/get-aws-kubeconfig.sh
      ;;
    *)
      echo "❌ Entorno no soportado: $ENVIRONMENT"
      echo "Los entornos soportados son: local, aws"
      exit 1
      ;;
  esac
}

# Desplegar componentes de plataforma
deploy_platform() {
  print_section "Desplegando componentes de plataforma"
  
  # Instalar networking
  echo "Instalando Cilium..."
  ./scripts/install-cilium.sh
  
  # Instalar almacenamiento
  echo "Instalando Longhorn..."
  ./scripts/install-longhorn.sh
  
  # Instalar observabilidad
  echo "Instalando stack de observabilidad..."
  ./scripts/install-monitoring.sh
  
  # Instalar MinIO
  echo "Instalando MinIO..."
  cd infrastructure/$ENVIRONMENT
  tofu apply -target=helm_release.minio -auto-approve
  cd ../..
  
  # Instalar seguridad
  echo "Instalando componentes de seguridad..."
  ./scripts/install-cert-manager.sh
  ./scripts/install-opa.sh
  
  # Instalar Vault
  cd infrastructure/$ENVIRONMENT
  tofu apply -target=helm_release.vault -auto-approve
  cd ../..
}

# Desplegar aplicaciones
deploy_applications() {
  print_section "Desplegando aplicaciones"
  
  # Configurar Gitea
  echo "Instalando Gitea..."
  cd infrastructure/$ENVIRONMENT
  tofu apply -target=helm_release.gitea -auto-approve
  cd ../..
  
  # Configurar Drone (requiere configuración manual de OAuth en Gitea)
  echo "Drone CI requiere configuración manual de OAuth en Gitea."
  echo "Por favor, ejecuta ./scripts/setup-drone.sh después de configurar OAuth en Gitea."
}

# Verificar despliegue
verify_deployment() {
  print_section "Verificando despliegue"
  
  echo "Verificando nodos..."
  kubectl get nodes
  
  echo "Verificando namespaces..."
  kubectl get namespaces
  
  echo "Verificando pods por namespace..."
  for ns in platform monitoring security kube-system ingress-system longhorn-system
  do
    echo "--- Namespace: $ns ---"
    kubectl get pods -n $ns
  done
  
  echo "Verificando servicios..."
  kubectl get svc -A
  
  echo "Verificando ingress..."
  kubectl get ingress -A
}

# Configurar acceso y proporcionar información
configure_access() {
  print_section "Configurando acceso"
  
  case $ENVIRONMENT in
    local)
      echo "Para acceder a las aplicaciones, añade las siguientes entradas a tu archivo /etc/hosts:"
      echo "127.0.0.1 grafana.local minio.local gitea.local drone.local vault.local"
      
      echo "URLs de acceso:"
      echo "Grafana: http://grafana.local"
      echo "MinIO: http://minio.local"
      echo "Gitea: http://gitea.local"
      echo "Drone: http://drone.local"
      echo "Vault: http://vault.local"
      ;;
    aws)
      echo "Obteniendo IPs públicas..."
      INGRESS_IP=$(kubectl get svc -n ingress-system ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
      
      echo "Para acceder a las aplicaciones, añade las siguientes entradas a tu DNS o archivo /etc/hosts:"
      echo "$INGRESS_IP grafana.yourdomain.com minio.yourdomain.com gitea.yourdomain.com drone.yourdomain.com vault.yourdomain.com"
      
      echo "URLs de acceso:"
      echo "Grafana: http://grafana.yourdomain.com"
      echo "MinIO: http://minio.yourdomain.com"
      echo "Gitea: http://gitea.yourdomain.com"
      echo "Drone: http://drone.yourdomain.com"
      echo "Vault: http://vault.yourdomain.com"
      ;;
  esac
  
  echo "Credenciales por defecto:"
  echo "Grafana: admin / prom-operator"
  echo "MinIO: admin / minioadmin"
  echo "Gitea: gitea_admin / gitea_admin"
  echo "Vault: En modo desarrollo, no requiere autenticación"
  
  echo "IMPORTANTE: Cambiar todas las contraseñas por defecto antes de usar en producción."
}

# Función principal
main() {
  check_tools
  deploy_infrastructure
  deploy_platform
  deploy_applications
  verify_deployment
  configure_access
  
  print_section "Despliegue completado exitosamente"
  echo "La plataforma multi-cloud está lista para usar en entorno: $ENVIRONMENT"
  echo "Ejecuta los scripts específicos de aplicaciones según sea necesario."
}

# Ejecutar función principal
main
```

## Script de estado de salud del sistema

```bash
#!/bin/bash
set -e

print_header() {
  echo "====================================================================================="
  echo "  $1"
  echo "====================================================================================="
}

# Verificar estado de nodos
print_header "ESTADO DE NODOS"
kubectl get nodes -o wide

# Verificar estado de componentes del plano de control
print_header "COMPONENTES DEL PLANO DE CONTROL"
kubectl get componentstatuses

# Verificar pods en estado no Running
print_header "PODS NO RUNNING"
kubectl get pods --all-namespaces | grep -v "Running" | grep -v "Completed"

# Verificar uso de recursos
print_header "USO DE RECURSOS"
echo "Top Pods por CPU:"
kubectl top pods --all-namespaces | sort --reverse --key 3 --numeric | head -10
echo ""
echo "Top Pods por Memoria:"
kubectl top pods --all-namespaces | sort --reverse --key 4 --numeric | head -10

# Verificar eventos recientes
print_header "EVENTOS RECIENTES"
kubectl get events --all-namespaces --sort-by='.lastTimestamp' | tail -20

# Verificar estado de PVCs
print_header "ESTADO DE PVCs"
kubectl get pvc --all-namespaces

# Verificar estado de servicios
print_header "SERVICIOS"
kubectl get svc --all-namespaces

# Verificar estado de ingress
print_header "INGRESS"
kubectl get ingress --all-namespaces

# Verificar estado de deployments
print_header "DEPLOYMENTS"
kubectl get deployments --all-namespaces

# Verificar espacio en disco
print_header "ESPACIO EN DISCO"
df -h

# Verificar memoria
print_header "MEMORIA"
free -h

# Verificar logs de componentes críticos
print_header "LOGS DE COMPONENTES CRÍTICOS"

echo ">>> Logs de coredns:"
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=20

echo ">>> Logs de nginx-ingress-controller:"
kubectl logs -n ingress-system -l app.kubernetes.io/name=ingress-nginx --tail=20

# Resumen
print_header "RESUMEN DEL SISTEMA"
echo "Nodos: $(kubectl get nodes --no-headers | wc -l)"
echo "Namespaces: $(kubectl get namespaces --no-headers | wc -l)"
echo "Pods: $(kubectl get pods --all-namespaces --no-headers | wc -l)"
echo "Pods Running: $(kubectl get pods --all-namespaces --no-headers | grep "Running" | wc -l)"
echo "Pods Pending/Failed: $(kubectl get pods --all-namespaces --no-headers | grep -v "Running" | grep -v "Completed" | wc -l)"
echo "Deployments: $(kubectl get deployments --all-namespaces --no-headers | wc -l)"
echo "Services: $(kubectl get svc --all-namespaces --no-headers | wc -l)"
echo "PVCs: $(kubectl get pvc --all-namespaces --no-headers | wc -l)"
echo "Ingress: $(kubectl get ingress --all-namespaces --no-headers | wc -l)"
```

## Script para rotación de credenciales

```bash
#!/bin/bash
set -e

print_step() {
  echo "==> $1"
}

# Función para generar contraseña aleatoria
generate_password() {
  openssl rand -base64 16 | tr -d "=+/" | cut -c1-16
}

# Rotar credenciales de MinIO
rotate_minio_credentials() {
  print_step "Rotando credenciales de MinIO"
  
  NEW_ACCESS_KEY="minio$(date +%Y%m)"
  NEW_SECRET_KEY=$(generate_password)
  
  # Actualizar el secret de Kubernetes
  kubectl create secret generic minio-credentials \
    --from-literal=accesskey=$NEW_ACCESS_KEY \
    --from-literal=secretkey=$NEW_SECRET_KEY \
    -n platform \
    --dry-run=client -o yaml | kubectl apply -f -
  
  # Actualizar el despliegue de MinIO
  kubectl rollout restart deployment minio -n platform
  
  echo "Nuevas credenciales de MinIO:"
  echo "Access Key: $NEW_ACCESS_KEY"
  echo "Secret Key: $NEW_SECRET_KEY"
  echo ""
  echo "Guarda estas credenciales en un lugar seguro."
}

# Rotar credenciales de Grafana
rotate_grafana_credentials() {
  print_step "Rotando credenciales de Grafana"
  
  NEW_ADMIN_PASSWORD=$(generate_password)
  
  # Actualizar el secret de Kubernetes
  kubectl patch secret prometheus-grafana -n monitoring \
    -p="{\"data\":{\"admin-password\": \"$(echo -n $NEW_ADMIN_PASSWORD | base64)\"}}"
  
  # Reiniciar pod de Grafana
  kubectl rollout restart deployment prometheus-grafana -n monitoring
  
  echo "Nuevas credenciales de Grafana:"
  echo "Usuario: admin"
  echo "Contraseña: $NEW_ADMIN_PASSWORD"
  echo ""
  echo "Guarda estas credenciales en un lugar seguro."
}

# Rotar credenciales de Gitea
rotate_gitea_credentials() {
  print_step "Rotando credenciales de Gitea"
  
  NEW_ADMIN_PASSWORD=$(generate_password)
  
  # Actualizar el secret de Kubernetes
  kubectl patch secret gitea-admin-secret -n platform \
    -p="{\"data\":{\"password\": \"$(echo -n $NEW_ADMIN_PASSWORD | base64)\"}}"
  
  # Reiniciar pod de Gitea
  kubectl rollout restart statefulset gitea -n platform
  
  echo "Nuevas credenciales de Gitea:"
  echo "Usuario: gitea_admin"
  echo "Contraseña: $NEW_ADMIN_PASSWORD"
  echo ""
  echo "Guarda estas credenciales en un lugar seguro."
}

# Función principal
main() {
  echo "Script de Rotación de Credenciales"
  echo "====================================="
  
  echo "Este script rotará las credenciales de los siguientes servicios:"
  echo "1. MinIO"
  echo "2. Grafana"
  echo "3. Gitea"
  echo "4. Todos los servicios"
  echo ""
  read -p "Selecciona una opción (1-4): " option
  
  case $option in
    1)
      rotate_minio_credentials
      ;;
    2)
      rotate_grafana_credentials
      ;;
    3)
      rotate_gitea_credentials
      ;;
    4)
      rotate_minio_credentials
      rotate_grafana_credentials
      rotate_gitea_credentials
      ;;
    *)
      echo "Opción no válida."
      exit 1
      ;;
  esac
  
  echo "Rotación de credenciales completada correctamente."
}

# Ejecutar función principal
main
```
```
# Implementación Multi-Cloud con OpenTofu: Versión sin costo (Parte 6)

## 14. Automatización y Herramientas de Productividad (continuación)

### 14.2 Makefile para tareas comunes (continuación)

```makefile
# Estado
status:
	@echo "${GREEN}Estado de la plataforma:${NC}"
	@kubectl get nodes
	@echo "\n${GREEN}Pods por namespace:${NC}"
	@for ns in platform monitoring security kube-system ingress-system longhorn-system; do \
		echo "\n${YELLOW}Namespace: $$ns${NC}"; \
		kubectl get pods -n $$ns; \
	done
	@echo "\n${GREEN}Servicios expuestos:${NC}"
	@kubectl get svc --all-namespaces | grep -E 'LoadBalancer|NodePort'
	@echo "\n${GREEN}Ingress:${NC}"
	@kubectl get ingress --all-namespaces

# Logs
logs:
	@if [ -z "$(APP)" ]; then \
		echo "${RED}Error: Debes especificar una aplicación con APP=nombre${NC}"; \
		exit 1; \
	fi
	@echo "${GREEN}Mostrando logs de $(APP) en namespace $(NAMESPACE)...${NC}"
	@kubectl logs -n $(NAMESPACE) -l app=$(APP) --tail=100 -f

# Backup
backup:
	@echo "${GREEN}Realizando backup de la plataforma...${NC}"
	@./scripts/backup.sh

# Restore
restore:
	@if [ -z "$(BACKUP)" ]; then \
		echo "${RED}Error: Debes especificar un backup con BACKUP=nombre${NC}"; \
		exit 1; \
	fi
	@echo "${GREEN}Restaurando backup $(BACKUP)...${NC}"
	@./scripts/restore.sh $(BACKUP)

# Tareas adicionales
.PHONY: port-forward update upgrade

port-forward:
	@if [ -z "$(APP)" ]; then \
		echo "${RED}Error: Debes especificar una aplicación con APP=nombre${NC}"; \
		exit 1; \
	fi
	@if [ -z "$(PORT)" ]; then \
		echo "${RED}Error: Debes especificar un puerto con PORT=número${NC}"; \
		exit 1; \
	fi
	@echo "${GREEN}Port-forward para $(APP) en namespace $(NAMESPACE) al puerto $(PORT)...${NC}"
	@kubectl port-forward -n $(NAMESPACE) svc/$(APP) $(PORT):$(PORT)

update:
	@echo "${GREEN}Actualizando repositorio...${NC}"
	@git pull
	@echo "${GREEN}Actualizando dependencias...${NC}"
	@cd infrastructure/$(ENVIRONMENT) && tofu init -upgrade

upgrade:
	@echo "${GREEN}Actualizando componentes de la plataforma...${NC}"
	@helm repo update
	@./scripts/upgrade-all.sh
```

### 14.3 Integración con VSCode

```markdown
# Integración con Visual Studio Code

Para facilitar el desarrollo y gestión del proyecto, puedes configurar Visual Studio Code con extensiones y configuraciones específicas.

## Configuración del Workspace

Crea un archivo `.vscode/settings.json` en tu proyecto:

```json
{
  "editor.formatOnSave": true,
  "editor.renderWhitespace": "all",
  "files.trimTrailingWhitespace": true,
  "files.insertFinalNewline": true,
  "files.trimFinalNewlines": true,
  
  // OpenTofu
  "terraform.languageServer": {
    "external": true,
    "pathToBinary": "tofu",
    "args": ["metadata"]
  },
  "[terraform]": {
    "editor.formatOnSave": true,
    "editor.defaultFormatter": "hashicorp.terraform"
  },

  // Kubernetes
  "vs-kubernetes": {
    "vs-kubernetes.kubectl-path": "kubectl",
    "vs-kubernetes.helm-path": "helm",
    "vs-kubernetes.minikube-path": "k3d"
  },
  
  // YAML
  "yaml.schemas": {
    "kubernetes": ["k8s/**/*.yaml", "platform/**/*.yaml"]
  },
  "[yaml]": {
    "editor.defaultFormatter": "redhat.vscode-yaml"
  },
  
  // Configuraciones de terminal
  "terminal.integrated.env.linux": {
    "KUBECONFIG": "${workspaceFolder}/.kube/config"
  },
  "terminal.integrated.env.osx": {
    "KUBECONFIG": "${workspaceFolder}/.kube/config"
  },
  
  // Extensiones recomendadas
  "extensions.ignoreRecommendations": false
}
```

## Extensiones Recomendadas

Crea un archivo `.vscode/extensions.json` para recomendar extensiones:

```json
{
  "recommendations": [
    "hashicorp.terraform",
    "ms-kubernetes-tools.vscode-kubernetes-tools",
    "redhat.vscode-yaml",
    "ms-azuretools.vscode-docker",
    "github.vscode-github-actions",
    "timonwong.shellcheck",
    "yzhang.markdown-all-in-one",
    "streetsidesoftware.code-spell-checker",
    "bierner.markdown-mermaid",
    "esbenp.prettier-vscode"
  ]
}
```

## Tasks de VS Code

Crea un archivo `.vscode/tasks.json` para definir tareas:

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Deploy Local Infrastructure",
      "type": "shell",
      "command": "cd infrastructure/local && tofu init && tofu apply -auto-approve",
      "problemMatcher": []
    },
    {
      "label": "Create Local Cluster",
      "type": "shell",
      "command": "./scripts/create-local-cluster.sh",
      "problemMatcher": []
    },
    {
      "label": "Deploy Monitoring Stack",
      "type": "shell",
      "command": "./scripts/install-monitoring.sh",
      "problemMatcher": []
    },
    {
      "label": "Check Platform Status",
      "type": "shell",
      "command": "kubectl get nodes && echo '' && kubectl get pods -A",
      "problemMatcher": []
    },
    {
      "label": "Cleanup All Resources",
      "type": "shell",
      "command": "./scripts/cleanup.sh",
      "problemMatcher": []
    }
  ]
}
```

## Launch Configuration

Para debugging de scripts, crea un archivo `.vscode/launch.json`:

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "type": "bashdb",
      "request": "launch",
      "name": "Debug Bash Script",
      "program": "${file}",
      "args": []
    },
    {
      "type": "node",
      "request": "launch",
      "name": "Debug Node App",
      "skipFiles": ["<node_internals>/**"],
      "program": "${workspaceFolder}/demo-app/api/index.js"
    }
  ]
}
```

## Script para configurar VS Code

```bash
#!/bin/bash
set -e

# Crear directorios
mkdir -p .vscode .kube

# Crear settings.json
cat > .vscode/settings.json << 'EOF'
{
  "editor.formatOnSave": true,
  "editor.renderWhitespace": "all",
  "files.trimTrailingWhitespace": true,
  "files.insertFinalNewline": true,
  "files.trimFinalNewlines": true,
  
  // OpenTofu
  "terraform.languageServer": {
    "external": true,
    "pathToBinary": "tofu",
    "args": ["metadata"]
  },
  "[terraform]": {
    "editor.formatOnSave": true,
    "editor.defaultFormatter": "hashicorp.terraform"
  },

  // Kubernetes
  "vs-kubernetes": {
    "vs-kubernetes.kubectl-path": "kubectl",
    "vs-kubernetes.helm-path": "helm",
    "vs-kubernetes.minikube-path": "k3d"
  },
  
  // YAML
  "yaml.schemas": {
    "kubernetes": ["k8s/**/*.yaml", "platform/**/*.yaml"]
  },
  "[yaml]": {
    "editor.defaultFormatter": "redhat.vscode-yaml"
  },
  
  // Configuraciones de terminal
  "terminal.integrated.env.linux": {
    "KUBECONFIG": "${workspaceFolder}/.kube/config"
  },
  "terminal.integrated.env.osx": {
    "KUBECONFIG": "${workspaceFolder}/.kube/config"
  },
  
  // Extensiones recomendadas
  "extensions.ignoreRecommendations": false
}
EOF

# Crear extensions.json
cat > .vscode/extensions.json << 'EOF'
{
  "recommendations": [
    "hashicorp.terraform",
    "ms-kubernetes-tools.vscode-kubernetes-tools",
    "redhat.vscode-yaml",
    "ms-azuretools.vscode-docker",
    "github.vscode-github-actions",
    "timonwong.shellcheck",
    "yzhang.markdown-all-in-one",
    "streetsidesoftware.code-spell-checker",
    "bierner.markdown-mermaid",
    "esbenp.prettier-vscode"
  ]
}
EOF

# Crear tasks.json
cat > .vscode/tasks.json << 'EOF'
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Deploy Local Infrastructure",
      "type": "shell",
      "command": "cd infrastructure/local && tofu init && tofu apply -auto-approve",
      "problemMatcher": []
    },
    {
      "label": "Create Local Cluster",
      "type": "shell",
      "command": "./scripts/create-local-cluster.sh",
      "problemMatcher": []
    },
    {
      "label": "Deploy Monitoring Stack",
      "type": "shell",
      "command": "./scripts/install-monitoring.sh",
      "problemMatcher": []
    },
    {
      "label": "Check Platform Status",
      "type": "shell",
      "command": "kubectl get nodes && echo '' && kubectl get pods -A",
      "problemMatcher": []
    },
    {
      "label": "Cleanup All Resources",
      "type": "shell",
      "command": "./scripts/cleanup.sh",
      "problemMatcher": []
    }
  ]
}
EOF

# Crear launch.json
cat > .vscode/launch.json << 'EOF'
{
  "version": "0.2.0",
  "configurations": [
    {
      "type": "bashdb",
      "request": "launch",
      "name": "Debug Bash Script",
      "program": "${file}",
      "args": []
    },
    {
      "type": "node",
      "request": "launch",
      "name": "Debug Node App",
      "skipFiles": ["<node_internals>/**"],
      "program": "${workspaceFolder}/demo-app/api/index.js"
    }
  ]
}
EOF

echo "Configuración de VS Code creada correctamente."
```
```

## 15. Consideraciones Finales y Mejores Prácticas

### 15.1 Mejorando el README principal

```markdown
# Multi-Cloud Platform con OpenTofu

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Infrastructure](https://img.shields.io/badge/infrastructure-opentofu-844FBA)](https://opentofu.org/)
[![Kubernetes](https://img.shields.io/badge/kubernetes-k3s-326CE5)](https://k3s.io/)
[![Cost](https://img.shields.io/badge/Cost-$0-success)](docs/zero-cost-optimizations.md)

![Multi-Cloud Architecture](docs/diagrams/architecture-diagram.png)

## 🌟 Descripción

Esta plataforma implementa una arquitectura multi-cloud completa utilizando exclusivamente herramientas open source. Comienza con costo $0 en un entorno local y puede migrarse fácilmente a proveedores cloud cuando sea necesario.

### Características principales:

- **Infraestructura como Código** con OpenTofu
- **Kubernetes ligero** con K3s/K3d
- **Observabilidad integrada** con Prometheus, Grafana y Loki
- **CI/CD autónomo** con Gitea y Drone
- **Almacenamiento escalable** con Longhorn y MinIO (compatible con S3)
- **Seguridad robusta** con Vault, OPA y Cert-Manager
- **Migración sencilla** de local a cloud (AWS, Oracle, GCP, Azure)
- **Documentación extensa** con diagramas y ADRs

## 📋 Requisitos

- Docker
- kubectl
- helm
- OpenTofu (fork open source de Terraform)
- 4GB RAM y 20GB disco para entorno local

## 🚀 Inicio Rápido

```bash
# Clonar repositorio
git clone https://github.com/tu-usuario/multi-cloud-platform-opentofu.git
cd multi-cloud-platform-opentofu

# Instalar herramientas (si no las tienes)
./scripts/install-tools.sh

# Desplegar plataforma completa en local
make deploy ENVIRONMENT=local

# Verificar instalación
kubectl get pods -A
```

## 📊 Componentes

| Categoría | Componentes |
|-----------|-------------|
| **Infraestructura** | OpenTofu, K3d/K3s, Cilium |
| **Almacenamiento** | Longhorn, MinIO |
| **CI/CD** | Gitea, Drone CI |
| **Observabilidad** | Prometheus, Grafana, Loki |
| **Seguridad** | Vault, OPA/Gatekeeper, Cert-Manager |
| **Demo App** | Node.js API, Redis, PostgreSQL |

## 🗂️ Estructura del Proyecto

```
multi-cloud-platform-opentofu/
├── docs/                      # Documentación
│   ├── diagrams/              # Diagramas de arquitectura
│   └── decision-records/      # Architecture Decision Records
├── infrastructure/            # Configuración de infraestructura
│   ├── modules/               # Módulos reutilizables
│   ├── local/                 # Configuración para entorno local
│   └── aws/                   # Configuración para AWS
├── platform/                  # Configuración de la plataforma
│   ├── kubernetes/            # Configuración de Kubernetes
│   └── applications/          # Aplicaciones de la plataforma
├── demo-app/                  # Aplicación de ejemplo
├── policies/                  # Políticas de seguridad
└── scripts/                   # Scripts de automatización
```

## 📚 Documentación

- [Guía de Usuario](docs/user-guide.md)
- [Guía de Implementación](docs/implementation-guide.md)
- [Arquitectura](docs/architecture.md)
- [Optimizaciones sin costo](docs/zero-cost-optimizations.md)
- [Migración a AWS](docs/aws-migration-guide.md)
- [Troubleshooting](docs/troubleshooting.md)

## 🔧 Comandos Comunes

```bash
# Crear cluster local
./scripts/create-local-cluster.sh

# Desplegar infraestructura
cd infrastructure/local && tofu apply

# Instalar componentes específicos
./scripts/install-monitoring.sh

# Limpiar entorno
./scripts/cleanup.sh

# Usar Makefile para tareas comunes
make status
make deploy ENVIRONMENT=local
make logs APP=grafana NAMESPACE=monitoring
```

## 💡 Extensiones y Casos de Uso

- [Integración con Oracle Cloud](docs/extensions.md#Oracle-Cloud)
- [Componentes adicionales](docs/extensions.md)
- [Ideas de proyectos](docs/project-ideas.md)

## 📄 Licencia

Este proyecto está licenciado bajo [MIT License](LICENSE).

## 🙏 Agradecimientos

- [OpenTofu Community](https://opentofu.org)
- [K3s Project](https://k3s.io)
- [CNCF Landscape](https://landscape.cncf.io/)
```

### 15.2 Mejores prácticas y recomendaciones finales

```markdown
# Mejores Prácticas y Recomendaciones

## Optimización de Recursos

### 1. Dimensionamiento correcto

* Establece peticiones y límites precisos para todos los componentes
* Usa perfiles diferentes entre desarrollo y producción
* Prioriza servicios críticos con Quality of Service adecuado

### 2. Minimizar cargas innecesarias

* Desactiva componentes que no uses (ej. algunos exporters de Prometheus)
* Implementa políticas de retención adecuadas para logs y métricas
* Usa sidecar containers solo cuando sean realmente necesarios

### 3. Optimizar almacenamiento

* Implementa políticas de lifecycle para datos antiguos
* Usa compresión cuando sea posible
* Monitorea crecimiento de PVs y establece alertas

## Seguridad

### 1. Gestión de credenciales

* Nunca uses credenciales por defecto en entornos reales
* Rota credenciales regularmente
* Implementa políticas de mínimo privilegio

### 2. Exposición de servicios

* Limita ingress solo a los servicios que realmente necesitan ser expuestos
* Usa TLS para todas las conexiones externas
* Implementa autenticación en todos los endpoints públicos

### 3. Actualizaciones y parches

* Establece un proceso regular para aplicar actualizaciones de seguridad
* Mantén un inventario de todas las versiones de componentes
* Pon especial atención a CVEs críticos

## Operaciones

### 1. Respaldos

* Implementa una estrategia de backup regular
* Prueba restauraciones periódicamente
* Documenta procedimientos de recuperación

### 2. Monitoreo

* Configura alertas para problemas críticos
* Establece SLOs/SLIs para servicios importantes
* Implementa dashboards útiles y claros

### 3. Automatización

* Automatiza tareas repetitivas con scripts
* Documenta todos los procedimientos manuales
* Usa IaC para todos los cambios de infraestructura

## Escalabilidad

### 1. Microservicios

* Diseña servicios con límites claros de responsabilidad
* Implementa patrones de resilencia (Circuit Breaker, Bulkhead)
* Usa comunicación asíncrona cuando sea posible

### 2. Stateless vs Stateful

* Prioriza arquitecturas stateless cuando sea posible
* Usa servicios externos gestionados para estado cuando escales a cloud
* Implementa correctamente persistent volumes para servicios stateful

### 3. Migración a la nube

* Planifica la estrategia de migración con anticipación
* Comienza con componentes no críticos
* Implementa monitoreo antes de migrar servicios críticos

## Proceso de Desarrollo

### 1. GitOps

* Mantén la configuración en Git
* Implementa CI/CD para validar cambios
* Utiliza despliegues progresivos o canary

### 2. Documentación

* Actualiza diagramas y documentación con cada cambio significativo
* Mantén un registro de decisiones de arquitectura (ADRs)
* Documenta procedimientos operativos

### 3. Testing

* Implementa pruebas automatizadas para todos los componentes
* Realiza pruebas de caos para validar resiliencia
* Simula escenarios de recuperación de desastres

## Consideraciones para Entornos Productivos

### 1. Alta disponibilidad

* Migrar a un cluster multi-nodo real
* Configurar replicación de componentes críticos
* Implementar estrategias de failover

### 2. Cumplimiento y gobernanza

* Configurar auditoría y logging centralizado
* Establecer controles de acceso basados en roles (RBAC)
* Implementar políticas de seguridad más estrictas

### 3. Soporte y mantenimiento

* Establecer un calendario de mantenimiento
* Planificar actualizaciones de versiones mayores
* Documentar procedimientos de escalado de incidentes
```

### 15.3 Checklist final

```markdown
# ✅ Checklist Final del Proyecto

## Infraestructura y Configuración Base

- [ ] Herramientas locales instaladas y verificadas
- [ ] Estructura de repositorio definida y organizada
- [ ] Módulos OpenTofu para infraestructura creados
- [ ] Configuración para entorno local creada
- [ ] Configuración para AWS preparada

## Kubernetes y Plataforma Base

- [ ] Cluster K3d local funcionando
- [ ] Namespaces creados (platform, monitoring, security)
- [ ] Cilium instalado y configurado
- [ ] Longhorn instalado y configurado como storageclass default
- [ ] Ingress Controller configurado

## Componentes Core

- [ ] MinIO instalado y configurado
- [ ] Prometheus/Grafana/Loki instalados
- [ ] Gitea instalado y configurado
- [ ] Drone CI configurado con Gitea
- [ ] Vault instalado y operativo

## Seguridad

- [ ] OPA/Gatekeeper instalado
- [ ] Políticas básicas implementadas
- [ ] Cert-Manager instalado
- [ ] TLS para ingress configurado
- [ ] Network Policies implementadas

## Documentación

- [ ] README principal completo
- [ ] Diagramas de arquitectura creados
- [ ] Decision Records (ADRs) documentados
- [ ] Guía de implementación detallada
- [ ] Documentación de troubleshooting

## Automatización

- [ ] Scripts para instalación creados
- [ ] Scripts para mantenimiento implementados
- [ ] Makefile configurado
- [ ] CI/CD para el proyecto configurado
- [ ] Integración con VSCode preparada

## Aplicación Demo

- [ ] API y servicios desarrollados
- [ ] Configuración Kubernetes creada
- [ ] Pipeline CI/CD configurado
- [ ] Monitoreo específico implementado
- [ ] Documentación de la aplicación

## Pruebas y Validación

- [ ] Pruebas de despliegue completo realizadas
- [ ] Validación de seguridad ejecutada
- [ ] Pruebas de backup y restauración
- [ ] Comprobación de monitoreo y alertas
- [ ] Prueba de migración a AWS ejecutada

## Mejoras y Optimizaciones

- [ ] Optimizaciones de recursos implementadas
- [ ] Mejoras de seguridad aplicadas
- [ ] Documentación de mejores prácticas
- [ ] Planificación para extensiones futuras
- [ ] Revisión final de código y configuración
```
# Implementación Multi-Cloud con OpenTofu: Versión sin costo (Parte 7 - Sección Final)

## 16. Próximos pasos y expansión del proyecto (continuación)

### 16.3 Contribución y Comunidad

```markdown
# Guía de Contribución

¡Gracias por considerar contribuir a este proyecto! Seguir estas pautas nos ayuda a mantener una base de código coherente y de alta calidad.

## 🌟 Cómo Contribuir

### Reportar Problemas

1. Usa el rastreador de problemas de GitHub para informar errores o sugerir mejoras
2. Verifica primero si el problema ya ha sido reportado
3. Usa la plantilla de problemas para proporcionar toda la información necesaria

### Solicitudes de Cambios (Pull Requests)

1. Haz fork del repositorio
2. Crea una rama para tu cambio: `git checkout -b feature/amazing-feature`
3. Realiza tus cambios y haz commit: `git commit -m 'Add: amazing feature'`
4. Empuja tus cambios al fork: `git push origin feature/amazing-feature`
5. Abre un Pull Request desde tu fork a este repositorio

### Convenciones de Código

- Sigue el estilo de código existente
- Usa nombres descriptivos para variables y funciones
- Mantén la documentación actualizada
- Escribe pruebas para nuevas características

## 📋 Proceso de Revisión

1. Al menos un mantenedor debe aprobar los cambios
2. Los cambios deben pasar todas las comprobaciones de CI/CD
3. La documentación debe actualizarse si es necesario
4. El código debe seguir las convenciones del proyecto

## 🔍 Áreas Prioritarias para Contribuciones

- Optimizaciones para entornos sin costo
- Soporte para más proveedores cloud
- Mejoras en seguridad y observabilidad
- Expansión de la documentación y tutoriales
- Componentes adicionales para la plataforma

## 🙏 Código de Conducta

Por favor, lee y sigue nuestro [Código de Conducta](CODE_OF_CONDUCT.md) para mantener un ambiente respetuoso y colaborativo.
```

### 16.4 Construyendo una comunidad alrededor del proyecto

```markdown
# Construyendo una Comunidad

## 👥 Cómo Participar

### Canales de Comunicación

- **GitHub Discussions**: Para preguntas, ideas y discusiones generales
- **Issues en GitHub**: Para reportar problemas y solicitar características
- **Pull Requests**: Para contribuir con código o documentación
- **Discord/Slack**: Canal para comunicación en tiempo real (próximamente)

### Reuniones y Eventos

- **Office Hours**: Sesiones bimensuales para responder preguntas (próximamente)
- **Webinars**: Demostraciones y tutoriales sobre el proyecto (próximamente)
- **Hacktoberfest**: Participación anual para fomentar contribuciones

## 🌱 Proyectos para Principiantes

Si eres nuevo en el proyecto, aquí hay algunas áreas donde puedes comenzar:

- **Documentación**: Mejora de guías, corrección de errores, traducciones
- **Ejemplos**: Crea ejemplos adicionales de uso de la plataforma
- **Pruebas**: Añade tests o mejora la cobertura actual
- **Dashboards**: Crea dashboards adicionales para Grafana
- **Issues etiquetados como "good first issue"**: Problemas seleccionados para nuevos contribuyentes

## 🎓 Recursos de Aprendizaje

Para aprender más sobre las tecnologías utilizadas:

- [Guía de OpenTofu](https://opentofu.org/docs/) - Aprende sobre infraestructura como código
- [K3s Documentation](https://docs.k3s.io/) - Kubernetes ligero
- [Prometheus & Grafana](https://prometheus.io/docs/) - Observabilidad
- [GitOps Principles](https://www.gitops.tech/) - Flujos de trabajo basados en Git

## 💼 Casos de Uso y Testimonios

Nos encantaría conocer cómo estás utilizando este proyecto:

- Comparte tu experiencia en GitHub Discussions
- Envía un Pull Request añadiendo tu caso de uso a nuestra galería
- Contribuye con mejoras basadas en tu uso particular

## 🌟 Reconocimiento de Contribuyentes

Valoramos enormemente todas las contribuciones al proyecto:

- Todos los contribuyentes son listados en nuestro archivo CONTRIBUTORS.md
- Las contribuciones significativas son destacadas en las notas de lanzamiento
- Los contribuyentes regulares pueden ser invitados a unirse como mantenedores
```

## 17. Apéndices y Referencia

### 17.1 Glosario de términos

```markdown
# Glosario de Términos

## A

**API Gateway** - Servicio que actúa como punto de entrada para las APIs, gestionando tráfico, autenticación y más.

**ArgoCD** - Herramienta de GitOps para Kubernetes que sincroniza automáticamente el estado deseado (en Git) con el estado actual del cluster.

**AWS (Amazon Web Services)** - Plataforma de servicios cloud de Amazon.

## C

**CI/CD (Continuous Integration/Continuous Deployment)** - Prácticas de desarrollo que automatizan la integración y despliegue de código.

**Cilium** - Solución de networking basada en eBPF para Kubernetes que proporciona seguridad y observabilidad.

**Cloud-Native** - Enfoque arquitectónico que aprovecha las capacidades de la nube.

**ConfigMap** - Objeto de Kubernetes para almacenar datos de configuración no confidenciales.

## D

**DaemonSet** - Tipo de workload de Kubernetes que garantiza que todos (o algunos) nodos ejecuten una copia de un pod.

**Deployment** - Objeto de Kubernetes que proporciona actualizaciones declarativas para pods y ReplicaSets.

**Docker** - Plataforma para desarrollar, enviar y ejecutar aplicaciones en contenedores.

**Drone CI** - Plataforma de CI/CD basada en contenedores.

## E

**eBPF (Extended Berkeley Packet Filter)** - Tecnología que permite ejecutar programas en el espacio de kernel de Linux.

**Endpoint** - URL de un API o servicio web.

## G

**GitOps** - Metodología que utiliza Git como fuente única de verdad para infraestructura y aplicaciones.

**Grafana** - Plataforma de visualización y monitoreo.

**GitLab/GitHub/Gitea** - Plataformas de gestión de repositorios Git.

## H

**Helm** - Gestor de paquetes para Kubernetes.

**HorizontalPodAutoscaler** - Recurso de Kubernetes que escala automáticamente el número de pods.

## I

**IaC (Infrastructure as Code)** - Gestión y aprovisionamiento de infraestructura a través de archivos de configuración.

**Ingress** - Objeto de Kubernetes que gestiona el acceso externo a los servicios dentro del cluster.

## K

**K3s** - Distribución ligera de Kubernetes optimizada para IoT y edge computing.

**K3d** - Herramienta para ejecutar K3s en contenedores Docker.

**Kubernetes** - Sistema de orquestación de contenedores de código abierto.

## L

**Loki** - Sistema de agregación de logs.

**Longhorn** - Solución de almacenamiento distribuido para Kubernetes.

## M

**Microservices** - Enfoque arquitectónico donde una aplicación se construye como un conjunto de servicios pequeños.

**MinIO** - Servidor de almacenamiento de objetos compatible con Amazon S3.

**Multi-Cloud** - Estrategia que utiliza servicios de múltiples proveedores cloud.

## N

**Namespace** - Mecanismo para dividir recursos de cluster en Kubernetes.

**Network Policy** - Especificación de cómo los grupos de pods pueden comunicarse entre sí.

## O

**OpenTofu** - Fork open source de Terraform para infraestructura como código.

**OPA (Open Policy Agent)** - Motor de políticas para servicios en la nube.

**Observabilidad** - Capacidad de medir el estado de un sistema a partir de sus salidas.

## P

**Pod** - La unidad más pequeña y básica en Kubernetes, representa uno o más contenedores.

**Prometheus** - Sistema de monitoreo y alerta.

**PVC (PersistentVolumeClaim)** - Solicitud de almacenamiento persistente en Kubernetes.

## R

**RBAC (Role-Based Access Control)** - Método para regular el acceso a recursos basado en roles.

**ReplicaSet** - Garantiza que un número especificado de réplicas de pod estén ejecutándose en todo momento.

## S

**Secret** - Objeto de Kubernetes para almacenar información confidencial.

**Service** - Abstracción que define un conjunto lógico de pods y una política para acceder a ellos.

**Service Mesh** - Capa de infraestructura para gestionar comunicaciones entre servicios.

**StatefulSet** - Workload para aplicaciones stateful en Kubernetes.

## T

**TLS (Transport Layer Security)** - Protocolo criptográfico para comunicaciones seguras.

**Terraform** - Herramienta de infraestructura como código.

## V

**Vault** - Herramienta para gestión de secretos.

**Volume** - Directorio accesible a los contenedores en un pod.

## Z

**Zero Trust** - Modelo de seguridad que requiere verificación estricta para cada acceso a recursos.
```

### 17.2 Referencias y Enlaces útiles

```markdown
# Referencias y Enlaces Útiles

## OpenTofu y Terraform

- [OpenTofu Official Website](https://opentofu.org/)
- [OpenTofu GitHub Repository](https://github.com/opentofu/opentofu)
- [HashiCorp Terraform Documentation](https://www.terraform.io/docs) (Información complementaria)
- [Terraform Best Practices](https://www.terraform-best-practices.com/)

## Kubernetes y K3s

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [K3s Documentation](https://docs.k3s.io/)
- [K3d GitHub Repository](https://github.com/k3d-io/k3d)
- [Kubernetes Patterns](https://k8spatterns.io/)
- [CNCF Landscape](https://landscape.cncf.io/)

## Herramientas de Observabilidad

- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [Loki Documentation](https://grafana.com/docs/loki/latest/)
- [OpenTelemetry Documentation](https://opentelemetry.io/docs/)

## Networking y Seguridad

- [Cilium Documentation](https://docs.cilium.io/)
- [Vault Documentation](https://developer.hashicorp.com/vault/docs)
- [OPA/Gatekeeper Documentation](https://open-policy-agent.github.io/gatekeeper/website/)
- [Cert-Manager Documentation](https://cert-manager.io/docs/)

## CI/CD y GitOps

- [Gitea Documentation](https://docs.gitea.io/)
- [Drone CI Documentation](https://docs.drone.io/)
- [FluxCD Documentation](https://fluxcd.io/docs/) (Alternativa GitOps)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/) (Alternativa GitOps)

## Almacenamiento

- [Longhorn Documentation](https://longhorn.io/docs/)
- [MinIO Documentation](https://min.io/docs/minio/container/index.html)

## Cloud Providers

- [AWS Documentation](https://docs.aws.amazon.com/)
- [Oracle Cloud Documentation](https://docs.oracle.com/en-us/iaas/Content/home.htm)
- [Google Cloud Documentation](https://cloud.google.com/docs)
- [Microsoft Azure Documentation](https://learn.microsoft.com/en-us/azure/)

## Libros Recomendados

- "Kubernetes: Up & Running" - Kelsey Hightower, Brendan Burns, Joe Beda
- "Cloud Native Infrastructure" - Justin Garrison, Kris Nova
- "Infrastructure as Code" - Kief Morris
- "Site Reliability Engineering" - Google
- "The DevOps Handbook" - Gene Kim, Jez Humble, Patrick Debois, John Willis

## Blogs y Recursos Adicionales

- [CNCF Blog](https://www.cncf.io/blog/)
- [The New Stack](https://thenewstack.io/)
- [KubeWeekly Newsletter](https://www.cncf.io/kubeweekly/)
- [Last Week in Kubernetes Development](https://lwkd.info/)
- [DevOps Toolkit YouTube Channel](https://www.youtube.com/c/DevOpsToolkit)
- [TGI Kubernetes](https://www.youtube.com/watch?v=9YYeE-bMWv8&list=PL7bmigfV0EqQzxcNpmcdTJ9eFRPBe-iZa)

## Comunidades

- [CNCF Slack](https://slack.cncf.io/)
- [Kubernetes Forum](https://discuss.kubernetes.io/)
- [OpenTofu Discussions](https://github.com/opentofu/opentofu/discussions)
- [Reddit r/kubernetes](https://www.reddit.com/r/kubernetes/)
- [Reddit r/devops](https://www.reddit.com/r/devops/)
- [DevOps Stack Exchange](https://devops.stackexchange.com/)
```

### 17.3 Lista de verificación de seguridad

```markdown
# Lista de Verificación de Seguridad

Esta lista te ayudará a asegurar que tu implementación sigue las mejores prácticas de seguridad. Úsala regularmente para auditar tu plataforma.

## 🔒 Autenticación y Autorización

- [ ] Credenciales por defecto cambiadas para todos los componentes
- [ ] RBAC configurado correctamente en Kubernetes
- [ ] Autenticación multifactor habilitada donde sea posible
- [ ] Tokens y secretos con tiempo de expiración adecuado
- [ ] Cuentas de servicio con privilegios mínimos necesarios
- [ ] Revisión periódica de permisos y accesos

## 🛡️ Seguridad de Kubernetes

- [ ] API Server accesible solo desde redes confiables
- [ ] Pod Security Standards aplicados a todos los namespaces
- [ ] Network Policies implementadas para limitar comunicación entre pods
- [ ] Seccomp y AppArmor habilitados para contenedores críticos
- [ ] PodSecurityContext configurado para evitar privilegios excesivos
- [ ] Recursos críticos protegidos con admission controllers
- [ ] Kubernetes Dashboard protegido o deshabilitado

## 🔐 Gestión de Secretos

- [ ] Secrets de Kubernetes encriptados en reposo
- [ ] Secrets rotados regularmente
- [ ] HashiCorp Vault configurado para secretos sensibles
- [ ] Secrets inyectados en runtime (no en imágenes o código)
- [ ] Política de rotación de secretos documentada
- [ ] Acceso a secretos auditado y registrado

## 🔍 Imágenes y Contenedores

- [ ] Imágenes escaneadas en busca de vulnerabilidades (Trivy)
- [ ] Imágenes basadas en distros mínimas (Alpine, Distroless)
- [ ] Imágenes firmadas y verificadas
- [ ] Contenedores ejecutados como usuario no root
- [ ] Imágenes sin secretos o datos sensibles
- [ ] Registry de contenedores privado y seguro

## 🧪 CI/CD y Cadena de Suministro

- [ ] Pipeline CI/CD seguro con escaneo de vulnerabilidades
- [ ] Validación de manifiestos y IaC antes del despliegue
- [ ] Separación de entornos (desarrollo, staging, producción)
- [ ] Artefactos y despliegues firmados
- [ ] Rollback automatizado en caso de fallos
- [ ] Verificación de integridad de dependencias

## 📡 Networking

- [ ] TLS habilitado para todo el tráfico externo
- [ ] Certificados gestionados y renovados automáticamente
- [ ] Tráfico entre servicios encriptado (mTLS)
- [ ] Exposición mínima de servicios al exterior
- [ ] Reglas de firewall restrictivas
- [ ] WAF configurado para APIs públicas

## 🖥️ Infraestructura

- [ ] Actualizaciones de seguridad aplicadas regularmente
- [ ] Hardening de nodos según benchmarks de seguridad
- [ ] Acceso SSH limitado y basado en claves
- [ ] Segmentación de red implementada
- [ ] Logs centralizados y protegidos
- [ ] Monitoreo de seguridad activo

## 📊 Monitoreo y Detección

- [ ] Logging completo de accesos y cambios
- [ ] Alertas configuradas para comportamientos sospechosos
- [ ] Monitoreo de integridad de archivos críticos
- [ ] Detección de anomalías implementada
- [ ] Retención de logs adecuada para análisis forense
- [ ] Monitoreo de eventos de seguridad de Kubernetes

## 🚨 Respuesta a Incidentes

- [ ] Plan de respuesta a incidentes documentado
- [ ] Roles y responsabilidades definidos para emergencias
- [ ] Proceso de escalamiento claro
- [ ] Procedimientos de recuperación probados
- [ ] Backups regulares y verificados
- [ ] Simulacros de seguridad realizados periódicamente

## 🔍 Cumplimiento y Gobernanza

- [ ] Políticas de seguridad documentadas
- [ ] Controles de cumplimiento mapeados
- [ ] Inventario de activos y datos mantenido
- [ ] Clasificación de datos implementada
- [ ] Revisiones de seguridad programadas
- [ ] Matriz de responsabilidad definida

## 🛡️ Consideraciones Específicas para Multi-Cloud

- [ ] IAM consistente entre proveedores
- [ ] Secretos no compartidos entre entornos cloud
- [ ] Redes aisladas entre proveedores
- [ ] Estrategia de DR entre clouds documentada
- [ ] Monitoreo centralizado para todos los entornos
- [ ] Capacidades de seguridad específicas de cada proveedor aprovechadas
```

### 17.4 Lista de herramientas alternativas

```markdown
# Herramientas Alternativas para la Plataforma

Esta lista proporciona alternativas para cada componente principal de la plataforma, permitiéndote adaptar la solución según tus necesidades.

## 🏗️ Infraestructura como Código

| Componente Actual | Alternativas                     | Consideraciones                                      |
|-------------------|----------------------------------|-----------------------------------------------------|
| **OpenTofu**      | Pulumi                           | Permite usar lenguajes de programación completos     |
|                   | AWS CDK / CDK for Terraform      | Experiencia de desarrollo más cercana al código      |
|                   | Crossplane                       | IaC directamente en Kubernetes                       |
|                   | Ansible                          | Enfoque más imperativo para automatización           |

## 🎛️ Kubernetes y Orquestación

| Componente Actual | Alternativas                     | Consideraciones                                      |
|-------------------|----------------------------------|-----------------------------------------------------|
| **K3s/K3d**       | MicroK8s                         | Alternativa ligera de Canonical/Ubuntu              |
|                   | Kind                             | Excelente para desarrollo y testing                  |
|                   | Minikube                         | Bien documentado, más recursos necesarios            |
|                   | Docker Swarm                     | Más simple pero menos funcionalidades                |

## 🌐 Networking

| Componente Actual | Alternativas                     | Consideraciones                                      |
|-------------------|----------------------------------|-----------------------------------------------------|
| **Cilium**        | Calico                           | Buena seguridad de red y rendimiento                 |
|                   | Flannel                          | Más simple, menos funciones avanzadas                |
|                   | Weave Net                        | Fácil configuración, encriptación                    |
|                   | Kube-OVN                         | Basado en Open vSwitch, funciones avanzadas          |

## 💾 Almacenamiento

| Componente Actual | Alternativas                     | Consideraciones                                      |
|-------------------|----------------------------------|-----------------------------------------------------|
| **Longhorn**      | OpenEBS                          | Otra solución CNS para Kubernetes                    |
|                   | Rook-Ceph                        | Más complejo, funciones empresariales                |
|                   | Portworx                         | Solución empresarial (tiene costos)                 |
|                   | Local Path Provisioner           | Solución muy simple para entornos de desarrollo      |
| **MinIO**         | Ceph Object Gateway              | Más complejo, funciones empresariales                |
|                   | Garage                           | Almacenamiento S3 alternativo, más simple            |
|                   | Lakestore                        | Enfoque a data lakes                                 |
|                   | Cloudserver                      | Compatible con S3, flexible                          |

## 👁️ Observabilidad

| Componente Actual | Alternativas                     | Consideraciones                                      |
|-------------------|----------------------------------|-----------------------------------------------------|
| **Prometheus**    | Thanos                           | Prometheus con almacenamiento distribuido            |
|                   | Victoria Metrics                 | Muy eficiente en recursos                            |
|                   | M3DB                             | Escalabilidad horizontal                             |
|                   | Cortex                           | Prometheus como servicio                             |
| **Grafana**       | Chronograf                       | Parte del stack TICK                                 |
|                   | Kibana                           | Si usas stack ELK                                    |
|                   | Superset                         | Visualización de datos más avanzada                  |
|                   | Redash                           | Enfocado en dashboards empresariales                 |
| **Loki**          | Elasticsearch + Fluentd          | Stack ELK, más maduro pero más recursos              |
|                   | Vector                           | Pipeline de logs moderna y eficiente                 |
|                   | OpenSearch                       | Fork de Elasticsearch                                |
|                   | Graylog                          | Enfocado en análisis de logs                         |

## 🔄 CI/CD y Control de Versiones

| Componente Actual | Alternativas                     | Consideraciones                                      |
|-------------------|----------------------------------|-----------------------------------------------------|
| **Gitea**         | Gitlab CE                        | Más completo pero requiere más recursos              |
|                   | Gogs                             | Aún más ligero que Gitea                             |
|                   | Sourcehut                        | Minimalista y ligero                                 |
|                   | Phabricator                      | Suite completa de herramientas                       |
| **Drone CI**      | Jenkins                          | Muy flexible pero más complejo                        |
|                   | Tekton                           | Nativo de Kubernetes, componible                      |
|                   | ArgoCD                           | GitOps, más que simple CI                             |
|                   | Woodpecker CI                    | Fork de Drone, compatible                             |

## 🔒 Seguridad

| Componente Actual | Alternativas                     | Consideraciones                                      |
|-------------------|----------------------------------|-----------------------------------------------------|
| **Vault**         | SOPS                             | Más simple, enfocado en archivos encriptados         |
|                   | Sealed Secrets                   | Específico para secretos de Kubernetes               |
|                   | External Secrets Operator        | Integración con proveedores externos                 |
|                   | Infisical                        | Gestión de secretos para equipo                      |
| **OPA/Gatekeeper**| Kyverno                          | Políticas más simples para Kubernetes                |
|                   | Kubewarden                       | Políticas en WebAssembly                             |
|                   | Karmor                           | Enfocado en seguridad de aplicaciones                |
|                   | Ratify                           | Verificación de artefactos                           |
| **Cert-Manager**  | Smallstep                        | PKI completa                                         |
|                   | Vault PKI                        | Si ya usas Vault                                     |
|                   | CFSSL                            | PKI simple de Cloudflare                             |
|                   | OpenSSL Automation               | Scripts personalizados                               |

## 🧩 Soluciones Adicionales

| Categoría         | Opciones                         | Caso de uso                                          |
|-------------------|----------------------------------|-----------------------------------------------------|
| **API Gateway**   | Kong                             | Gateway completo con plugins                         |
|                   | Traefik                          | Fácil integración con Kubernetes                     |
|                   | APISIX                           | Alto rendimiento, escalable                          |
|                   | Envoy                            | Proxy de servicio avanzado                           |
| **Service Mesh**  | Linkerd                          | Más simple que Istio                                 |
|                   | Istio                            | Completo pero complejo                               |
|                   | Kuma                             | Universal service mesh                               |
|                   | Consul Connect                   | De HashiCorp                                         |
| **Serverless**    | OpenFaaS                         | Simple y fácil de usar                               |
|                   | Knative                          | Estándar en Kubernetes                               |
|                   | Kubeless                         | Nativo de Kubernetes                                 |
|                   | Fission                          | Enfocado en velocidad                                |
| **Bases de datos**| PostgreSQL                       | Relacional completa                                  |
|                   | MySQL/MariaDB                    | Alternativa relacional popular                       |
|                   | MongoDB                          | Documento NoSQL                                      |
|                   | ClickHouse                       | Analítica columnar                                   |
```

## 18. Conclusión y Agradecimientos

### 18.1 Resumen del proyecto y próximos pasos

```markdown
# Conclusión y Próximos Pasos

## 🎯 Resumen del Proyecto

A lo largo de esta guía, hemos desarrollado una plataforma multi-cloud completa con costo cero, utilizando herramientas open source de calidad empresarial. Esta plataforma proporciona:

- **Infraestructura como código** con OpenTofu
- **Orquestación de contenedores** con Kubernetes (K3s/K3d)
- **Almacenamiento escalable** con Longhorn y MinIO
- **DevOps y CI/CD** con Gitea y Drone
- **Observabilidad integral** con Prometheus, Grafana y Loki
- **Seguridad robusta** con Vault, OPA y Cert-Manager
- **Documentación detallada** para despliegue y operación

Todo esto se ha diseñado para ejecutarse localmente sin costo y con la capacidad de migrar fácilmente a proveedores cloud cuando sea necesario.

## 🚀 Próximos Pasos Recomendados

### Para todos los usuarios:

1. **Desplegar la plataforma completa** siguiendo la guía paso a paso
2. **Experimentar con la aplicación demo** incluida
3. **Personalizar la configuración** para tus necesidades específicas
4. **Explorar los componentes adicionales** mencionados en la documentación

### Para desarrolladores:

1. **Crear nuevas aplicaciones** utilizando la plataforma como base
2. **Contribuir con mejoras** al proyecto
3. **Explorar patrones avanzados** de cloud-native
4. **Compartir casos de uso** y experiencias con la comunidad

### Para equipos:

1. **Adaptar la plataforma** a casos de uso empresariales
2. **Implementar GitOps** para gestión de configuración
3. **Desarrollar políticas específicas** para tu organización
4. **Extender con componentes adicionales** para necesidades especiales

### Hacia el Cloud:

Cuando estés listo para migrar a un entorno cloud:

1. **Revisar la guía de migración a AWS** (o a otros proveedores)
2. **Comenzar con un entorno híbrido** manteniendo componentes críticos locales
3. **Aplicar optimizaciones de costos** específicas de cada proveedor
4. **Implementar resiliencia multi-región/multi-cloud** para alta disponibilidad

## 🛣️ Visión a largo plazo

Esta plataforma representa sólo el comienzo de lo que se puede lograr con herramientas open source en entornos multi-cloud. Algunas direcciones futuras incluyen:

- **Federación de clusters** para gestión unificada
- **Mesh networking** entre clouds y on-premises
- **Automatización avanzada** para optimización continua
- **Integración de ML/AI** para operaciones inteligentes
- **Edge computing** como extensión natural de la plataforma

## 📈 Midiendo el Éxito

El éxito de tu implementación puede medirse por:

- **Velocidad de despliegue** de nuevas aplicaciones
- **Consistencia entre entornos** (desarrollo, staging, producción)
- **Tiempo medio de recuperación** ante incidentes
- **Nivel de automatización** de operaciones
- **Costo total** comparado con soluciones comerciales

Recuerda que la verdadera potencia de una plataforma cloud-native no está solo en las herramientas utilizadas, sino en las prácticas y la cultura que fomenta.

¡Disfruta construyendo y evolucionando tu plataforma multi-cloud!
```

### 18.2 Agradecimientos y conclusión final

```markdown
# Agradecimientos y Conclusión Final

## 🙏 Agradecimientos

Este proyecto no sería posible sin el increíble ecosistema de software open source y las comunidades que lo mantienen. Queremos expresar nuestro más sincero agradecimiento a:

### Comunidades Open Source

- **La comunidad Kubernetes** por crear el estándar de facto para orquestación de contenedores
- **El equipo de K3s/K3d** por hacer Kubernetes accesible para entornos ligeros
- **La comunidad OpenTofu** por mantener una alternativa open source robusta para IaC
- **El ecosistema CNCF** por fomentar y apoyar proyectos cloud-native innovadores
- **Todos los mantenedores** de las herramientas y componentes utilizados en este proyecto

### Contribuciones