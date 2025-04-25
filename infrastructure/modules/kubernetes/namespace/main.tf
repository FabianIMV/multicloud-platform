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
