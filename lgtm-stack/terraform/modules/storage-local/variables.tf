variable "storage_names" {
  description = "List of storage volume names"
  type        = list(string)
  default     = ["loki-chunks", "loki-ruler", "mimir-blocks", "mimir-ruler", "tempo-traces"]
}

variable "storage_sizes" {
  description = "Storage size for each volume"
  type        = map(string)
  default = {
    loki-chunks  = "100Gi"
    loki-ruler   = "10Gi"
    mimir-blocks = "100Gi"
    mimir-ruler  = "10Gi"
    tempo-traces = "50Gi"
  }
}

variable "storage_class" {
  description = "Kubernetes storage class"
  type        = string
  default     = "standard"
}

variable "host_path_base" {
  description = "Base path for hostPath volumes"
  type        = string
  default     = "/mnt/lgtm-data"
}

variable "k8s_namespace" {
  description = "Kubernetes namespace"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}
