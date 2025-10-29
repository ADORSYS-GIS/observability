module "monitoring-secrets" {
  source  = "blackbird-cloud/deployment/helm"
  version = "~> 1.0"

  name             = "monitoring-secrets"
  namespace        = kubernetes_namespace.monitoring_namespace.metadata[0].name
  create_namespace = false

  repository    = "https://bedag.github.io/helm-charts"
  chart         = "raw"
  chart_version = "2.0.0"

  values = [
    templatefile("${path.module}/files/monitoring-secrets.values.yaml", {
      loki_bucket         = var.loki_bucket
      loki_s3_access_key  = var.loki_s3_access_key
      loki_s3_secret_key  = var.loki_s3_secret_key
      tempo_bucket        = var.tempo_bucket
      tempo_s3_access_key = var.tempo_s3_access_key
      tempo_s3_secret_key = var.tempo_s3_secret_key
      ns_monitoring       = kubernetes_namespace.monitoring_namespace.metadata[0].name
    })
  ]

  cleanup_on_fail = false
  wait            = false
}

resource "kubernetes_namespace" "monitoring_namespace" {
  metadata {
    name = "monitoring"
  }
}
