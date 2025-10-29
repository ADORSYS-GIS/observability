locals {
  name                       = "wazuh"
  root_secret_name           = "${local.name}-root-secret"
  dashboard_certificate_name = replace(var.ip_addresses.dashboard.domain, "/[.]/", "-")
  manager_certificate_name   = replace(var.ip_addresses.manager.domain, "/[.]/", "-")
}
