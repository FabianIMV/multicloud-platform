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
