variable "helm_chart_version" {
  type      = string
}

variable "openid_connect_url" {
  type = string
  default = "https://login.dev.wazuh.adorsys.team/realms/test-adorsys"
}

variable "openid_client_id" {
  sensitive = true
  type = string
}

variable "openid_client_secret" {
  sensitive = true
  type = string
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
    cert = object({
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
