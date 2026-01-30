variable "cloud_provider" {
  description = "Cloud provider (gke, eks, aks, or generic)"
  type        = string
  default     = "gke"
  validation {
    condition     = contains(["gke", "eks", "aks", "generic"], var.cloud_provider)
    error_message = "Cloud provider must be one of: gke, eks, aks, generic."
  }
}

variable "project_id" {
  description = "GCP Project ID (required for GKE)"
  type        = string
  default     = ""
}

variable "region" {
  description = "GCP Region"
  type        = string
  default     = "us-central1"
}

variable "aws_region" {
  description = "AWS Region (for EKS)"
  type        = string
  default     = "us-east-1"
}

variable "gke_endpoint" {
  description = "GKE Cluster Endpoint"
  type        = string
  default     = ""
}

variable "gke_ca_certificate" {
  description = "GKE Cluster CA Certificate"
  type        = string
  default     = ""
}

variable "install_cert_manager" {
  description = "Whether to install cert-manager"
  type        = bool
  default     = false
}

variable "create_issuer" {
  description = "Whether to create the cert issuer (set to false if creating it separately to avoid circular dependencies)"
  type        = bool
  default     = true
}

variable "release_name" {
  description = "Helm release name"
  type        = string
  default     = "cert-manager"
}

variable "cert_manager_version" {
  description = "Version of cert-manager chart"
  type        = string
  default     = "v1.19.2"
}

variable "namespace" {
  description = "Namespace to install cert-manager into"
  type        = string
  default     = "cert-manager"
}



variable "letsencrypt_email" {
  description = "Email address for Let's Encrypt certificate notifications"
  type        = string
}

variable "cert_issuer_name" {
  description = "Name of the ClusterIssuer or Issuer to create"
  type        = string
  default     = "letsencrypt-prod"
}

variable "cert_issuer_kind" {
  description = "Kind of Issuer to create (ClusterIssuer or Issuer)"
  type        = string
  default     = "ClusterIssuer"
  validation {
    condition     = contains(["ClusterIssuer", "Issuer"], var.cert_issuer_kind)
    error_message = "The cert_issuer_kind must be either 'ClusterIssuer' or 'Issuer'."
  }
}

variable "issuer_namespace" {
  description = "Namespace for the Issuer (required if cert_issuer_kind is Issuer). Defaults to the installation namespace if not provided."
  type        = string
  default     = ""
}

variable "issuer_server" {
  description = "ACME server URL"
  type        = string
  default     = "https://acme-v02.api.letsencrypt.org/directory"
}

variable "ingress_class_name" {
  description = "Ingress class to solve challenges"
  type        = string
  default     = "nginx"
}
