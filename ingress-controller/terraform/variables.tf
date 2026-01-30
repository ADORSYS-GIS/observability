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

variable "install_nginx_ingress" {
  description = "Whether to install NGINX Ingress Controller"
  type        = bool
  default     = false
}

variable "nginx_ingress_version" {
  description = "Version of nginx-ingress chart (NGINX Inc. official from helm.nginx.com/stable)"
  type        = string
  default     = "2.4.2"
}

variable "release_name" {
  description = "Helm release name"
  type        = string
  default     = "nginx-monitoring"
}

variable "ingress_class_name" {
  description = "Ingress Class Name"
  type        = string
  default     = "nginx"
}

variable "namespace" {
  description = "Namespace to install ingress-nginx into"
  type        = string
  default     = "ingress-nginx"
}


variable "replica_count" {
  description = "Number of replicas for the controller"
  type        = number
  default     = 1
}
