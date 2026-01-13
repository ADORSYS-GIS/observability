variable "argocd_namespace" {
  description = "Kubernetes namespace for Argo CD"
  type        = string
  default     = "argocd"
}

variable "argocd_version" {
  description = "Argo CD Helm chart version"
  type        = string
  default     = "7.0.0"
}

variable "argocd_image_version" {
  description = "Argo CD container image version"
  type        = string
  default     = "v2.11.2"
}

variable "argocd_agent_version" {
  description = "Argo CD Agent image version"
  type        = string
  default     = "v0.5.3"
}

variable "control_plane_cluster" {
  description = "Control plane cluster configuration"
  type = object({
    name              = string
    context_name      = string
    kubeconfig_path   = string
    server_address    = string
    server_port       = number
    tls_enabled       = bool
  })
  default = {
    name            = "control-plane"
    context_name    = "context-2"
    kubeconfig_path = "/home/ubuntu/.kube/merged-config"
    server_address  = "argocd-cp.local"
    server_port     = 443
    tls_enabled     = true
  }
}

variable "workload_clusters" {
  description = "Workload clusters configuration (agents)"
  type = list(object({
    name              = string
    context_name      = string
    kubeconfig_path   = string
    principal_address = string
    principal_port    = number
    agent_name        = string
    tls_enabled       = bool
  }))
  default = [{
    name              = "workload-1"
    context_name      = "context_1"
    kubeconfig_path   = "/home/ubuntu/.kube/merged-config"
    principal_address = "argocd-cp.local"
    principal_port    = 443
    agent_name        = "agent-1"
    tls_enabled       = true
  }]
}

variable "tls_config" {
  description = "TLS configuration for mTLS"
  type = object({
    generate_certs     = bool
    cert_validity_days = number
    tls_algorithm      = string
  })
  default = {
    generate_certs     = true
    cert_validity_days = 365
    tls_algorithm      = "RSA"
  }
}

variable "helm_repository_url" {
  description = "Argo Helm repository URL"
  type        = string
  default     = "https://argoproj.github.io/argo-helm"
}

variable "enable_server_ui" {
  description = "Enable Argo CD server UI"
  type        = bool
  default     = true
}

variable "server_service_type" {
  description = "Argo CD server service type"
  type        = string
  default     = "LoadBalancer"
  validation {
    condition     = contains(["LoadBalancer", "ClusterIP", "NodePort"], var.server_service_type)
    error_message = "Service type must be LoadBalancer, ClusterIP, or NodePort."
  }
}

variable "controller_replicas" {
  description = "Number of Argo CD application controller replicas"
  type        = number
  default     = 1
  validation {
    condition     = var.controller_replicas > 0
    error_message = "Controller replicas must be greater than 0."
  }
}

variable "repo_server_replicas" {
  description = "Number of Argo CD repo server replicas"
  type        = number
  default     = 1
  validation {
    condition     = var.repo_server_replicas > 0
    error_message = "Repo server replicas must be greater than 0."
  }
}

variable "agent_mode" {
  description = "Argo CD Agent mode (autonomous or managed)"
  type        = string
  default     = "autonomous"
  validation {
    condition     = contains(["autonomous", "managed"], var.agent_mode)
    error_message = "Agent mode must be 'autonomous' or 'managed'."
  }
}

variable "create_certificate_authority" {
  description = "Create a CA certificate for signing agent certificates"
  type        = bool
  default     = true
}

variable "labels_common" {
  description = "Common labels for all resources"
  type        = map(string)
  default = {
    managed_by = "terraform"
    application = "argocd"
  }
}

variable "annotations_common" {
  description = "Common annotations for all resources"
  type        = map(string)
  default = {
    "terraform.io/managed" = "true"
  }
}

variable "domain_name" {
  description = "Domain name for Argo CD server (e.g., argocd.example.com)"
  type        = string
  default     = "net.tail3365c9.ts.net"
}

variable "acme_email" {
  description = "Email address for Let's Encrypt notifications"
  type        = string
  default     = "emmanuelodon943@gmail.com"
}
