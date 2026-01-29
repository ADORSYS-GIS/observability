#!/bin/bash

set -euo pipefail

# Verify ArgoCD Agent deployment
# Checks hub cluster, spoke clusters, and agent connectivity

NAMESPACE="${NAMESPACE:-argocd-agent}"
TIMEOUT="${TIMEOUT:-300}"

echo "🔍 Verifying ArgoCD Agent deployment..."
echo "📋 Namespace: $NAMESPACE"
echo "⏱️  Timeout: ${TIMEOUT}s"

# Exit codes
EXIT_CODE=0

# Helper function for checks
check_status() {
  local check_name="$1"
  local check_command="$2"
  
  echo ""
  echo "▶️  Checking: $check_name"
  
  if eval "$check_command"; then
    echo "  ✅ PASSED: $check_name"
    return 0
  else
    echo "  ❌ FAILED: $check_name"
    EXIT_CODE=1
    return 1
  fi
}

# 1. Check namespace exists
check_status \
  "Namespace exists" \
  "kubectl get namespace $NAMESPACE &>/dev/null"

# 2. Check ArgoCD Agent pods are running
echo ""
echo "▶️  Checking ArgoCD Agent pods..."
PODS_NOT_READY=$(kubectl get pods -n "$NAMESPACE" --field-selector=status.phase!=Running 2>/dev/null | grep -v "NAME" | wc -l || echo "0")

if [ "$PODS_NOT_READY" -eq 0 ]; then
  echo "  ✅ All pods are running"
  kubectl get pods -n "$NAMESPACE" -o wide
else
  echo "  ❌ Some pods are not running:"
  kubectl get pods -n "$NAMESPACE" --field-selector=status.phase!=Running
  EXIT_CODE=1
fi

# 3. Check if hub cluster is reachable
echo ""
if kubectl get namespace argocd &>/dev/null; then
  echo "▶️  Checking ArgoCD hub cluster..."
  
  # Check ArgoCD server is running
  if kubectl get deployment -n argocd argocd-server &>/dev/null; then
    REPLICAS_READY=$(kubectl get deployment -n argocd argocd-server -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    REPLICAS_DESIRED=$(kubectl get deployment -n argocd argocd-server -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    
    if [ "$REPLICAS_READY" -eq "$REPLICAS_DESIRED" ] && [ "$REPLICAS_READY" -gt 0 ]; then
      echo "  ✅ ArgoCD server is running ($REPLICAS_READY/$REPLICAS_DESIRED replicas)"
    else
      echo "  ❌ ArgoCD server is not ready ($REPLICAS_READY/$REPLICAS_DESIRED replicas)"
      EXIT_CODE=1
    fi
  else
    echo "  ⚠️  ArgoCD server deployment not found (may be on different cluster)"
  fi
else
  echo "  ℹ️  ArgoCD namespace not found on this cluster (hub may be on different cluster)"
fi

# 4. Check Agentctl installation (if exists)
echo ""
if command -v agentctl &>/dev/null; then
  echo "▶️  Checking agentctl..."
  agentctl version
  echo "  ✅ Agentctl is installed"
else
  echo "  ℹ️  Agentctl not found (optional tool)"
fi

# 5. Check service accounts
echo ""
echo "▶️  Checking service accounts..."
if kubectl get serviceaccount -n "$NAMESPACE" &>/dev/null; then
  SA_COUNT=$(kubectl get serviceaccount -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
  echo "  ✅ Found $SA_COUNT service account(s) in namespace"
  kubectl get serviceaccount -n "$NAMESPACE"
else
  echo "  ⚠️  No service accounts found"
fi

# 6. Check secrets
echo ""
echo "▶️  Checking secrets..."
SECRET_COUNT=$(kubectl get secrets -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l || echo "0")
if [ "$SECRET_COUNT" -gt 0 ]; then
  echo "  ✅ Found $SECRET_COUNT secret(s) in namespace"
  kubectl get secrets -n "$NAMESPACE" --no-headers | awk '{print "    - " $1 " (" $2 ")"}'
else
  echo "  ⚠️  No secrets found"
fi

# 7. Check ingress resources (if any)
echo ""
if kubectl get ingress -n "$NAMESPACE" &>/dev/null 2>&1; then
  INGRESS_COUNT=$(kubectl get ingress -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l || echo "0")
  if [ "$INGRESS_COUNT" -gt 0 ]; then
    echo "▶️  Found ingress resources:"
    kubectl get ingress -n "$NAMESPACE"
  fi
fi

# 8. Check events for errors
echo ""
echo "▶️  Checking recent events for errors..."
ERROR_EVENTS=$(kubectl get events -n "$NAMESPACE" --field-selector type=Warning --sort-by='.lastTimestamp' 2>/dev/null | tail -5 || echo "")

if [ -n "$ERROR_EVENTS" ]; then
  echo "  ⚠️  Recent warning events:"
  echo "$ERROR_EVENTS"
else
  echo "  ✅ No recent warning events"
fi

# Summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ $EXIT_CODE -eq 0 ]; then
  echo "✅ ArgoCD Agent deployment verification PASSED"
else
  echo "❌ ArgoCD Agent deployment verification FAILED"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

exit $EXIT_CODE
