output "namespace" {
  description = "Namespace where cert-manager was installed"
  value       = var.namespace
}

output "issuer_name" {
  description = "Name of the created Issuer"
  value       = var.install_cert_manager ? var.cert_issuer_name : ""
}
