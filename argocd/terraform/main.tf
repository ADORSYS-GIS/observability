# =============================================================================
# SECTION 1: KEYCLOAK CONFIGURATION
# Configure the existing Keycloak to accept ArgoCD logins
# =============================================================================

# 1. Create the OIDC Client
resource "keycloak_openid_client" "argocd" {
  realm_id                     = var.target_realm
  client_id                    = "argocd-client"
  name                         = "ArgoCD"
  enabled                      = true
  access_type                  = "CONFIDENTIAL"
  standard_flow_enabled        = true
  direct_access_grants_enabled = true

  # This must match your ArgoCD URL exactly
  valid_redirect_uris = [
    "${var.argocd_url}/auth/callback",
    "${var.argocd_url}/*" # Temporary wildcard to troubleshoot
  ]
}

resource "keycloak_openid_client_default_scopes" "client_default_scopes" {
  realm_id  = var.target_realm
  client_id = keycloak_openid_client.argocd.id

  default_scopes = [
    "openid",
    "profile",
    "email",
    "roles"
  ]
}

# 2. Create the Client Secret
# (The provider generates this automatically, we just access it later)

# 3. Create Group Mapper
# This ensures Keycloak sends the "groups" claim so ArgoCD can do RBAC
resource "keycloak_openid_group_membership_protocol_mapper" "groups" {
  realm_id   = var.target_realm
  client_id  = keycloak_openid_client.argocd.id
  name       = "group-mapper"
  claim_name = "groups"
  full_path  = false
}

# =============================================================================
# SECTION 2: ARGOCD DEPLOYMENT (HELMS)
# Deploy ArgoCD to GKE and inject the secrets from Section 1
# =============================================================================

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = var.namespace
  create_namespace = true
  version          = var.argocd_version
  skip_crds        = false

  # Using values (YAML) instead of set avoids comma parsing errors entirely
  values = [
    yamlencode({
      configs = {
        cm = {
          url = var.argocd_url
          "oidc.config" = yamlencode({
            name            = "Keycloak"
            issuer          = "${var.keycloak_url}/realms/${var.target_realm}"
            clientID        = keycloak_openid_client.argocd.client_id
            clientSecret    = keycloak_openid_client.argocd.client_secret
            requestedScopes = ["openid", "profile", "email"]

            rootCA = ""
          })
        }
        rbac = {
          "policy.csv" = "g, /ArgoCDAdmins, role:admin"
        }
      }
    })
  ]
}


# Managing certificate signing and creation
# Cert-Manager Module
module "cert_manager" {
  providers = {
    kubernetes = kubernetes
    helm       = helm
  }

  source = "../../cert-manager/terraform"

  install_cert_manager = var.install_cert_manager
  cert_manager_version = var.cert_manager_version
  release_name         = var.cert_manager_release_name
  namespace            = var.cert_manager_namespace

  letsencrypt_email = var.letsencrypt_email
  cert_issuer_name  = var.cert_issuer_name
  cert_issuer_kind  = var.cert_issuer_kind
  # If Kind is Issuer, it must be in the observability namespace to be used by the ingress in that namespace.
  # If Kind is ClusterIssuer, this variable is ignored by the module logic.
  issuer_namespace   = var.namespace
  ingress_class_name = var.ingress_class_name

  # Ensure namespace exists before issuer creation (handled inside module)
}

# Setting Up An Ingress Controller
# Ingress Controller Module
module "ingress_nginx" {
  source = "../../ingress-controller/terraform"

  install_nginx_ingress = var.install_nginx_ingress
  nginx_ingress_version = var.nginx_ingress_version
  release_name          = var.nginx_ingress_release_name
  namespace             = var.nginx_ingress_namespace
  ingress_class_name    = var.ingress_class_name
}



# =============================================================================
# OUTPUTS
# =============================================================================

output "keycloak_client_secret" {
  value     = keycloak_openid_client.argocd.client_secret
  sensitive = true
}
