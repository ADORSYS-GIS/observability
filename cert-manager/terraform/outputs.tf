output "namespace" {
  description = "Namespace where cert-manager was installed"
  value       = var.namespace
}

output "issuer_name" {
  description = "Name of the created Issuer"
  value       = var.install_cert_manager ? var.cert_issuer_name : ""
}

output "issuer_id" {
  description = "ID of the created Issuer resource (for dependency management)"
  value       = var.install_cert_manager && var.create_issuer ? null_resource.letsencrypt_issuer[0].id : ""
}
