# =============================================================================
# LOCAL VALUES AND COMPUTED VARIABLES
# Computed values derived from input variables for consistent use across resources
# =============================================================================

locals {
  # =============================================================================
  # SERVICE FQDNS (Fully Qualified Domain Names)
  # =============================================================================

  # ArgoCD Server service endpoints
  argocd_server_fqdn = "${var.argocd_server_service_name}.${var.hub_namespace}.svc.cluster.local"
  argocd_server_dns = join(",", [
    "localhost",
    "${var.argocd_server_service_name}.${var.hub_namespace}.svc.cluster.local",
    "${var.argocd_server_service_name}.${var.hub_namespace}.svc"
  ])

  # Principal service endpoints
  principal_fqdn = "${var.principal_service_name}.${var.hub_namespace}.svc.cluster.local"
  principal_dns = join(",", [
    "localhost",
    "${var.principal_service_name}.${var.hub_namespace}.svc.cluster.local",
    "${var.principal_service_name}.${var.hub_namespace}.svc"
  ])

  # Resource proxy service endpoints
  resource_proxy_fqdn   = "${var.resource_proxy_service_name}.${var.hub_namespace}.svc.cluster.local"
  resource_proxy_server = "${local.resource_proxy_fqdn}:${var.resource_proxy_port}"
  resource_proxy_dns = join(",", [
    "localhost",
    local.resource_proxy_fqdn
  ])

  # =============================================================================
  # AGENT MANAGEMENT
  # =============================================================================

  # List of all agent names from clusters map
  all_agent_names = keys(var.clusters)

  # Comma-separated string of agent names
  all_agent_names_str = join(",", local.all_agent_names)

  # =============================================================================
  # COMMON LABELS AND ANNOTATIONS
  # =============================================================================

  # Common labels for all resources
  common_labels = {
    "app.kubernetes.io/managed-by" = "terraform"
    "app.kubernetes.io/part-of"    = "argocd-agent"
  }

  # Hub-specific labels
  hub_labels = merge(local.common_labels, {
    "argocd-agent/component" = "hub"
  })

  # Spoke-specific labels
  spoke_labels = merge(local.common_labels, {
    "argocd-agent/component" = "spoke"
  })

  # =============================================================================
  # TIMEOUT VALUES
  # =============================================================================

  # Standardized timeout values for scripts
  kubectl_timeout_seconds          = tonumber(regex("^([0-9]+)", var.kubectl_timeout)[0])
  namespace_delete_timeout_seconds = tonumber(regex("^([0-9]+)", var.namespace_delete_timeout)[0])

  # =============================================================================
  # ARGOCD INSTALLATION URLS
  # =============================================================================

  # ArgoCD base installation manifest URL
  # NOTE: v0.5.3 is the default tested version and maps to 'stable' branch
  # Other versions use the specific version tag for reproducibility
  argocd_base_install_url = "https://raw.githubusercontent.com/argoproj/argo-cd/${var.argocd_version == "v0.5.3" ? "stable" : var.argocd_version}/manifests/install.yaml"

  # ArgoCD Agent installation URLs (kustomize)
  agent_principal_install_url     = "https://github.com/argoproj-labs/argocd-agent/install/kubernetes/principal?ref=${var.argocd_version}"
  agent_spoke_managed_install_url = "https://github.com/argoproj-labs/argocd-agent/install/kubernetes/argo-cd/agent-managed?ref=${var.argocd_version}"
  agent_client_install_url        = "https://github.com/argoproj-labs/argocd-agent/install/kubernetes/agent?ref=${var.argocd_version}"
}
