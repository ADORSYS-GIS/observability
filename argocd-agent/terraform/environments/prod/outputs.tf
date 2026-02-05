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
  value = var.deploy_hub && local.deploy_spokes_conditional ? format(
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

# =============================================================================
# DEPLOYMENT STATUS (Two-Stage Deployment Support)
# =============================================================================

output "deployment_status" {
  description = "Overall deployment status and next steps"
  value = !local.principal_ready && var.deploy_spokes ? <<-EOT

    ⚠️  NOTICE: Spoke clusters were SKIPPED because Principal LoadBalancer IP is not ready yet.

    This is normal for fresh deployments. The LoadBalancer is still provisioning.

    Next Steps:
    1. Wait 5-10 minutes for GKE to assign the LoadBalancer IP
    2. Check status: kubectl get svc argocd-agent-principal -n ${var.hub_namespace} --context ${var.hub_cluster_context}
    3. Once EXTERNAL-IP shows (not <pending>), re-run this workflow
    4. The second run will deploy the spoke clusters automatically
  EOT
  : "✅ Deployment complete! All components deployed successfully."
}

output "hub_deployed" {
  description = "Whether hub cluster was deployed"
  value       = var.deploy_hub
}

output "spokes_deployed" {
  description = "Whether spoke clusters were deployed"
  value       = local.deploy_spokes_conditional
}

output "spokes_requested" {
  description = "Whether spoke deployment was requested"
  value       = var.deploy_spokes
}

output "spokes_skipped_reason" {
  description = "Reason spokes were skipped (if applicable)"
  value       = var.deploy_spokes && !local.deploy_spokes_conditional ? "Principal LoadBalancer IP not ready (still provisioning)" : null
}
