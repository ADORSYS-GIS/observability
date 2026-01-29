#!/bin/bash
set -e

echo "=================================="
echo "Namespace Cleanup Script"
echo "=================================="
echo ""
echo "This script manually cleans up cert-manager and ingress-nginx namespaces"
echo "that were left behind after 'terraform destroy'."
echo ""

NAMESPACES=("cert-manager" "ingress-nginx")

for NAMESPACE in "${NAMESPACES[@]}"; do
  if kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    echo "[$NAMESPACE] Found namespace, cleaning up..."
    
    if [ "$NAMESPACE" = "cert-manager" ]; then
      echo "[$NAMESPACE] Deleting cert-manager CRDs..."
      kubectl delete crd certificaterequests.cert-manager.io --ignore-not-found=true --timeout=60s || true
      kubectl delete crd certificates.cert-manager.io --ignore-not-found=true --timeout=60s || true
      kubectl delete crd challenges.acme.cert-manager.io --ignore-not-found=true --timeout=60s || true
      kubectl delete crd clusterissuers.cert-manager.io --ignore-not-found=true --timeout=60s || true
      kubectl delete crd issuers.cert-manager.io --ignore-not-found=true --timeout=60s || true
      kubectl delete crd orders.acme.cert-manager.io --ignore-not-found=true --timeout=60s || true
    fi
    
    echo "[$NAMESPACE] Deleting namespace..."
    kubectl delete namespace "$NAMESPACE" --timeout=120s || true
    
    echo "[$NAMESPACE] ✓ Cleanup completed"
  else
    echo "[$NAMESPACE] ✓ Namespace already deleted"
  fi
  echo ""
done

echo "=================================="
echo "✓ All namespaces cleaned up"
echo "=================================="
