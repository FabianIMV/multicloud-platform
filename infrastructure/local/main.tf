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
