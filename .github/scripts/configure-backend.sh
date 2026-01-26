#!/bin/bash
set -euo pipefail

# Configure Terraform backend based on cloud provider
# Usage: configure-backend.sh <cloud_provider>

CLOUD_PROVIDER="${1:-gke}"
BACKEND_FILE="backend-config.tf"

echo "🔧 Configuring Terraform backend for: $CLOUD_PROVIDER"

case "$CLOUD_PROVIDER" in
  gke)
    cat > "$BACKEND_FILE" <<EOF
terraform {
  backend "gcs" {
    bucket = "${TF_STATE_BUCKET}"
    prefix = "terraform/lgtm-stack"
  }
}
EOF
    echo "✅ Configured GCS backend: ${TF_STATE_BUCKET}"
    ;;
    
  eks)
    cat > "$BACKEND_FILE" <<EOF
terraform {
  backend "s3" {
    bucket = "${TF_STATE_BUCKET}"
    key    = "terraform/lgtm-stack/terraform.tfstate"
    region = "${AWS_REGION}"
  }
}
EOF
    echo "✅ Configured S3 backend: ${TF_STATE_BUCKET}"
    ;;
    
  aks)
    cat > "$BACKEND_FILE" <<EOF
terraform {
  backend "azurerm" {
    storage_account_name = "${AZURE_STORAGE_ACCOUNT}"
    container_name       = "${AZURE_STORAGE_CONTAINER}"
    key                  = "terraform/lgtm-stack/terraform.tfstate"
  }
}
EOF
    echo "✅ Configured Azure Blob backend: ${AZURE_STORAGE_ACCOUNT}/${AZURE_STORAGE_CONTAINER}"
    ;;
    
  generic)
    cat > "$BACKEND_FILE" <<EOF
terraform {
  backend "kubernetes" {
    secret_suffix    = "lgtm-stack"
    namespace        = "kube-system"
    labels = {
      "managed-by" = "terraform"
      "component"  = "lgtm-stack"
    }
  }
}
EOF
    echo "✅ Configured Kubernetes backend (secret in kube-system)"
    ;;
    
  *)
    echo "❌ Unknown cloud provider: $CLOUD_PROVIDER"
    exit 1
    ;;
esac

echo "📄 Backend configuration written to: $BACKEND_FILE"
