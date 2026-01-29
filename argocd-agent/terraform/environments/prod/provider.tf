# =============================================================================
# PROVIDER CONFIGURATION
# =============================================================================
# Configures providers for hub and spoke clusters
# =============================================================================

data "google_client_config" "default" {}

data "google_container_cluster" "hub" {
  name     = var.cluster_name
  location = var.region
  project  = var.project_id
}

provider "kubernetes" {
  host                   = "https://${data.google_container_cluster.hub.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(data.google_container_cluster.hub.master_auth[0].cluster_ca_certificate)
}

provider "helm" {
  alias = "hub"
  kubernetes {
    host                   = "https://${data.google_container_cluster.hub.endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(data.google_container_cluster.hub.master_auth[0].cluster_ca_certificate)
  }
}

provider "keycloak" {
  client_id = "admin-cli"
  url       = var.keycloak_url
  username  = var.keycloak_user
  password  = var.keycloak_password
}

# Spoke cluster providers are configured dynamically
# Each spoke cluster context is passed through variables

# Note: Spoke cluster operations are handled via kubectl --context flags
# in null_resource provisioners to support dynamic multi-cluster management
