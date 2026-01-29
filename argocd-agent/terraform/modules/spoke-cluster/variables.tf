# =============================================================================
# DEPLOYMENT CONTROL
# =============================================================================

variable "clusters" {
  description = "Map of agent_name => cluster_context for spoke clusters (module input). Renamed from workload_clusters for module interface."
  type        = map(string)
}

variable "hub_cluster_context" {
  description = "Kubectl context for hub cluster"
  type        = string
}

# =============================================================================
# ARGOCD CONFIGURATION
# =============================================================================

variable "argocd_version" {
  description = "ArgoCD Agent version to deploy"
  type        = string
  default     = "v0.5.3"
}

variable "hub_namespace" {
  description = "Namespace for ArgoCD on hub cluster"
  type        = string
  default     = "argocd"
}

variable "spoke_namespace" {
  description = "Namespace for ArgoCD on spoke clusters"
  type        = string
  default     = "argocd"
}

# =============================================================================
# EXPOSURE CONFIGURATION
# =============================================================================

variable "ui_expose_method" {
  description = "How to expose ArgoCD UI: 'loadbalancer' or 'ingress'"
  type        = string
  default     = "ingress"

  validation {
    condition     = contains(["loadbalancer", "ingress"], var.ui_expose_method)
    error_message = "The ui_expose_method must be either 'loadbalancer' or 'ingress'."
  }
}

variable "principal_expose_method" {
  description = "How to expose Principal service: 'loadbalancer', 'ingress', or 'nodeport'"
  type        = string
  default     = "ingress"

  validation {
    condition     = contains(["loadbalancer", "ingress", "nodeport"], var.principal_expose_method)
    error_message = "The principal_expose_method must be one of 'loadbalancer', 'ingress', or 'nodeport'."
  }
}

variable "argocd_host" {
  description = "Hostname for ArgoCD UI (required if ui_expose_method='ingress')"
  type        = string
  default     = ""
}

# =============================================================================
# EXTERNAL PRINCIPAL (for spoke-only deployments)
# =============================================================================

variable "principal_address" {
  description = "External Principal IP/hostname (only needed if deploy_hub=false). Get this from hub deployment outputs."
  type        = string
  default     = ""
}

variable "principal_port" {
  description = "External Principal port (only needed if deploy_hub=false)"
  type        = number
  default     = 443
}

# =============================================================================
# KEYCLOAK INTEGRATION
# =============================================================================

variable "enable_keycloak" {
  description = "Enable Keycloak OIDC authentication for ArgoCD"
  type        = bool
  default     = false
}

variable "keycloak_url" {
  description = "Keycloak URL (e.g., https://keycloak.example.com)"
  type        = string
  default     = ""

  validation {
    condition     = var.enable_keycloak ? var.keycloak_url != "" : true
    error_message = "The keycloak_url is required when enable_keycloak is true."
  }
}

variable "keycloak_user" {
  description = "Keycloak admin username"
  type        = string
  default     = "admin"
}

variable "keycloak_password" {
  description = "Keycloak admin password"
  type        = string
  sensitive   = true
  default     = ""

  validation {
    condition     = var.enable_keycloak ? var.keycloak_password != "" : true
    error_message = "The keycloak_password is required when enable_keycloak is true."
  }
}

variable "keycloak_realm" {
  description = "Keycloak realm name to create ArgoCD client in"
  type        = string
  default     = "argocd"
}

variable "argocd_url" {
  description = "ArgoCD URL for Keycloak redirect URIs (e.g., https://argocd.example.com)"
  type        = string
  default     = ""

  validation {
    condition     = var.enable_keycloak ? var.argocd_url != "" : true
    error_message = "The argocd_url is required when enable_keycloak is true."
  }
}

variable "keycloak_client_id" {
  description = "Keycloak OIDC client ID for ArgoCD"
  type        = string
  default     = "argocd"
}

variable "keycloak_enable_pkce" {
  description = "Enable PKCE authentication method (true) instead of Client Authentication (false). PKCE enables CLI login with --sso."
  type        = bool
  default     = false

  validation {
    condition     = var.keycloak_enable_pkce == true || var.keycloak_enable_pkce == false
    error_message = "The keycloak_enable_pkce must be either true or false."
  }
}

variable "create_default_admin_user" {
  description = "Create a default admin user in Keycloak for initial ArgoCD access"
  type        = bool
  default     = true
}

variable "default_admin_username" {
  description = "Default admin username for Keycloak"
  type        = string
  default     = "argocd-admin"
}

variable "default_admin_email" {
  description = "Default admin email for Keycloak"
  type        = string
  default     = "admin@argocd.local"
}

variable "default_admin_password" {
  description = "Default admin password for Keycloak (change after first login if temporary)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "default_admin_password_temporary" {
  description = "Whether the default admin password is temporary (user must change on first login)"
  type        = bool
  default     = true
}

# =============================================================================
# RESOURCE PROXY & AGENT CREDENTIALS
# =============================================================================

variable "enable_resource_proxy_credentials_secret" {
  description = "Store resource proxy credentials in Kubernetes secret for reference and rotation"
  type        = bool
  default     = true
}

variable "enable_principal_ingress" {
  description = "Expose Principal via Ingress (in addition to LoadBalancer). Requires cert-manager and nginx-ingress."
  type        = bool
  default     = false
}

variable "principal_ingress_host" {
  description = "Hostname for Principal Ingress (e.g., principal.example.com)"
  type        = string
  default     = ""
}

# =============================================================================
# APPPROJECT CONFIGURATION
# =============================================================================

variable "enable_appproject_sync" {
  description = "Enable automatic AppProject synchronization to agents (required for managed mode)"
  type        = bool
  default     = true
}

variable "appproject_default_source_namespaces" {
  description = "Default AppProject source namespaces (repositories) - use ['*'] for all"
  type        = list(string)
  default     = ["*"]
}

variable "appproject_default_dest_server" {
  description = "Default AppProject destination server - use '*' for all"
  type        = string
  default     = "*"
}

variable "appproject_default_dest_namespaces" {
  description = "Default AppProject destination namespaces - use ['*'] for all"
  type        = list(string)
  default     = ["*"]
}

# =============================================================================
# INFRASTRUCTURE MODULES
# =============================================================================

variable "install_cert_manager" {
  description = "Install cert-manager (set to false if already exists in cluster)"
  type        = bool
  default     = false
}

variable "install_nginx_ingress" {
  description = "Install nginx ingress controller (set to false if already exists in cluster)"
  type        = bool
  default     = false
}

variable "cert_manager_version" {
  description = "cert-manager Helm chart version"
  type        = string
  default     = "v1.16.2"
}

variable "nginx_ingress_version" {
  description = "nginx-ingress Helm chart version"
  type        = string
  default     = "4.11.3"
}

variable "cert_manager_release_name" {
  description = "Helm release name for cert-manager"
  type        = string
  default     = "cert-manager"
}

variable "cert_manager_namespace" {
  description = "Namespace for cert-manager"
  type        = string
  default     = "cert-manager"
}

variable "nginx_ingress_release_name" {
  description = "Helm release name for nginx-ingress"
  type        = string
  default     = "nginx-ingress"
}

variable "nginx_ingress_namespace" {
  description = "Namespace for nginx-ingress"
  type        = string
  default     = "ingress-nginx"
}

variable "cert_issuer_name" {
  description = "Name of the cert-manager ClusterIssuer"
  type        = string
  default     = "letsencrypt-prod"
}

variable "cert_issuer_kind" {
  description = "Kind of cert-manager issuer: 'Issuer' (namespace-scoped) or 'ClusterIssuer' (cluster-wide)"
  type        = string
  default     = "Issuer"
}

variable "letsencrypt_email" {
  description = "Email for Let's Encrypt certificate notifications"
  type        = string
  default     = ""
}

variable "ingress_class_name" {
  description = "Ingress class name to use"
  type        = string
  default     = "nginx"
}

# =============================================================================
# PATHS AND TOOLS
# =============================================================================

variable "argocd_agentctl_path" {
  description = "Path to argocd-agentctl binary (installed to /usr/local/bin by Terraform)"
  type        = string
  default     = "/usr/local/bin/argocd-agentctl"
}

# =============================================================================
# HIGH AVAILABILITY
# =============================================================================

variable "principal_replicas" {
  description = "Number of Principal replicas for HA (1=dev, 2+=production). Enables PodDisruptionBudget when >1"
  type        = number
  default     = 1

  validation {
    condition     = var.principal_replicas >= 1 && var.principal_replicas <= 5
    error_message = "The principal_replicas must be between 1 and 5."
  }
}

# =============================================================================
# TIMEOUTS AND OPERATIONAL PARAMETERS
# =============================================================================

variable "kubectl_timeout" {
  description = "Timeout for kubectl wait operations (deployment rollouts, pod ready checks)"
  type        = string
  default     = "300s"

  validation {
    condition     = can(regex("^[0-9]+[smh]$", var.kubectl_timeout))
    error_message = "The kubectl_timeout must be a valid duration (e.g., 300s, 5m, 1h)."
  }
}

variable "namespace_delete_timeout" {
  description = "Timeout for namespace deletion operations"
  type        = string
  default     = "120s"

  validation {
    condition     = can(regex("^[0-9]+[smh]$", var.namespace_delete_timeout))
    error_message = "The namespace_delete_timeout must be a valid duration (e.g., 120s, 2m)."
  }
}

variable "argocd_install_retry_attempts" {
  description = "Number of retry attempts for ArgoCD installation (handles transient network issues)"
  type        = number
  default     = 5

  validation {
    condition     = var.argocd_install_retry_attempts >= 1 && var.argocd_install_retry_attempts <= 10
    error_message = "The argocd_install_retry_attempts must be between 1 and 10."
  }
}

variable "argocd_install_retry_delay" {
  description = "Delay between ArgoCD installation retry attempts (seconds)"
  type        = number
  default     = 15

  validation {
    condition     = var.argocd_install_retry_delay >= 5 && var.argocd_install_retry_delay <= 60
    error_message = "The argocd_install_retry_delay must be between 5 and 60 seconds."
  }
}

variable "principal_loadbalancer_wait_timeout" {
  description = "Maximum wait time for Principal LoadBalancer IP allocation (seconds)"
  type        = number
  default     = 300

  validation {
    condition     = var.principal_loadbalancer_wait_timeout >= 60 && var.principal_loadbalancer_wait_timeout <= 600
    error_message = "The principal_loadbalancer_wait_timeout must be between 60 and 600 seconds."
  }
}

# =============================================================================
# SERVICE NAMING AND DNS
# =============================================================================

variable "argocd_server_service_name" {
  description = "Name of the ArgoCD server service"
  type        = string
  default     = "argocd-server"
}

variable "principal_service_name" {
  description = "Name of the ArgoCD Agent Principal service"
  type        = string
  default     = "argocd-agent-principal"
}

variable "resource_proxy_service_name" {
  description = "Name of the ArgoCD Agent resource-proxy service"
  type        = string
  default     = "argocd-agent-resource-proxy"
}

variable "resource_proxy_port" {
  description = "Port for resource-proxy service"
  type        = number
  default     = 9090

  validation {
    condition     = var.resource_proxy_port > 0 && var.resource_proxy_port <= 65535
    error_message = "The resource_proxy_port must be a valid port number (1-65535)."
  }
}

variable "argocd_repo_server_name" {
  description = "Name of the ArgoCD repo-server deployment"
  type        = string
  default     = "argocd-repo-server"
}

variable "argocd_application_controller_name" {
  description = "Name of the ArgoCD application-controller statefulset"
  type        = string
  default     = "argocd-application-controller"
}

variable "argocd_redis_name" {
  description = "Name of the ArgoCD Redis deployment"
  type        = string
  default     = "argocd-redis"
}

variable "argocd_redis_network_policy_name" {
  description = "Name of the ArgoCD Redis NetworkPolicy"
  type        = string
  default     = "argocd-redis-network-policy"
}

variable "argocd_cmd_params_cm_name" {
  description = "Name of the ArgoCD command parameters ConfigMap"
  type        = string
  default     = "argocd-cmd-params-cm"
}

variable "argocd_cm_name" {
  description = "Name of the main ArgoCD ConfigMap"
  type        = string
  default     = "argocd-cm"
}

variable "argocd_secret_name" {
  description = "Name of the ArgoCD secret"
  type        = string
  default     = "argocd-secret"
}
