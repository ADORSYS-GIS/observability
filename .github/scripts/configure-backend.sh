#!/bin/bash

set -euo pipefail

# Configure Terraform backend based on cloud provider
# Usage: configure-backend.sh <cloud_provider> <environment>

CLOUD_PROVIDER="${1:-gke}"
ENVIRONMENT="${2:-dev}"
BACKEND_FILE="backend-config.tf"

echo "🔧 Configuring Terraform backend for: $CLOUD_PROVIDER ($ENVIRONMENT)"

case "$CLOUD_PROVIDER" in
  gke)
    cat > "$BACKEND_FILE" <<EOF
terraform {
  backend "gcs" {
    bucket = "${TF_STATE_BUCKET}"
    prefix = "terraform/argocd-agent/${ENVIRONMENT}"
  }
}
EOF
    echo "✅ Configured GCS backend: ${TF_STATE_BUCKET} (prefix: terraform/argocd-agent/${ENVIRONMENT})"
    ;;
    
  eks)
    cat > "$BACKEND_FILE" <<EOF
terraform {
  backend "s3" {
    bucket = "${TF_STATE_BUCKET}"
    key    = "terraform/argocd-agent/${ENVIRONMENT}/terraform.tfstate"
    region = "${AWS_REGION}"
  }
}
EOF
    echo "✅ Configured S3 backend: ${TF_STATE_BUCKET} (key: terraform/argocd-agent/${ENVIRONMENT}/terraform.tfstate)"
    ;;
    
  aks)
    cat > "$BACKEND_FILE" <<EOF
terraform {
  backend "azurerm" {
    storage_account_name = "${AZURE_STORAGE_ACCOUNT}"
    container_name       = "${AZURE_STORAGE_CONTAINER}"
    key                  = "terraform/argocd-agent/${ENVIRONMENT}/terraform.tfstate"
  }
}
EOF
    echo "✅ Configured Azure Blob backend: ${AZURE_STORAGE_ACCOUNT}/${AZURE_STORAGE_CONTAINER}"
    ;;
    
  generic)
    cat > "$BACKEND_FILE" <<EOF
terraform {
  backend "kubernetes" {
    secret_suffix    = "argocd-agent-${ENVIRONMENT}"
    namespace        = "kube-system"
    labels = {
      "managed-by" = "terraform"
      "component"  = "argocd-agent"
      "environment" = "${ENVIRONMENT}"
    }
  }
}
EOF
    echo "✅ Configured Kubernetes backend (secret suffix: argocd-agent-${ENVIRONMENT})"
    ;;
    
  *)
    echo "❌ Unknown cloud provider: $CLOUD_PROVIDER"
    exit 1
    ;;
esac

echo "📄 Backend configuration written to: $BACKEND_FILE"
