output "deployed_agents" {
  description = "Deployed spoke agent names"
  value       = keys(var.clusters)
}

output "spoke_namespace" {
  description = "Namespace used on spoke clusters"
  value       = var.spoke_namespace
}
