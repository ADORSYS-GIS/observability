# =============================================================================
# PRODUCTION ENVIRONMENT - ARGOCD AGENT HUB-AND-SPOKE ARCHITECTURE
# =============================================================================
# This is the main orchestration layer that calls the hub-cluster and
# spoke-cluster modules based on deployment flags.
#
# Architecture:
# - Hub Cluster: ArgoCD control plane + Agent Principal + PKI
# - Spoke Clusters: ArgoCD agents running in managed mode
#
# Deployment Modes:
# 1. Hub + Spokes (default): deploy_hub=true, deploy_spokes=true
# 2. Hub only: deploy_hub=true, deploy_spokes=false
# 3. Spokes only: deploy_hub=false, deploy_spokes=true (requires external principal)
# =============================================================================

terraform {
  required_version = ">= 1.0"
}

# =============================================================================
# INFRASTRUCTURE MODULES (Cert-Manager, Ingress)
# =============================================================================

module "cert_manager" {
  count  = var.deploy_hub && var.install_cert_manager ? 1 : 0
  source = "../../../../cert-manager/terraform"

  providers = {
    kubernetes = kubernetes.hub
    helm       = helm.hub
  }

  install_cert_manager = true
  create_issuer        = false
  cert_manager_version = var.cert_manager_version
  release_name         = var.cert_manager_release_name
  namespace            = var.cert_manager_namespace
  letsencrypt_email    = var.letsencrypt_email
  cert_issuer_name     = var.cert_issuer_name
  cert_issuer_kind     = var.cert_issuer_kind
  issuer_namespace     = var.hub_namespace
  ingress_class_name   = var.ingress_class_name
}

module "ingress_nginx" {
  count  = var.deploy_hub && var.install_nginx_ingress ? 1 : 0
  source = "../../../../ingress-controller/terraform"

  providers = {
    kubernetes = kubernetes.hub
    helm       = helm.hub
  }

  install_nginx_ingress = true
  nginx_ingress_version = var.nginx_ingress_version
  release_name          = var.nginx_ingress_release_name
  namespace             = var.nginx_ingress_namespace
  ingress_class_name    = var.ingress_class_name
}

# =============================================================================
# HUB CLUSTER MODULE
# =============================================================================

module "hub_cluster" {
  count  = var.deploy_hub ? 1 : 0
  source = "../../modules/hub-cluster"

  providers = {
    kubernetes = kubernetes.hub
    helm       = helm.hub
    keycloak   = keycloak
  }

  # Pass through all variables
  hub_cluster_context                      = var.hub_cluster_context
  hub_namespace                            = var.hub_namespace
  argocd_version                           = var.argocd_version
  argocd_agentctl_path                     = var.argocd_agentctl_path
  workload_clusters                        = var.workload_clusters
  ui_expose_method                         = var.ui_expose_method
  principal_expose_method                  = var.principal_expose_method
  argocd_host                              = var.argocd_host
  enable_keycloak                          = var.enable_keycloak
  enable_appproject_sync                   = var.enable_appproject_sync
  enable_resource_proxy_credentials_secret = var.enable_resource_proxy_credentials_secret
  enable_principal_ingress                 = var.enable_principal_ingress
  kubectl_timeout                          = var.kubectl_timeout
  namespace_delete_timeout                 = var.namespace_delete_timeout
  argocd_install_retry_attempts            = var.argocd_install_retry_attempts
  argocd_install_retry_delay               = var.argocd_install_retry_delay
  principal_loadbalancer_wait_timeout      = var.principal_loadbalancer_wait_timeout
  argocd_server_service_name               = var.argocd_server_service_name
  principal_service_name                   = var.principal_service_name
  resource_proxy_service_name              = var.resource_proxy_service_name
  resource_proxy_port                      = var.resource_proxy_port
  ingress_class_name                       = var.ingress_class_name
  cert_issuer_name                         = var.cert_issuer_name
  cert_issuer_kind                         = var.cert_issuer_kind
  keycloak_url                             = var.keycloak_url
  keycloak_user                            = var.keycloak_user
  keycloak_password                        = var.keycloak_password
  keycloak_realm                           = var.keycloak_realm
  argocd_url                               = var.argocd_url
  keycloak_client_id                       = var.keycloak_client_id
  keycloak_enable_pkce                     = var.keycloak_enable_pkce
  principal_port                           = var.principal_port
  principal_replicas                       = var.principal_replicas
  principal_ingress_host                   = var.principal_ingress_host
  appproject_default_source_namespaces     = var.appproject_default_source_namespaces
  appproject_default_dest_server           = var.appproject_default_dest_server
  appproject_default_dest_namespaces       = var.appproject_default_dest_namespaces
  argocd_repo_server_name                  = var.argocd_repo_server_name
  argocd_application_controller_name       = var.argocd_application_controller_name
  argocd_redis_name                        = var.argocd_redis_name
  argocd_redis_network_policy_name         = var.argocd_redis_network_policy_name
  argocd_cmd_params_cm_name                = var.argocd_cmd_params_cm_name
  argocd_cm_name                           = var.argocd_cm_name
  argocd_secret_name                       = var.argocd_secret_name
  create_default_admin_user                = var.create_default_admin_user
  default_admin_username                   = var.default_admin_username
  default_admin_email                      = var.default_admin_email
  default_admin_password                   = var.default_admin_password
  default_admin_password_temporary         = var.default_admin_password_temporary

  depends_on = [
    module.cert_manager,
    module.ingress_nginx
  ]
}

# =============================================================================
# CERT-MANAGER ISSUER (created after hub namespace exists)
# =============================================================================

locals {
  issuer_namespace_local = var.cert_issuer_kind == "Issuer" ? var.hub_namespace : ""

  issuer_manifest_local = join("\n", [
    "apiVersion: cert-manager.io/v1",
    "kind: ${var.cert_issuer_kind}",
    "metadata:",
    "  name: ${var.cert_issuer_name}",
    var.cert_issuer_kind == "Issuer" ? "  namespace: ${var.hub_namespace}" : "",
    "spec:",
    "  acme:",
    "    server: https://acme-v02.api.letsencrypt.org/directory",
    "    email: ${var.letsencrypt_email}",
    "    privateKeySecretRef:",
    "      name: ${var.cert_issuer_name}-key",
    "    solvers:",
    "    - http01:",
    "        ingress:",
    "          class: ${var.ingress_class_name}",
  ])
}

resource "null_resource" "letsencrypt_issuer" {
  count = var.deploy_hub && var.install_cert_manager ? 1 : 0

  triggers = {
    cert_issuer_kind = var.cert_issuer_kind
    cert_issuer_name = var.cert_issuer_name
    namespace        = local.issuer_namespace_local
    manifest_hash    = md5(local.issuer_manifest_local)
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "[cert-manager] Creating ${var.cert_issuer_kind} ${var.cert_issuer_name}..."
      kubectl apply -f - <<EOF
${local.issuer_manifest_local}
EOF
      echo "[cert-manager] ✓ ${var.cert_issuer_kind} created successfully"
    EOT
  }

  provisioner "local-exec" {
    when       = destroy
    command    = "kubectl delete ${self.triggers.cert_issuer_kind} ${self.triggers.cert_issuer_name} --ignore-not-found=true ${self.triggers.cert_issuer_kind == "Issuer" ? "--namespace ${self.triggers.namespace}" : ""}"
    on_failure = continue
  }

  depends_on = [
    module.hub_cluster
  ]
}

# =============================================================================
# SPOKE CLUSTER MODULE
# =============================================================================

module "spoke_cluster" {
  count  = var.deploy_spokes ? 1 : 0
  source = "../../modules/spoke-cluster"

  providers = {
    # Spoke clusters use dynamic providers configured in provider.tf
  }

  # Cluster configuration
  clusters        = var.workload_clusters
  spoke_namespace = var.spoke_namespace

  # ArgoCD configuration
  argocd_version       = var.argocd_version
  argocd_agentctl_path = var.argocd_agentctl_path

  # Principal connection (from hub or external)
  principal_address = var.deploy_hub ? module.hub_cluster[0].principal_address : var.principal_address
  principal_port    = var.deploy_hub ? module.hub_cluster[0].principal_port : var.principal_port

  # Timeouts
  kubectl_timeout               = var.kubectl_timeout
  argocd_install_retry_attempts = var.argocd_install_retry_attempts
  argocd_install_retry_delay    = var.argocd_install_retry_delay

  # Service names
  principal_service_name      = var.principal_service_name
  resource_proxy_service_name = var.resource_proxy_service_name
  resource_proxy_port         = var.resource_proxy_port

  # AppProject configuration
  enable_appproject_sync               = var.enable_appproject_sync
  appproject_default_source_namespaces = var.appproject_default_source_namespaces
  appproject_default_dest_server       = var.appproject_default_dest_server
  appproject_default_dest_namespaces   = var.appproject_default_dest_namespaces

  # Hub cluster context (needed for agent operations)
  hub_cluster_context = var.hub_cluster_context
  hub_namespace       = var.hub_namespace

  # ArgoCD component names
  argocd_repo_server_name            = var.argocd_repo_server_name
  argocd_application_controller_name = var.argocd_application_controller_name
  argocd_redis_name                  = var.argocd_redis_name

  depends_on = [
    module.hub_cluster
  ]
}
