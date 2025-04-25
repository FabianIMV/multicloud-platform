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
