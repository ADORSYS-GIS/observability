#!/bin/bash
set -euo pipefail

# =============================================================================
# Terraform Backend Configuration Script
# =============================================================================
# This script generates the backend configuration for Terraform state storage.
# State files are stored in cloud provider buckets for collaboration and durability.
#
# IMPORTANT: State files are NEVER deleted by this script or workflows.
# Only the backend-config.tf file is regenerated to ensure correct configuration.
#
# Usage: ./configure-backend.sh <cloud_provider> <component>
#   cloud_provider: gke, eks, aks, or generic
#   component: cert-manager, ingress-controller, lgtm-stack, argocd-agent, etc.
#
# Environment Variables Required:
#   GKE: TF_STATE_BUCKET (GCS bucket name)
#   EKS: TF_STATE_BUCKET (S3 bucket name), AWS_REGION
#   AKS: AZURE_STORAGE_ACCOUNT, AZURE_STORAGE_CONTAINER
# =============================================================================

CLOUD_PROVIDER="${1:-gke}"
COMPONENT="${2:-lgtm-stack}"
BACKEND_FILE="backend-config.tf"

echo "Configuring Terraform backend for: $CLOUD_PROVIDER / $COMPONENT"
echo "State files will be stored remotely and persist across workflow runs"

case "$CLOUD_PROVIDER" in
  gke)
    if [ -z "${TF_STATE_BUCKET:-}" ]; then
      echo "ERROR: TF_STATE_BUCKET environment variable is required for GKE"
      echo "   Set it in GitHub Secrets or export it locally"
      exit 1
    fi
    cat > "$BACKEND_FILE" <<EOF
# Auto-generated backend configuration for GCS
# State files are stored at: gs://${TF_STATE_BUCKET}/terraform/${COMPONENT}/
terraform {
  backend "gcs" {
    bucket = "${TF_STATE_BUCKET}"
    prefix = "terraform/${COMPONENT}"
  }
}
EOF
    echo "Configured GCS backend: ${TF_STATE_BUCKET}/terraform/${COMPONENT}"
    ;;
    
  eks)
    if [ -z "${TF_STATE_BUCKET:-}" ]; then
      echo "ERROR: TF_STATE_BUCKET environment variable is required for EKS"
      exit 1
    fi
    if [ -z "${AWS_REGION:-}" ]; then
      echo "ERROR: AWS_REGION environment variable is required for EKS"
      exit 1
    fi
    cat > "$BACKEND_FILE" <<EOF
# Auto-generated backend configuration for S3
# State files are stored at: s3://${TF_STATE_BUCKET}/terraform/${COMPONENT}/
terraform {
  backend "s3" {
    bucket         = "${TF_STATE_BUCKET}"
    key            = "terraform/${COMPONENT}/terraform.tfstate"
    region         = "${AWS_REGION}"
    encrypt        = true
    dynamodb_table = "${TF_STATE_LOCK_TABLE:-terraform-state-lock}"
  }
}
EOF
    echo "Configured S3 backend: ${TF_STATE_BUCKET}/terraform/${COMPONENT}"
    echo "   Using DynamoDB lock table: ${TF_STATE_LOCK_TABLE:-terraform-state-lock}"
    ;;
    
  aks)
    if [ -z "${AZURE_STORAGE_ACCOUNT:-}" ]; then
      echo "ERROR: AZURE_STORAGE_ACCOUNT environment variable is required for AKS"
      exit 1
    fi
    if [ -z "${AZURE_STORAGE_CONTAINER:-}" ]; then
      echo "ERROR: AZURE_STORAGE_CONTAINER environment variable is required for AKS"
      exit 1
    fi
    cat > "$BACKEND_FILE" <<EOF
# Auto-generated backend configuration for Azure Blob Storage
# State files are stored at: ${AZURE_STORAGE_ACCOUNT}/${AZURE_STORAGE_CONTAINER}/terraform/${COMPONENT}/
terraform {
  backend "azurerm" {
    storage_account_name = "${AZURE_STORAGE_ACCOUNT}"
    container_name       = "${AZURE_STORAGE_CONTAINER}"
    key                  = "terraform/${COMPONENT}/terraform.tfstate"
  }
}
EOF
    echo "Configured Azure Blob backend: ${AZURE_STORAGE_ACCOUNT}/${AZURE_STORAGE_CONTAINER}/terraform/${COMPONENT}"
    ;;
    
  generic)
    cat > "$BACKEND_FILE" <<EOF
# Auto-generated backend configuration for Kubernetes
# State stored as Secret in kube-system namespace
terraform {
  backend "kubernetes" {
    secret_suffix    = "${COMPONENT}"
    namespace        = "kube-system"
    labels = {
      "managed-by" = "terraform"
      "component"  = "${COMPONENT}"
    }
  }
}
EOF
    echo "Configured Kubernetes backend (secret in kube-system) for ${COMPONENT}"
    echo "   WARNING: Kubernetes backend is not recommended for production"
    echo "   Consider using cloud storage (GCS/S3/Azure Blob) for better durability"
    ;;
    
  *)
    echo "ERROR: Unknown cloud provider: $CLOUD_PROVIDER"
    exit 1
    ;;
esac

echo "Backend configuration written to: $BACKEND_FILE"
echo ""
echo "State Management:"
echo "   - State files persist in remote storage across all runs"
echo "   - Only backend-config.tf is regenerated (not state files)"
echo "   - Multiple team members can collaborate using the same bucket"
echo "   - State locking prevents concurrent modifications"
