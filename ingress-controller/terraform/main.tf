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
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

resource "helm_release" "nginx_ingress" {
  count = var.install_nginx_ingress ? 1 : 0

  name             = var.release_name
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = var.namespace
  create_namespace = true
  version          = var.nginx_ingress_version

  set {
    name  = "controller.replicaCount"
    value = var.replica_count
  }

  set {
    name  = "controller.ingressClassResource.name"
    value = var.ingress_class_name
  }

  set {
    name  = "controller.ingressClass"
    value = var.ingress_class_name
  }

  set {
    name  = "controller.ingressClassResource.controllerValue"
    value = "k8s.io/${var.ingress_class_name}"
  }
  set {
    name  = "controller.ingressClassResource.enabled"
    value = "true"
  }

  set {
    name  = "controller.ingressClassByName"
    value = "true"
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
