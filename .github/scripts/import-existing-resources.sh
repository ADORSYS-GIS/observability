#!/bin/bash

set -euo pipefail

# Smart import of existing Kubernetes resources into Terraform state
# Only imports resources that exist in K8s but NOT in Terraform state

NAMESPACE="${NAMESPACE:-argocd-agent}"
REPORT_FILE="import-report.json"

echo "🔍 Scanning for existing ArgoCD Agent resources..."

# Initialize report
cat > "$REPORT_FILE" <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "imports": [],
  "skipped": [],
  "errors": []
}
EOF

# Helper function to check if resource is in Terraform state
is_in_terraform_state() {
  local tf_address="$1"
  
  if terraform state show "$tf_address" &>/dev/null; then
    return 0  # Already in state
  else
    return 1  # Not in state
  fi
}

# Helper function to attempt terraform import (only if needed)
smart_import() {
  local tf_address="$1"
  local resource_id="$2"
  local description="$3"
  
  echo "  📦 Checking: $description"
  
  # First check if already in Terraform state
  if is_in_terraform_state "$tf_address"; then
    echo "    ✅ Already in Terraform state (using existing)"
    jq --arg addr "$tf_address" --arg reason "already_in_state" \
      '.skipped += [{"address": $addr, "reason": $reason}]' \
      "$REPORT_FILE" > /tmp/report.tmp && mv /tmp/report.tmp "$REPORT_FILE"
    return 0
  fi
  
  # Not in state, attempt import
  echo "    🔄 Not in state, attempting import..."
  
  if terraform import "$tf_address" "$resource_id" 2>&1 | tee /tmp/import.log; then
    echo "    ✅ Import successful"
    jq --arg addr "$tf_address" --arg id "$resource_id" --arg desc "$description" \
      '.imports += [{"address": $addr, "id": $id, "description": $desc}]' \
      "$REPORT_FILE" > /tmp/report.tmp && mv /tmp/report.tmp "$REPORT_FILE"
    return 0
  else
    if grep -q "Resource already managed" /tmp/import.log; then
      echo "    ℹ️  Already managed by Terraform"
      jq --arg addr "$tf_address" --arg reason "already_managed" \
        '.skipped += [{"address": $addr, "reason": $reason}]' \
        "$REPORT_FILE" > /tmp/report.tmp && mv /tmp/report.tmp "$REPORT_FILE"
    else
      echo "    ⚠️  Import failed (resource may not exist in K8s)"
      jq --arg addr "$tf_address" --arg error "$(cat /tmp/import.log | tail -3 | tr '\n' ' ')" \
        '.errors += [{"address": $addr, "error": $error}]' \
        "$REPORT_FILE" > /tmp/report.tmp && mv /tmp/report.tmp "$REPORT_FILE"
    fi
    return 1
  fi
}

# Check if namespace exists in K8s
if kubectl get namespace "$NAMESPACE" &>/dev/null; then
  echo "📂 Found existing namespace in K8s: $NAMESPACE"
  # Use correct module address for Hub Cluster namespace
  smart_import \
    "module.hub_cluster[0].kubernetes_namespace.hub_argocd" \
    "$NAMESPACE" \
    "Hub Namespace: $NAMESPACE"
else
  echo "  ℹ️  Namespace $NAMESPACE does not exist in K8s (will be created by Terraform)"
fi

# Service Account Imports DISABLED
# Reason: These resources are created via 'null_resource' / 'kubectl apply' in Terraform
# and imply no directly managed 'resource "kubernetes_service_account"' block exists.
# Attempting to import them would fail with "Resource not found in configuration".

# Check for existing service accounts in argocd-agent namespace
# if kubectl get namespace "$NAMESPACE" &>/dev/null; then
#   if kubectl get serviceaccount -n "$NAMESPACE" argocd-agent-sa &>/dev/null; then
#     echo "👤 Found existing service account in K8s: argocd-agent-sa (Skipping import - managed via manifests)"
#     # smart_import \
#     #   "kubernetes_service_account.argocd_agent_sa" \
#     #   "$NAMESPACE/argocd-agent-sa" \
#     #   "Kubernetes Service Account"
#   fi
# fi

# GKE Specific: Check for GCP Service Account (if CLOUD_PROVIDER is set)
# if [ "${CLOUD_PROVIDER:-}" == "gke" ]; then
#   GCP_PROJECT_ID="${GCP_PROJECT_ID:-}"
#   if [ -n "$GCP_PROJECT_ID" ]; then
#     SA_NAME="gke-argocd-agent-sa"
#     SA_EMAIL="${SA_NAME}@${GCP_PROJECT_ID}.iam.gserviceaccount.com"
#     
#     if command -v gcloud &>/dev/null; then
#       if gcloud iam service-accounts describe "$SA_EMAIL" --project="$GCP_PROJECT_ID" &>/dev/null 2>&1; then
#         echo "👤 Found existing GCP Service Account: $SA_NAME (Skipping import - module not active)"
#         # smart_import \
#         #   "module.cloud_gke[0].google_service_account.argocd_agent_sa" \
#         #   "projects/${GCP_PROJECT_ID}/serviceAccounts/${SA_EMAIL}" \
#         #   "GCP Service Account: $SA_NAME"
#       fi
#     else
#       echo "  ⚠️  gcloud CLI not available, skipping GCP service account check"
#     fi
#   fi
# fi

# Keycloak Realm: Check if realm already exists (by attempting import)
KEYCLOAK_URL="${KEYCLOAK_URL:-}"
if [ -n "$KEYCLOAK_URL" ]; then
  echo "🔐 Checking for existing Keycloak realm 'argocd'..."
  # We assume if Keycloak URL is provided, we might need to import the realm
  
  smart_import \
    "module.hub_cluster[0].keycloak_realm.argocd[0]" \
    "argocd" \
    "Keycloak Realm: argocd"
fi

# Summary
echo ""
echo "📊 Import Summary:"
IMPORTED=$(jq -r '.imports | length' "$REPORT_FILE")
SKIPPED=$(jq -r '.skipped | length' "$REPORT_FILE")
ERRORS=$(jq -r '.errors | length' "$REPORT_FILE")

echo "  ✅ Imported: $IMPORTED"
echo "  ⏭️  Skipped (already in state): $SKIPPED"
echo "  ❌ Errors: $ERRORS"

echo ""
echo "📄 Full report saved to: $REPORT_FILE"
cat "$REPORT_FILE" | jq '.'

# Exit successfully even if some imports failed
# This allows the workflow to continue
exit 0
