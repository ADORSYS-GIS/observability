variable "root_domain_name" {
  description = "Zone domain, must end with a period."
  type        = string
}

variable "project_id" {
  type        = string
  description = "Google Project ID"
}

variable "network_self_link" {
  type        = string
  description = "Network self link"
}

variable "name" {
  type        = string
  description = "Deployment name"
}

variable "labels" {
  description = "Map of labels for project"
  type        = map(string)
  default     = {}
}

variable "records" {
  description = "Map of records for dns"
  type = map(object({
    type    = string
    ttl     = number
    records = list(string)
  }))
  default = {}
}
