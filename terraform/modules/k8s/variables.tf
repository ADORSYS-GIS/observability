variable "project_id" {
  type        = string
  description = "The ID of the project where this GKE will be created"
}

variable "region" {
  type        = string
  description = "The region where to deploy resources"
}

variable "name" {
  type        = string
  description = "Deployment name"
}

variable "network_name" {
  type = string
}

variable "sub_network_name" {
  type = string
}

variable "ip_range_pod" {
  type = string
}

variable "ip_range_services" {
  type = string
}
