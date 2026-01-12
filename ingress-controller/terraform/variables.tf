variable "install_nginx_ingress" {
  description = "Whether to install NGINX Ingress Controller"
  type        = bool
  default     = false
}

variable "nginx_ingress_version" {
  description = "Version of ingress-nginx chart"
  type        = string
  default     = "4.10.1"
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
