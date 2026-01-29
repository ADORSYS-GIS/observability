terraform {
  required_version = ">= 1.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.30.0, < 2.32.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.12.0, < 2.14.0"
    }
    keycloak = {
      source  = "mrparkers/keycloak"
      version = ">= 4.4.0, < 4.5.0"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.2.0, < 3.3.0"
    }
    external = {
      source  = "hashicorp/external"
      version = ">= 2.3.0, < 2.4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6.0, < 3.7.0"
    }
  }
}
