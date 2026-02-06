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

# Providers are configured in the root module and passed to this module
# This allows the module to work with count, for_each, and depends_on

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
    value = "true"
  }

  set {
    name  = "controller.ingressClass.setAsDefaultIngress"
    value = "false"
  }

  # Wait for the LoadBalancer to be ready
  wait    = true
  timeout = 600
}

# Explicit namespace cleanup on destroy
resource "null_resource" "namespace_cleanup" {
  count = var.install_nginx_ingress ? 1 : 0

  triggers = {
    namespace = var.namespace
  }

  provisioner "local-exec" {
    when       = destroy
    command    = "kubectl delete namespace ${self.triggers.namespace} --ignore-not-found=true --timeout=60s || true"
    on_failure = continue
  }

  depends_on = [helm_release.nginx_ingress]
}

# =============================================================================
# RBAC FIX FOR NGINX INC CONTROLLER
# =============================================================================
# The NGINX Inc Helm chart doesn't create sufficient RBAC permissions by default
# This is a known limitation compared to the Community NGINX chart
# Without these permissions, the controller cannot list/watch Kubernetes ingresses
# and will fail with: "cannot list resource 'ingresses' in API group 'networking.k8s.io'"
#
# Official NGINX Inc docs confirm this is required for proper operation:
# https://docs.nginx.com/nginx-ingress-controller/installation/installation-with-helm/
# =============================================================================

resource "kubernetes_cluster_role_v1" "nginx_ingress_rbac" {
  count = var.install_nginx_ingress ? 1 : 0

  metadata {
    name = "nginx-ingress"
  }

  # Discovery API - Required for service discovery
  rule {
    api_groups = ["discovery.k8s.io"]
    resources  = ["endpointslices"]
    verbs      = ["get", "list", "watch"]
  }

  # Core resources - Services, endpoints, pods, secrets, configmaps
  rule {
    api_groups = [""]
    resources  = ["services", "endpoints", "pods", "secrets", "configmaps"]
    verbs      = ["get", "list", "watch"]
  }

  # Events - For logging and debugging
  rule {
    api_groups = [""]
    resources  = ["events"]
    verbs      = ["create", "patch", "list"]
  }

  # CRITICAL: Ingress resources - This is what was missing!
  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["ingresses", "ingressclasses"]
    verbs      = ["get", "list", "watch"]
  }

  # Ingress status updates - So controller can update LoadBalancer IPs
  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["ingresses/status"]
    verbs      = ["update"]
  }

  # NGINX Inc specific CRDs (if using VirtualServer, etc.)
  rule {
    api_groups = ["k8s.nginx.org"]
    resources  = ["virtualservers", "virtualserverroutes", "transportservers", "policies", "globalconfigurations"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["k8s.nginx.org"]
    resources  = ["virtualservers/status", "virtualserverroutes/status", "transportservers/status", "policies/status"]
    verbs      = ["update"]
  }

  depends_on = [helm_release.nginx_ingress]
}

resource "kubernetes_cluster_role_binding_v1" "nginx_ingress_rbac" {
  count = var.install_nginx_ingress ? 1 : 0

  metadata {
    name = "nginx-ingress"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.nginx_ingress_rbac[0].metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = "nginx-monitoring-nginx-ingress" # This is created by the Helm chart
    namespace = var.namespace
  }

  depends_on = [helm_release.nginx_ingress]
}
