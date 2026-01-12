terraform {
  required_providers {
    keycloak = {
      source  = "mrparkers/keycloak"
      version = ">= 4.0.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.0.0"
    }
  }
}

# 1. Connect to your EXISTING Keycloak
provider "keycloak" {
  client_id = "admin-cli"
  url       = var.keycloak_url      # e.g. https://auth.example.com
  username  = var.keycloak_user
  password  = var.keycloak_password
}



# 2. Connect to GKE using your local terminal credentials
provider "helm" {
  kubernetes {
    config_path    = "~/.kube/config"
    config_context = var.kube_context # Optional: specify if you have multiple contexts
  }
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = var.kube_context # Optional: specify if you have multiple contexts
}