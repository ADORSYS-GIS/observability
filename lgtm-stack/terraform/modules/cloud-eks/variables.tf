variable "bucket_prefix" {
  description = "Prefix for S3 bucket names"
  type        = string
}

variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "eks_oidc_provider_arn" {
  description = "ARN of the EKS OIDC provider"
  type        = string
}

variable "bucket_names" {
  description = "List of bucket names to create"
  type        = list(string)
  default     = ["loki-chunks", "loki-ruler", "mimir-blocks", "mimir-ruler", "tempo-traces"]
}

variable "k8s_namespace" {
  description = "Kubernetes namespace"
  type        = string
}

variable "k8s_service_account_name" {
  description = "Kubernetes Service Account name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "component_name" {
  description = "Component name for tagging"
  type        = string
  default     = "lgtm-observability"
}

variable "retention_days" {
  description = "Data retention in days"
  type        = number
  default     = 90
}

variable "force_destroy_buckets" {
  description = "Allow destroying buckets with data"
  type        = bool
  default     = false
}
