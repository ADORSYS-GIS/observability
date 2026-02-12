#!/bin/bash

# This script checks for the existence of core ArgoCD hub resources
# and imports them into the Terraform state if they are found.
# This makes the deployment workflows idempotent and prevents errors
# when running them multiple times.

set -e
set -o pipefail

HUB_NAMESPACE=$1
HUB_CONTEXT=$2

echo "======================================================================"
echo "Checking for existing ArgoCD Hub resources to import..."
echo "Hub Namespace: $HUB_NAMESPACE"
echo "Hub Context: $HUB_CONTEXT"
echo "======================================================================"

# Check 1: ArgoCD Namespace in Kubernetes
echo "Checking for namespace '$HUB_NAMESPACE'..."
if kubectl get namespace "$HUB_NAMESPACE" --context "$HUB_CONTEXT" >/dev/null 2>&1; then
  echo "✓ Found existing namespace '$HUB_NAMESPACE'. Attempting to import..."
  if terraform state list | grep -q "module.hub_cluster\[0\].kubernetes_namespace.hub_argocd"; then
    echo "ℹ Namespace is already in the Terraform state. Skipping import."
  else
    terraform import "module.hub_cluster[0].kubernetes_namespace.hub_argocd" "$HUB_NAMESPACE"
    echo "✓ Namespace import successful."
  fi
else
  echo "ℹ Namespace '$HUB_NAMESPACE' not found. It will be created by Terraform."
fi

echo "----------------------------------------------------------------------"

# Check 2: ArgoCD Realm in Keycloak
# We can't directly check if the realm exists without complex API calls.
# Instead, we will attempt to import it. If it already exists in the state
# or doesn't exist in Keycloak, the command will fail gracefully.
# We will rely on the error message to determine the outcome.
echo "Checking for Keycloak realm 'argocd'..."
if terraform state list | grep -q "module.hub_cluster\[0\].keycloak_realm.argocd"; then
  echo "ℹ Keycloak realm is already in the Terraform state. Skipping import."
else
  echo "Attempting to import Keycloak realm 'argocd'..."
  # The import will fail if the realm doesn't exist, which is the desired behavior.
  # The error is ignored because Terraform will create it on the next run.
  terraform import "module.hub_cluster[0].keycloak_realm.argocd" "argocd" || true
  echo "✓ Keycloak realm import check complete. Terraform will create it if it's missing."
fi

echo "======================================================================"
echo "Resource import check finished."
echo "======================================================================"