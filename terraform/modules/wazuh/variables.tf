variable "helm_chart_user" {
  sensitive = true
  type      = string
}

variable "helm_chart_pass" {
  sensitive = true
  type      = string
}

variable "helm_chart_version" {
  sensitive = true
  type      = string
}

variable "subject" {
  type = object({
    country      = string
    locality     = string
    organization = string
    common_name  = string
  })
}

variable "ip_addresses" {
  type = object({
    dashboard = object({
      domain  = string
      ip_name = string
      ip      = string
    })
    manager = object({
      domain  = string
      ip_name = string
      ip      = string
    })
  })
}
