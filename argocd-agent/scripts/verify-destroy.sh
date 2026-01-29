#!/bin/bash
set -e

#===================================================================
# Terraform Destroy Verification Script
#===================================================================
# This script verifies that 'terraform destroy' properly cleans up
# all resources created by the ArgoCD Agent deployment.
#
# Usage:
#   1. Run terraform destroy: terraform destroy -auto-approve
#   2. Run this script: ./scripts/verify-destroy.sh
#===================================================================

echo "=========================================="
echo "Terraform Destroy Verification"
echo "=========================================="
echo ""

HUB_CONTEXT="${HUB_CONTEXT:-gke_observe-472521_europe-west3_observe-prod-cluster}"
PROJECT_ID="${PROJECT_ID:-observe-472521}"
REGION="${REGION:-europe-west3}"

ERRORS=0

#===================================================================
# Function to check if resource exists
#===================================================================
check_resource_deleted() {
  local resource_type=$1
  local resource_name=$2
  local namespace=$3
  local context=$4
  
  if [ -n "$namespace" ]; then
    kubectl get "$resource_type" "$resource_name" -n "$namespace" --context "$context" &>/dev/null
  else
    kubectl get "$resource_type" "$resource_name" --context "$context" &>/dev/null
  fi
  
  if [ $? -eq 0 ]; then
    echo "✗ FAIL: $resource_type/$resource_name still exists"
    ((ERRORS++))
    return 1
  else
    echo "✓ PASS: $resource_type/$resource_name deleted"
    return 0
  fi
}

#===================================================================
# 1. Check Namespaces
#===================================================================
echo "[1/6] Verifying namespace cleanup..."
echo ""

NAMESPACES=("argocd" "agent-1" "agent-2" "agent-3" "cert-manager" "ingress-nginx")

for NS in "${NAMESPACES[@]}"; do
  if kubectl get namespace "$NS" --context "$HUB_CONTEXT" &>/dev/null; then
    echo "✗ FAIL: Namespace $NS still exists"
    ((ERRORS++))
  else
    echo "✓ PASS: Namespace $NS deleted"
  fi
done

echo ""

#===================================================================
# 2. Check Helm Releases
#===================================================================
echo "[2/6] Verifying Helm release cleanup..."
echo ""

HELM_RELEASES=("cert-manager" "nginx-ingress")

for RELEASE in "${HELM_RELEASES[@]}"; do
  if helm list --all-namespaces --kube-context "$HUB_CONTEXT" | grep -q "$RELEASE"; then
    echo "✗ FAIL: Helm release $RELEASE still exists"
    ((ERRORS++))
  else
    echo "✓ PASS: Helm release $RELEASE uninstalled"
  fi
done

echo ""

#===================================================================
# 3. Check cert-manager CRDs
#===================================================================
echo "[3/6] Verifying cert-manager CRD cleanup..."
echo ""

CRDS=(
  "certificaterequests.cert-manager.io"
  "certificates.cert-manager.io"
  "challenges.acme.cert-manager.io"
  "clusterissuers.cert-manager.io"
  "issuers.cert-manager.io"
  "orders.acme.cert-manager.io"
)

for CRD in "${CRDS[@]}"; do
  if kubectl get crd "$CRD" --context "$HUB_CONTEXT" &>/dev/null; then
    echo "✗ FAIL: CRD $CRD still exists"
    ((ERRORS++))
  else
    echo "✓ PASS: CRD $CRD deleted"
  fi
done

echo ""

#===================================================================
# 4. Check GCP LoadBalancers
#===================================================================
echo "[4/6] Verifying GCP LoadBalancer cleanup..."
echo ""

# Check for orphaned forwarding rules (32-char hex names like aa92b15706d624ec0a4c8d001e31f874)
ORPHANED_FW=$(gcloud compute forwarding-rules list \
  --project="$PROJECT_ID" \
  --regions="$REGION" \
  --format="value(name)" \
  --filter="name~'^a[a-f0-9]{31}$'" 2>/dev/null || true)

if [ -z "$ORPHANED_FW" ]; then
  echo "✓ PASS: No orphaned GCP forwarding rules"
else
  echo "✗ FAIL: Found orphaned forwarding rules:"
  echo "$ORPHANED_FW"
  ((ERRORS++))
fi

# Check for orphaned target pools
ORPHANED_TP=$(gcloud compute target-pools list \
  --project="$PROJECT_ID" \
  --regions="$REGION" \
  --format="value(name)" \
  --filter="name~'^a[a-f0-9]{31}$'" 2>/dev/null || true)

if [ -z "$ORPHANED_TP" ]; then
  echo "✓ PASS: No orphaned GCP target pools"
else
  echo "✗ FAIL: Found orphaned target pools:"
  echo "$ORPHANED_TP"
  ((ERRORS++))
fi

echo ""

#===================================================================
# 5. Check Keycloak Resources (if applicable)
#===================================================================
echo "[5/6] Verifying Keycloak resource cleanup..."
echo ""

# Note: Keycloak resources are managed by Terraform's Keycloak provider
# and should be automatically deleted. This is informational only.
echo "ℹ  INFO: Keycloak resources (realm, clients, users) are managed by Terraform provider"
echo "ℹ  INFO: Verify in Keycloak console at: ${KEYCLOAK_URL:-https://keycloak-dev.observe.camer.digital}"
echo "   - Realm 'argocd' should be deleted"
echo ""

#===================================================================
# 6. Check ArgoCD Agent Resources
#===================================================================
echo "[6/6] Verifying ArgoCD Agent resource cleanup..."
echo ""

# These should be deleted with the namespaces
AGENT_RESOURCES=(
  "secret/cluster-agent-1:argocd"
  "secret/cluster-agent-2:argocd"
  "secret/cluster-agent-3:argocd"
)

for RESOURCE in "${AGENT_RESOURCES[@]}"; do
  IFS=':' read -r res ns <<< "$RESOURCE"
  if kubectl get "$res" -n "$ns" --context "$HUB_CONTEXT" &>/dev/null; then
    echo "✗ FAIL: $res in namespace $ns still exists"
    ((ERRORS++))
  else
    echo "✓ PASS: $res in namespace $ns deleted"
  fi
done

echo ""

#===================================================================
# Summary
#===================================================================
echo "=========================================="
if [ $ERRORS -eq 0 ]; then
  echo "✓ ALL CHECKS PASSED"
  echo "=========================================="
  echo ""
  echo "All resources have been properly cleaned up by terraform destroy."
  exit 0
else
  echo "✗ $ERRORS CHECK(S) FAILED"
  echo "=========================================="
  echo ""
  echo "Some resources were not properly cleaned up."
  echo ""
  echo "To clean up manually:"
  echo "1. Run cleanup scripts:"
  echo "   ./scripts/cleanup-namespaces.sh"
  echo "   ./scripts/cleanup-gcp-lb.sh"
  echo ""
  echo "2. Or manually delete resources using kubectl/gcloud"
  exit 1
fi
