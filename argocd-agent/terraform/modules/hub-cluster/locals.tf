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

  # List of all agent names from workload_clusters map
  all_agent_names = keys(var.workload_clusters)

  # Comma-separated string of agent names (for Principal allowed-namespaces)
  allowed_namespaces = length(local.all_agent_names) > 0 ? join(",", local.all_agent_names) : "default"

  # String representation for templates
  all_agent_names_str = join(",", local.all_agent_names)

  # =============================================================================
  # CONDITIONAL DEPLOYMENT FLAGS
  # =============================================================================

  # Determine if infrastructure modules should be installed
  install_cert_manager_module  = var.deploy_hub && var.install_cert_manager
  install_nginx_ingress_module = var.deploy_hub && var.install_nginx_ingress

  # Determine if Keycloak integration is active
  keycloak_enabled = var.deploy_hub && var.enable_keycloak

  # =============================================================================
  # CONDITIONAL FEATURES (Module-level)
  # =============================================================================

  # Note: Infrastructure modules (cert-manager, ingress-nginx) are managed
  # at the orchestration layer, not within this module

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

  # ArgoCD base installation manifest URL for HUB (Principal)
  # IMPORTANT: Use ArgoCD Agent's principal-specific installation
  # This excludes application-controller which must ONLY run on spoke clusters
  # Reference: https://argocd-agent.readthedocs.io/latest/getting-started/kubernetes/
  argocd_base_install_url = "https://github.com/argoproj-labs/argocd-agent/install/kubernetes/argo-cd/principal?ref=${var.argocd_version}"

  # ArgoCD Agent installation URLs (kustomize)
  agent_principal_install_url     = "https://github.com/argoproj-labs/argocd-agent/install/kubernetes/principal?ref=${var.argocd_version}"
  agent_spoke_managed_install_url = "https://github.com/argoproj-labs/argocd-agent/install/kubernetes/argo-cd/agent-managed?ref=${var.argocd_version}"
  agent_client_install_url        = "https://github.com/argoproj-labs/argocd-agent/install/kubernetes/agent?ref=${var.argocd_version}"

  # =============================================================================
  # KEYCLOAK ADMIN USER
  # =============================================================================

  # Admin password - use provided password or random password if not set
  admin_password = var.default_admin_password != "" ? var.default_admin_password : (
    var.create_default_admin_user ? random_password.keycloak_admin_password[0].result : ""
  )
}
