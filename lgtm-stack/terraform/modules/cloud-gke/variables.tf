variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP Region for resources"
  type        = string
  default     = "us-central1"
}

variable "bucket_names" {
  description = "List of bucket names to create"
  type        = list(string)
  default     = ["loki-chunks", "loki-ruler", "mimir-blocks", "mimir-ruler", "tempo-traces"]
}

variable "service_account_name" {
  description = "GCP Service Account name"
  type        = string
}

variable "k8s_namespace" {
  description = "Kubernetes namespace for Workload Identity binding"
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
  description = "Component name for labeling"
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
