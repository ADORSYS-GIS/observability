# =============================================================================
# HUB CLUSTER MODULE OUTPUTS
# =============================================================================

output "argocd_url" {
  description = "ArgoCD UI URL"
  value       = var.ui_expose_method == "ingress" ? "https://${var.argocd_host}" : try("https://${data.external.hub_principal_address.result.address}", "Pending LoadBalancer IP")
}

output "principal_address" {
  description = "Principal service external address"
  value       = try(data.external.hub_principal_address.result.address, "Pending")
}

output "principal_port" {
  description = "Principal service external port"
  value       = try(data.external.hub_principal_address.result.port, "443")
}

output "hub_namespace" {
  description = "Hub cluster namespace"
  value       = var.hub_namespace
}

output "keycloak_client_id" {
  description = "Keycloak OIDC client ID"
  value       = var.enable_keycloak ? var.keycloak_client_id : null
}

output "keycloak_config" {
  description = "Keycloak OIDC configuration details"
  value = var.enable_keycloak ? {
    realm       = var.keycloak_realm
    url         = "${var.keycloak_url}/realms/${var.keycloak_realm}"
    client_id   = var.keycloak_client_id
    auth_method = var.keycloak_enable_pkce ? "PKCE" : "Client Auth"
    groups      = "ArgoCDAdmins (admin), ArgoCDDevelopers (edit), ArgoCDViewers (readonly)"
  } : null
}

output "appproject_config" {
  description = "AppProject configuration for managed mode"
  value = var.enable_appproject_sync ? {
    source_namespaces = var.appproject_default_source_namespaces
    dest_server       = var.appproject_default_dest_server
    dest_namespaces   = var.appproject_default_dest_namespaces
  } : null
}

output "management_commands" {
  description = "Commands for infrastructure management"
  value = {
    hub_pods       = "kubectl get pods -n ${var.hub_namespace} --context ${var.hub_cluster_context}"
    principal_logs = "kubectl logs -n ${var.hub_namespace} deployment/${var.principal_service_name} --context ${var.hub_cluster_context}"
    list_agents    = "${var.argocd_agentctl_path} agent list --principal-context ${var.hub_cluster_context} --principal-namespace ${var.hub_namespace}"
    backup_pki     = "kubectl get secret argocd-agent-pki-ca -n ${var.hub_namespace} --context ${var.hub_cluster_context} -o yaml > pki-ca-backup-$(date +%%Y%%m%%d).yaml"
  }
}

output "pki_backup_warning" {
  description = "CRITICAL: Backup PKI CA immediately after deployment"
  value       = "⚠️  CRITICAL: Backup PKI CA with: kubectl get secret argocd-agent-pki-ca -n ${var.hub_namespace} --context ${var.hub_cluster_context} -o yaml > pki-ca-backup.yaml"
}
