terraform {
  required_version = ">= 1.0"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
  }
}

resource "helm_release" "cert_manager" {
  count = var.install_cert_manager ? 1 : 0

  name             = var.release_name
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  namespace        = var.namespace
  create_namespace = true
  version          = var.cert_manager_version

  set {
    name  = "installCRDs"
    value = "true"
  }

  wait    = true
  timeout = 600
}

# Issuer for Let's Encrypt
resource "kubernetes_manifest" "letsencrypt_issuer" {
  count = var.install_cert_manager ? 1 : 0

  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = var.cert_issuer_kind
    metadata = merge(
      {
        name = var.cert_issuer_name
      },
      # Only add namespace if Kind is Issuer. 
      # If issuer_namespace is set, use it. Otherwise fallback to var.namespace.
      var.cert_issuer_kind == "Issuer" ? {
        namespace = coalesce(var.issuer_namespace, var.namespace)
      } : {}
    )
    spec = {
      acme = {
        server = var.issuer_server
        email  = var.letsencrypt_email
        privateKeySecretRef = {
          name = "${var.cert_issuer_name}-key"
        }
        solvers = [
          {
            http01 = {
              ingress = {
                class = var.ingress_class_name
              }
            }
          }
        ]
      }
    }
  }

  depends_on = [helm_release.cert_manager]
}
