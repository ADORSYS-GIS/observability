#!/bin/bash
# ArgoCD Agent Cleanup Script
#
# Usage:
#   ./cleanup.sh [target] [-f]
#
# Targets:
#   all         - Clean Hub + all spokes (spoke-1, spoke-2, spoke-3)
#   hub         - Clean only Hub (Principal, PKI, ArgoCD, agent namespaces)
#   spokes      - Clean all spokes (spoke-1, spoke-2, spoke-3) but keep Hub
#   spoke-1     - Clean only spoke-1 cluster
#   spoke-2     - Clean only spoke-2 cluster  
#   spoke-3     - Clean only spoke-3 cluster
#
# Options:
#   -f          - Force mode (skip confirmation)
#
# Examples:
#   ./cleanup.sh all -f       # Clean everything without confirmation
#   ./cleanup.sh spokes       # Clean all spokes, keep Hub
#   ./cleanup.sh spoke-1 -f   # Clean only spoke-1
#   ./cleanup.sh spoke-2 -f   # Clean only spoke-2

# ═══════════════════════════════════════════════════════════════════════════════
# Configuration Extraction
# ═══════════════════════════════════════════════════════════════════════════════

TF_VARS="$(dirname "$0")/../terraform/environments/prod/terraform.tfvars"

if [ ! -f "$TF_VARS" ]; then
  echo "❌ Error: terraform.tfvars not found at $TF_VARS"
  exit 1
fi

# Extract Hub Context
export HUB_CTX=$(grep "hub_cluster_context" "$TF_VARS" | cut -d'"' -f2)

# Extract ArgoCD version
VERSION=$(grep "argocd_version" "$TF_VARS" | cut -d'"' -f2)

# Extract Spoke Contexts and Agent Names
# This parses the workload_clusters map from terraform.tfvars
ALL_AGENTS=($(grep -A 20 "workload_clusters =" "$TF_VARS" | grep "=" | grep -v "{" | cut -d'"' -f2))
ALL_SPOKES=($(grep -A 20 "workload_clusters =" "$TF_VARS" | grep "=" | grep -v "{" | cut -d'"' -f4))

if [ -z "$HUB_CTX" ]; then
  echo "❌ Error: Could not extract hub_cluster_context from $TF_VARS"
  exit 1
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Helper Functions
# ═══════════════════════════════════════════════════════════════════════════════

force_delete() {
  local KIND="$1"
  local NAME="$2"
  local NS="$3"  # Optional, pass "" if cluster-scoped
  local CONTEXT="$4"
  
  local NS_FLAG=""
  if [ -n "$NS" ]; then
    NS_FLAG="-n $NS"
  fi

  # 1. Attempt normal delete in background
  echo "  → Deleting $KIND $NAME..."
  kubectl delete $KIND $NAME $NS_FLAG --context $CONTEXT --ignore-not-found=true --wait=false 2>/dev/null &
  
  # 2. Wait a bit
  local ATTEMPTS=0
  while [ $ATTEMPTS -lt 10 ]; do
    if ! kubectl get $KIND $NAME $NS_FLAG --context $CONTEXT &>/dev/null; then
      echo "    ✓ Deleted"
      return 0
    fi
    sleep 1
    ATTEMPTS=$((ATTEMPTS+1))
  done
  
  # 3. If still exists, patch finalizers
  echo "    ⚠️  Stuck. Force removing finalizers..."
  kubectl patch $KIND $NAME $NS_FLAG --context $CONTEXT -p '{"metadata":{"finalizers":[]}}' --type=merge &>/dev/null || true
  
  # 4. Wait again
  sleep 2
  if ! kubectl get $KIND $NAME $NS_FLAG --context $CONTEXT &>/dev/null; then
    echo "    ✓ Deleted (Forced)"
  else
    echo "    ❌ Failed to delete $KIND $NAME"
  fi
}

clean_spoke() {
  local CTX="$1"
  echo ""
  echo "───────────────────────────────────────────────"
  echo "  Cleaning Spoke: $CTX"
  echo "───────────────────────────────────────────────"
  
  # Check if context exists
  if ! kubectl config get-contexts "$CTX" &>/dev/null; then
    echo "  ⚠️  Context '$CTX' not found, skipping..."
    return 0
  fi
  
  # Delete workload namespaces
  echo "→ Deleting workload namespaces..."
  force_delete namespace guestbook "" $CTX
  
  # Delete Agent
  echo "→ Deleting Agent..."
  kubectl delete -n argocd \
    -k "https://github.com/argoproj-labs/argocd-agent/install/kubernetes/agent?ref=${VERSION}" \
    --context $CTX --ignore-not-found=true 2>/dev/null || true
  
  # Delete ArgoCD
  echo "→ Deleting ArgoCD..."
  kubectl delete -n argocd \
    -k "https://github.com/argoproj-labs/argocd-agent/install/kubernetes/argo-cd/agent-managed?ref=${VERSION}" \
    --context $CTX --ignore-not-found=true 2>/dev/null || true
  
  # Delete secrets
  echo "→ Deleting secrets..."
  kubectl delete secret argocd-agent-ca argocd-agent-client-tls -n argocd --context $CTX --ignore-not-found=true 2>/dev/null || true
  
  # Delete namespace
  echo "→ Deleting argocd namespace..."
  force_delete namespace argocd "" $CTX
  
  # Delete CRDs
  echo "→ Deleting CRDs..."
  kubectl delete crd applications.argoproj.io applicationsets.argoproj.io appprojects.argoproj.io \
    --context $CTX --ignore-not-found=true 2>/dev/null || true
  
  echo "✓ Spoke $CTX cleaned"
}

clean_hub() {
  echo ""
  echo "───────────────────────────────────────────────"
  echo "  Cleaning Hub"
  echo "───────────────────────────────────────────────"
  
  # Delete applications in all agent namespaces
  echo "→ Deleting applications..."
  for ns in "${ALL_AGENTS[@]}"; do
    kubectl delete applications --all -n $ns --context $HUB_CTX 2>/dev/null || true
  done
  kubectl delete applications --all -n argocd --context $HUB_CTX 2>/dev/null || true
  
  # Delete cluster secrets
  echo "→ Deleting cluster secrets..."
  for agent in "${ALL_AGENTS[@]}"; do
    kubectl delete secret cluster-$agent -n argocd --context $HUB_CTX --ignore-not-found=true 2>/dev/null || true
  done
  
  # Delete agent namespaces
  echo "→ Deleting agent namespaces..."
  for ns in "${ALL_AGENTS[@]}"; do
    kubectl delete namespace $ns --context $HUB_CTX --ignore-not-found=true 2>/dev/null || true
  done
  
  # Delete Principal
  echo "→ Deleting Principal..."
  # Force delete LoadBalancer service first to prevent hang
  force_delete service argocd-agent-principal argocd $HUB_CTX
  
  kubectl delete -n argocd \
    -k "https://github.com/argoproj-labs/argocd-agent/install/kubernetes/principal?ref=${VERSION}" \
    --context $HUB_CTX --ignore-not-found=true 2>/dev/null || true
  
  # Delete ArgoCD
  echo "→ Deleting ArgoCD..."
  # Force delete LoadBalancer service
  force_delete service argocd-server argocd $HUB_CTX
  
  kubectl delete -n argocd \
    -k "https://github.com/argoproj-labs/argocd-agent/install/kubernetes/argo-cd/principal?ref=${VERSION}" \
    --context $HUB_CTX --ignore-not-found=true 2>/dev/null || true
  
  # Delete PKI secrets
  echo "→ Deleting PKI secrets..."
  kubectl delete secret argocd-agent-ca argocd-agent-principal-tls argocd-agent-resource-proxy-tls argocd-agent-jwt \
    -n argocd --context $HUB_CTX --ignore-not-found=true 2>/dev/null || true
  
  # Wait and delete namespace
  echo "→ Waiting for resources to terminate..."
  sleep 5
  
  # Delete namespace
  echo "→ Deleting argocd namespace..."
  force_delete namespace argocd "" $HUB_CTX
  
  # Delete CRDs
  echo "→ Deleting CRDs..."
  kubectl delete crd applications.argoproj.io applicationsets.argoproj.io appprojects.argoproj.io \
    --context $HUB_CTX --ignore-not-found=true 2>/dev/null || true
  
  echo "✓ Hub cleaned"
}

clean_terraform_artifacts() {
  echo ""
  echo "───────────────────────────────────────────────"
  echo "  Cleaning Terraform Artifacts"
  echo "───────────────────────────────────────────────"
  
  # Navigate to terraform directory if needed
  local TF_DIR="$(dirname "$0")/../terraform"
  
  if [ -d "$TF_DIR" ]; then
    echo "→ Removing terraform state files in $TF_DIR..."
    rm -f "$TF_DIR/terraform.tfstate" "$TF_DIR/terraform.tfstate.backup" "$TF_DIR/.terraform.lock.hcl"
    echo "    ✓ Cleaned state files"
    
    # Optional: remove .terraform directory to force re-init
    # rm -rf "$TF_DIR/.terraform"
  else
    echo "  ⚠️  Terraform directory not found at $TF_DIR"
  fi
}

delete_keycloak_realm() {
  echo ""
  echo "───────────────────────────────────────────────"
  echo "  Cleaning Keycloak Realm: $KC_REALM"
  echo "───────────────────────────────────────────────"

  if [ -z "$KC_URL" ] || [ -z "$KC_USER" ] || [ -z "$KC_PASSWORD" ]; then
    echo "  ⚠️  Keycloak credentials not set, skipping realm cleanup..."
    return 0
  fi

  echo "→ Authenticating with Keycloak..."
  TOKEN=$(curl -s -d "client_id=admin-cli" \
                  -d "username=$KC_USER" \
                  -d "password=$KC_PASSWORD" \
                  -d "grant_type=password" \
                  "$KC_URL/realms/master/protocol/openid-connect/token" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)

  if [ -z "$TOKEN" ]; then
    echo "  ❌ Failed to get access token. Check credentials."
    return 1
  fi

  echo "→ Deleting realm '$KC_REALM'..."
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE \
    -H "Authorization: Bearer $TOKEN" \
    "$KC_URL/admin/realms/$KC_REALM")

  if [ "$HTTP_CODE" -eq 204 ]; then
    echo "  ✓ Realm deleted successfully."
  elif [ "$HTTP_CODE" -eq 404 ]; then
    echo "  ✓ Realm not found (already deleted)."
  else
    echo "  ⚠️  Failed to delete realm (HTTP $HTTP_CODE)."
  fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════════════════

# Keycloak Configuration (Match terraform.tfvars)
KC_URL=$(grep "keycloak_url" "$TF_VARS" | cut -d'"' -f2)
KC_USER=$(grep "keycloak_user" "$TF_VARS" | cut -d'"' -f2)
KC_PASSWORD=$(grep "keycloak_password" "$TF_VARS" | cut -d'"' -f2)
KC_REALM=$(grep "keycloak_realm" "$TF_VARS" | cut -d'"' -f2)

# Parse arguments
FORCE_MODE=false
TARGET="${1:-all}"

for arg in "$@"; do
  if [ "$arg" == "-f" ]; then
    FORCE_MODE=true
  fi
done

echo "══════════════════════════════════  ══════════════"
echo "  ArgoCD Agent Cleanup"
echo "════════════════════════════════════════════════"
echo ""
echo "Hub Context: $HUB_CTX"
echo "Spokes:      ${ALL_SPOKES[*]}"
echo "Agents:      ${ALL_AGENTS[*]}"
echo "Target:      $TARGET"
echo ""

# Show what will be cleaned
case "$TARGET" in
  all)
    echo "⚠️  Will clean: Hub + all spokes (${ALL_SPOKES[*]})"
    ;;
  hub)
    echo "⚠️  Will clean: Hub only"
    ;;
  spokes)
    echo "⚠️  Will clean: All spokes (${ALL_SPOKES[*]})"
    ;;
  *)
    # Check if target is one of the spokes
    IS_SPOKE=false
    for s in "${ALL_SPOKES[@]}"; do
      if [ "$TARGET" == "$s" ]; then
        IS_SPOKE=true
        break
      fi
    done

    if [ "$IS_SPOKE" == "true" ]; then
      echo "⚠️  Will clean: $TARGET only"
    else
      echo "❌ Unknown target: $TARGET"
      echo ""
      echo "Valid targets: all, hub, spokes, ${ALL_SPOKES[*]}"
      exit 1
    fi
    ;;
esac

echo ""

# Confirm
if [ "$FORCE_MODE" != "true" ]; then
  read -p "Continue? (yes/no): " confirm
  if [ "$confirm" != "yes" ]; then
    echo "Cancelled"
    exit 0
  fi
fi

# Execute cleanup based on target
case "$TARGET" in
  all)
    for spoke in "${ALL_SPOKES[@]}"; do
      clean_spoke "$spoke"
    done
    clean_hub
    clean_terraform_artifacts
    delete_keycloak_realm
    ;;
  hub)
    clean_hub
    clean_terraform_artifacts
    delete_keycloak_realm
    ;;
  spokes)
    for spoke in "${ALL_SPOKES[@]}"; do
      clean_spoke "$spoke"
    done
    ;;
  *)
    # We already validated it's a valid spoke in the previous case
    clean_spoke "$TARGET"
    ;;
esac

echo ""
echo "════════════════════════════════════════════════"
echo "  Cleanup Complete"
echo "════════════════════════════════════════════════"
echo ""
echo "To redeploy, run:"
echo "  ./01-hub-setup.sh"
echo "  ./02-hub-pki-principal.sh"
echo "  ./03-spoke-setup.sh <spoke> && ./04-agent-connect.sh <agent> <spoke>"
echo ""