variable "name" {
  type        = string
  description = "Deployment name"
}

variable "region" {
  type        = string
  description = "The region where to deploy resources"
}

variable "regional" {
  type = bool
}

variable "project_id" {
  type        = string
  description = "Google Project ID"
}
