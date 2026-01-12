output "ingress_class_name" {
  description = "The Ingress Class Name"
  value       = var.ingress_class_name
}

output "load_balancer_ip" {
  description = "The Load Balancer IP (if available, this is output from the Helm release attribute)"
  value       = "" # Helm release resource outputs are often just metadata, getting IP usually requires a datasource look up. For now leaving placeholder or just the class name.
}
