# =============================================================================
# PRODUCTION ENVIRONMENT OUTPUTS
# =============================================================================
# Aggregates outputs from hub-cluster and spoke-cluster modules
# =============================================================================

# =============================================================================
# HUB CLUSTER OUTPUTS
# =============================================================================

output "argocd_url" {
  description = "ArgoCD UI URL"
  value       = var.deploy_hub ? module.hub_cluster[0].argocd_url : null
}

output "principal_address" {
  description = "Principal service external address"
  value       = var.deploy_hub ? module.hub_cluster[0].principal_address : var.principal_address
}

output "principal_port" {
  description = "Principal service external port"
  value       = var.deploy_hub ? module.hub_cluster[0].principal_port : var.principal_port
}

output "keycloak_client_id" {
  description = "Keycloak OIDC client ID"
  value       = var.deploy_hub ? module.hub_cluster[0].keycloak_client_id : null
}

output "keycloak_config" {
  description = "Keycloak OIDC configuration details"
  value       = var.deploy_hub ? module.hub_cluster[0].keycloak_config : null
}

output "appproject_config" {
  description = "AppProject configuration for managed mode"
  value       = var.deploy_hub ? module.hub_cluster[0].appproject_config : null
}

output "management_commands" {
  description = "Commands for infrastructure management"
  value       = var.deploy_hub ? module.hub_cluster[0].management_commands : null
}

output "pki_backup_warning" {
  description = "CRITICAL: Backup PKI CA immediately after deployment"
  value       = var.deploy_hub ? module.hub_cluster[0].pki_backup_warning : null
}

# =============================================================================
# SPOKE CLUSTER OUTPUTS
# =============================================================================

output "deployed_agents" {
  description = "List of connected spoke agents"
  value       = var.deploy_spokes ? module.spoke_cluster[0].deployed_agents : []
}

# =============================================================================
# DEPLOYMENT SUMMARY
# =============================================================================

output "deployment_summary" {
  description = "Deployment summary"
  value = var.deploy_hub && var.deploy_spokes ? format(
    "✓ Hub cluster: %s | Principal: %s:%s | Agents: %s",
    var.hub_cluster_context,
    module.hub_cluster[0].principal_address,
    module.hub_cluster[0].principal_port,
    join(", ", module.spoke_cluster[0].deployed_agents)
    ) : var.deploy_hub ? format(
    "✓ Hub-only: %s | Principal: %s:%s | Run with deploy_spokes=true to add agents",
    var.hub_cluster_context,
    module.hub_cluster[0].principal_address,
    module.hub_cluster[0].principal_port
    ) : format(
    "✓ Spoke-only: %s agents connected to %s:%s",
    length(var.workload_clusters),
    var.principal_address,
    var.principal_port
  )
}
