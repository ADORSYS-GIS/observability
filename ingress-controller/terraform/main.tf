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
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "google" {
  project = var.cloud_provider == "gke" && var.project_id != "" ? var.project_id : null
  region  = var.region
}

# AWS provider - required by EKS module even when not used (count=0)
provider "aws" {
  region                      = var.aws_region
  skip_credentials_validation = var.cloud_provider != "eks"
  skip_requesting_account_id  = var.cloud_provider != "eks"
  skip_metadata_api_check     = var.cloud_provider != "eks"
  access_key                  = var.cloud_provider != "eks" ? "mock_access_key" : null
  secret_key                  = var.cloud_provider != "eks" ? "mock_secret_key" : null
}

# The kubernetes and helm providers will use the configuration established
# by gcloud/kubectl/az in the workflow (via ~/.kube/config), but for GKE
# we explicitly configure them using values passed from the workflow
# to ensure zero-config connectivity in CI.
provider "kubernetes" {
  host                   = var.cloud_provider == "gke" && var.gke_endpoint != "" ? "https://${var.gke_endpoint}" : null
  token                  = var.cloud_provider == "gke" && var.gke_endpoint != "" ? data.google_client_config.default[0].access_token : null
  cluster_ca_certificate = var.cloud_provider == "gke" && var.gke_ca_certificate != "" ? base64decode(var.gke_ca_certificate) : null
}

provider "helm" {
  kubernetes {
    host                   = var.cloud_provider == "gke" && var.gke_endpoint != "" ? "https://${var.gke_endpoint}" : null
    token                  = var.cloud_provider == "gke" && var.gke_endpoint != "" ? data.google_client_config.default[0].access_token : null
    cluster_ca_certificate = var.cloud_provider == "gke" && var.gke_ca_certificate != "" ? base64decode(var.gke_ca_certificate) : null
  }
}

data "google_client_config" "default" {
  count = var.cloud_provider == "gke" ? 1 : 0
}

resource "helm_release" "nginx_ingress" {
  count = var.install_nginx_ingress ? 1 : 0

  name             = var.release_name
  repository       = "https://helm.nginx.com/stable"
  chart            = "nginx-ingress"
  namespace        = var.namespace
  create_namespace = true
  version          = var.nginx_ingress_version

  set {
    name  = "controller.replicaCount"
    value = var.replica_count
  }

  set {
    name  = "controller.ingressClass.name"
    value = var.ingress_class_name
  }

  set {
    name  = "controller.ingressClass.create"
    value = "false" # We create it explicitly below for better control
  }

  set {
    name  = "controller.ingressClass.setAsDefaultIngress"
    value = "false"
  }

  # Enable RBAC (should be enabled by default but explicit is better)
  set {
    name  = "rbac.create"
    value = "true"
  }

  # ServiceAccount configuration
  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "${var.release_name}-nginx-ingress"
  }

  # Wait for the LoadBalancer to be ready
  wait    = true
  timeout = 600
}

# Explicitly create IngressClass resource for better control and shareability
# This ensures the IngressClass is properly managed and can be used by other resources
resource "kubernetes_manifest" "ingress_class" {
  count = var.install_nginx_ingress ? 1 : 0

  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "IngressClass"
    metadata = {
      name = var.ingress_class_name
      labels = {
        "app.kubernetes.io/name"       = "nginx-ingress"
        "app.kubernetes.io/instance"   = var.release_name
        "app.kubernetes.io/component"  = "controller"
        "app.kubernetes.io/managed-by" = "terraform"
      }
      annotations = {
        "ingressclass.kubernetes.io/is-default-class" = "false"
      }
    }
    spec = {
      controller = "nginx.org/ingress-controller"
    }
  }

  depends_on = [helm_release.nginx_ingress]
}

# Explicit cleanup on destroy - removes IngressClass first, then namespace
resource "null_resource" "namespace_cleanup" {
  count = var.install_nginx_ingress ? 1 : 0

  triggers = {
    namespace     = var.namespace
    ingress_class = var.ingress_class_name
  }

  provisioner "local-exec" {
    when       = destroy
    command    = <<-EOT
      # Delete IngressClass first
      kubectl delete ingressclass ${self.triggers.ingress_class} --ignore-not-found=true --timeout=30s || true
      # Then delete namespace
      kubectl delete namespace ${self.triggers.namespace} --ignore-not-found=true --timeout=60s || true
    EOT
    on_failure = continue
  }

  depends_on = [
    helm_release.nginx_ingress,
    kubernetes_manifest.ingress_class
  ]
}
