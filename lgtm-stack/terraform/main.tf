terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
  }

  # Production Best Practice: Store state remotely
  # backend "gcs" {
  #   bucket  = "YOUR_TF_STATE_BUCKET"
  #   prefix  = "terraform/state"
  # }
}

provider "google" {
  project = var.project_id != "" ? var.project_id : null
  region  = var.region
}

# AWS provider - required by EKS module even when not used (count=0)
# Skip validation to avoid credential errors when deploying to GKE
provider "aws" {
  region                      = var.aws_region
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  access_key                  = "mock_access_key"
  secret_key                  = "mock_secret_key"
}

# Data sources for GKE cluster authentication
data "google_client_config" "default" {
  count = var.cloud_provider == "gke" ? 1 : 0
}

data "google_container_cluster" "monitoring" {
  count    = var.cloud_provider == "gke" ? 1 : 0
  name     = var.cluster_name
  location = var.cluster_location != "" ? var.cluster_location : var.region
}

# The kubernetes and helm providers will use explicit credentials for GKE
# to avoid connection errors in CI environments.
provider "kubernetes" {
  host                   = var.cloud_provider == "gke" ? "https://${data.google_container_cluster.monitoring[0].endpoint}" : null
  token                  = var.cloud_provider == "gke" ? data.google_client_config.default[0].access_token : null
  cluster_ca_certificate = var.cloud_provider == "gke" ? base64decode(data.google_container_cluster.monitoring[0].master_auth[0].cluster_ca_certificate) : null
}

provider "helm" {
  kubernetes {
    host                   = var.cloud_provider == "gke" ? "https://${data.google_container_cluster.monitoring[0].endpoint}" : null
    token                  = var.cloud_provider == "gke" ? data.google_client_config.default[0].access_token : null
    cluster_ca_certificate = var.cloud_provider == "gke" ? base64decode(data.google_container_cluster.monitoring[0].master_auth[0].cluster_ca_certificate) : null
  }
}

# Modular Cloud Resources
module "cloud_gke" {
  count  = var.cloud_provider == "gke" ? 1 : 0
  source = "./modules/cloud-gke"

  project_id               = var.project_id
  region                   = var.region
  service_account_name     = var.gcp_service_account_name
  k8s_namespace            = var.namespace
  k8s_service_account_name = var.k8s_service_account_name
  environment              = var.environment
}

module "cloud_eks" {
  count  = var.cloud_provider == "eks" ? 1 : 0
  source = "./modules/cloud-eks"

  bucket_prefix            = var.cluster_name
  cluster_name             = var.cluster_name
  eks_oidc_provider_arn    = var.eks_oidc_provider_arn
  k8s_namespace            = var.namespace
  k8s_service_account_name = var.k8s_service_account_name
}

module "cloud_generic" {
  count  = var.cloud_provider == "generic" ? 1 : 0
  source = "./modules/cloud-generic"

  k8s_namespace = var.namespace
}

# Local variables for unified access to cloud resources
locals {
  storage_config = {
    type = var.cloud_provider

    # GKE values
    gcp_sa_email = var.cloud_provider == "gke" ? module.cloud_gke[0].service_account_email : ""
    buckets      = var.cloud_provider == "gke" ? module.cloud_gke[0].storage_buckets : {}

    # EKS values
    aws_role_arn = var.cloud_provider == "eks" ? module.cloud_eks[0].irsa_role_arn : ""
    s3_buckets   = var.cloud_provider == "eks" ? module.cloud_eks[0].storage_buckets : {}
  }
}

# Kubernetes Namespace
resource "kubernetes_namespace" "observability" {
  metadata {
    name = var.namespace

    labels = {
      name       = var.namespace
      managed-by = "terraform"
    }
  }
}

# Kubernetes Service Account
resource "kubernetes_service_account" "observability_sa" {
  metadata {
    name      = var.k8s_service_account_name
    namespace = kubernetes_namespace.observability.metadata[0].name

    annotations = merge(
      var.cloud_provider == "gke" ? { "iam.gke.io/gcp-service-account" = local.storage_config.gcp_sa_email } : {},
      var.cloud_provider == "eks" ? { "eks.amazonaws.com/role-arn" = local.storage_config.aws_role_arn } : {}
    )

    labels = {
      managed-by = "terraform"
    }
  }
}

# Cert-Manager Module
module "cert_manager" {
  providers = {
    kubernetes = kubernetes
    helm       = helm
  }

  source = "../../cert-manager/terraform"

  install_cert_manager = var.install_cert_manager
  cert_manager_version = var.cert_manager_version
  release_name         = var.cert_manager_release_name
  namespace            = var.cert_manager_namespace

  letsencrypt_email = var.letsencrypt_email
  cert_issuer_name  = var.cert_issuer_name
  cert_issuer_kind  = var.cert_issuer_kind
  # If Kind is Issuer, it must be in the observability namespace to be used by the ingress in that namespace.
  # If Kind is ClusterIssuer, this variable is ignored by the module logic.
  issuer_namespace   = var.namespace
  ingress_class_name = var.ingress_class_name

  # Ensure namespace exists before issuer creation (handled inside module)
}

# Ingress Controller Module
module "ingress_nginx" {
  source = "../../ingress-controller/terraform"

  install_nginx_ingress = var.install_nginx_ingress
  nginx_ingress_version = var.nginx_ingress_version
  release_name          = var.nginx_ingress_release_name
  namespace             = var.nginx_ingress_namespace
  ingress_class_name    = var.ingress_class_name
}

# Loki
resource "helm_release" "loki" {
  name       = "monitoring-loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  namespace  = kubernetes_namespace.observability.metadata[0].name
  version    = var.loki_version

  values = [
    templatefile("values/loki-values.yaml", {
      cloud_provider            = var.cloud_provider
      gcp_service_account_email = local.storage_config.gcp_sa_email
      aws_role_arn              = local.storage_config.aws_role_arn
      k8s_service_account_name  = kubernetes_service_account.observability_sa.metadata[0].name

      # Storage buckets
      loki_chunks_bucket = var.cloud_provider == "gke" ? local.storage_config.buckets["loki-chunks"] : (var.cloud_provider == "eks" ? local.storage_config.s3_buckets["loki-chunks"] : "")
      loki_ruler_bucket  = var.cloud_provider == "gke" ? local.storage_config.buckets["loki-ruler"] : (var.cloud_provider == "eks" ? local.storage_config.s3_buckets["loki-ruler"] : "")

      aws_region            = var.aws_region
      loki_schema_from_date = var.loki_schema_from_date
      monitoring_domain     = var.monitoring_domain
      ingress_class_name    = var.ingress_class_name
      cert_issuer_name      = var.cert_issuer_name
    })
  ]

  depends_on = [
    kubernetes_service_account.observability_sa,
    module.cloud_gke,
    module.cloud_eks
  ]
}

# Mimir
resource "helm_release" "mimir" {
  name       = "monitoring-mimir"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "mimir-distributed"
  namespace  = kubernetes_namespace.observability.metadata[0].name
  version    = var.mimir_version

  values = [
    templatefile("values/mimir-values.yaml", {
      cloud_provider            = var.cloud_provider
      gcp_service_account_email = local.storage_config.gcp_sa_email
      aws_role_arn              = local.storage_config.aws_role_arn
      k8s_service_account_name  = kubernetes_service_account.observability_sa.metadata[0].name

      # Storage buckets
      mimir_blocks_bucket       = var.cloud_provider == "gke" ? local.storage_config.buckets["mimir-blocks"] : (var.cloud_provider == "eks" ? local.storage_config.s3_buckets["mimir-blocks"] : "")
      mimir_ruler_bucket        = var.cloud_provider == "gke" ? local.storage_config.buckets["mimir-ruler"] : (var.cloud_provider == "eks" ? local.storage_config.s3_buckets["mimir-ruler"] : "")
      mimir_alertmanager_bucket = var.cloud_provider == "gke" ? local.storage_config.buckets["mimir-ruler"] : (var.cloud_provider == "eks" ? local.storage_config.s3_buckets["mimir-ruler"] : "")

      aws_region         = var.aws_region
      monitoring_domain  = var.monitoring_domain
      ingress_class_name = var.ingress_class_name
      cert_issuer_name   = var.cert_issuer_name
    })
  ]

  depends_on = [
    kubernetes_service_account.observability_sa,
    module.cloud_gke,
    module.cloud_eks
  ]
}

# Tempo
resource "helm_release" "tempo" {
  name       = "monitoring-tempo"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "tempo-distributed"
  namespace  = kubernetes_namespace.observability.metadata[0].name
  version    = var.tempo_version

  values = [
    templatefile("values/tempo-values.yaml", {
      cloud_provider            = var.cloud_provider
      gcp_service_account_email = local.storage_config.gcp_sa_email
      aws_role_arn              = local.storage_config.aws_role_arn
      k8s_service_account_name  = kubernetes_service_account.observability_sa.metadata[0].name

      # Storage buckets
      tempo_traces_bucket = var.cloud_provider == "gke" ? local.storage_config.buckets["tempo-traces"] : (var.cloud_provider == "eks" ? local.storage_config.s3_buckets["tempo-traces"] : "")

      aws_region         = var.aws_region
      monitoring_domain  = var.monitoring_domain
      ingress_class_name = var.ingress_class_name
      cert_issuer_name   = var.cert_issuer_name
    })
  ]

  depends_on = [
    kubernetes_service_account.observability_sa,
    module.cloud_gke,
    module.cloud_eks
  ]
}

# Prometheus
resource "helm_release" "prometheus" {
  name       = "monitoring-prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus"
  namespace  = kubernetes_namespace.observability.metadata[0].name
  version    = var.prometheus_version

  values = [
    templatefile("values/prometheus-values.yaml", {
      cloud_provider            = var.cloud_provider
      gcp_service_account_email = local.storage_config.gcp_sa_email
      aws_role_arn              = local.storage_config.aws_role_arn
      aws_region                = var.aws_region
      k8s_service_account_name  = kubernetes_service_account.observability_sa.metadata[0].name
      monitoring_domain         = var.monitoring_domain
      cluster_name              = var.cluster_name
      environment               = var.environment
      project_id                = var.project_id
      region                    = var.region
      ingress_class_name        = var.ingress_class_name
      cert_issuer_name          = var.cert_issuer_name
    })
  ]

  depends_on = [
    helm_release.mimir,
    helm_release.loki
  ]

  timeout = 600
}

# Grafana
resource "helm_release" "grafana" {
  name       = "monitoring-grafana"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "grafana"
  namespace  = kubernetes_namespace.observability.metadata[0].name
  version    = var.grafana_version

  values = [
    templatefile("values/grafana-values.yaml", {
      cloud_provider            = var.cloud_provider
      gcp_service_account_email = local.storage_config.gcp_sa_email
      aws_role_arn              = local.storage_config.aws_role_arn
      aws_region                = var.aws_region
      k8s_service_account_name  = kubernetes_service_account.observability_sa.metadata[0].name
      monitoring_domain         = var.monitoring_domain
      grafana_admin_password    = var.grafana_admin_password
      ingress_class_name        = var.ingress_class_name
      cert_issuer_name          = var.cert_issuer_name
    })
  ]

  depends_on = [
    helm_release.prometheus,
    helm_release.loki,
    helm_release.mimir,
    helm_release.tempo
  ]

  timeout = 600
}

# Monitoring Ingress
resource "kubernetes_ingress_v1" "monitoring_stack" {
  metadata {
    name      = "monitoring-stack-ingress"
    namespace = kubernetes_namespace.observability.metadata[0].name
    annotations = {
      "kubernetes.io/ingress.class"                       = var.ingress_class_name
      "cert-manager.io/issuer"                            = var.cert_issuer_name
      "nginx.ingress.kubernetes.io/ssl-redirect"          = "true"
      "nginx.ingress.kubernetes.io/backend-protocol"      = "HTTP"
      "nginx.ingress.kubernetes.io/proxy-connect-timeout" = "300"
      "nginx.ingress.kubernetes.io/proxy-send-timeout"    = "300"
      "nginx.ingress.kubernetes.io/proxy-read-timeout"    = "300"
      "nginx.ingress.kubernetes.io/proxy-body-size"       = "50m"
    }
  }

  spec {
    tls {
      hosts = [
        "grafana.${var.monitoring_domain}",
        "loki.${var.monitoring_domain}",
        "mimir.${var.monitoring_domain}",
        "tempo.${var.monitoring_domain}",
        "tempo-push.${var.monitoring_domain}",
        "prometheus.${var.monitoring_domain}"
      ]
      secret_name = "monitoring-tls"
    }

    # Grafana
    rule {
      host = "grafana.${var.monitoring_domain}"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "monitoring-grafana"
              port {
                number = 80
              }
            }
          }
        }
      }
    }

    # Loki
    rule {
      host = "loki.${var.monitoring_domain}"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "monitoring-loki-gateway"
              port {
                number = 80
              }
            }
          }
        }
      }
    }

    # Mimir
    rule {
      host = "mimir.${var.monitoring_domain}"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "monitoring-mimir-nginx"
              port {
                number = 80
              }
            }
          }
        }
      }
    }

    # Tempo Query
    rule {
      host = "tempo.${var.monitoring_domain}"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "monitoring-tempo-query-frontend"
              port {
                number = 3200
              }
            }
          }
        }
      }
    }

    # Tempo Push
    rule {
      host = "tempo-push.${var.monitoring_domain}"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "monitoring-tempo-distributor"
              port {
                number = 4318
              }
            }
          }
        }
      }
    }

    # Prometheus
    rule {
      host = "prometheus.${var.monitoring_domain}"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "monitoring-prometheus-server"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    helm_release.grafana,
    module.cert_manager
  ]
}

# Tempo gRPC Ingress
resource "kubernetes_ingress_v1" "tempo_grpc" {
  metadata {
    name      = "monitoring-stack-ingress-grpc"
    namespace = kubernetes_namespace.observability.metadata[0].name
    annotations = {
      "kubernetes.io/ingress.class"                  = var.ingress_class_name
      "cert-manager.io/issuer"                       = var.cert_issuer_name
      "nginx.ingress.kubernetes.io/ssl-redirect"     = "true"
      "nginx.ingress.kubernetes.io/backend-protocol" = "GRPC"
    }
  }

  spec {
    tls {
      hosts = [
        "tempo-grpc.${var.monitoring_domain}"
      ]
      secret_name = "monitoring-grpc-tls"
    }

    rule {
      host = "tempo-grpc.${var.monitoring_domain}"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "monitoring-tempo-distributor"
              port {
                number = 4317
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    helm_release.tempo,
    module.cert_manager
  ]
}
