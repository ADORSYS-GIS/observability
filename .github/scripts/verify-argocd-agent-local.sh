#!/bin/bash
set -e

# =============================================================================
# ArgoCD Agent Verification Script (Local Machine)
# =============================================================================
# This script verifies the ArgoCD Agent deployment on your local machine
# Run this after the GitHub workflow completes to check the deployment
# =============================================================================

echo "═══════════════════════════════════════════════════════════════"
echo "ArgoCD Agent Deployment Verification (Local)"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Configuration
HUB_CONTEXT="gke_observe-472521_europe-west3_observe-prod-cluster"
NAMESPACE="argocd"
SPOKE_CONTEXTS=("spoke-1" "spoke-2" "spoke-3" "spoke-4")

# Get current context
CURRENT_CONTEXT=$(kubectl config current-context)
echo "✓ Current kubectl context: $CURRENT_CONTEXT"
echo ""

# ================================================================
# 1. VERIFY HUB CLUSTER (PRINCIPAL) DEPLOYMENT
# ================================================================
echo "[1/5] Verifying Principal (Hub) Deployment..."
echo "───────────────────────────────────────────────────────────────"

# Switch to hub context
kubectl config use-context "$HUB_CONTEXT"

# Check principal pods
echo "Checking principal pods..."
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=argocd-agent-principal

PRINCIPAL_READY=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=argocd-agent-principal -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
if [[ "$PRINCIPAL_READY" == *"True"* ]]; then
  echo "✓ Principal pod is running and ready"
else
  echo "✗ ERROR: Principal pod is not ready"
  kubectl describe pods -n $NAMESPACE -l app.kubernetes.io/name=argocd-agent-principal
  exit 1
fi

# Check principal service
echo ""
echo "Checking principal service..."
kubectl get svc -n $NAMESPACE argocd-agent-principal

PRINCIPAL_IP=$(kubectl get svc -n $NAMESPACE argocd-agent-principal -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
PRINCIPAL_PORT=$(kubectl get svc -n $NAMESPACE argocd-agent-principal -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "443")
if [ -z "$PRINCIPAL_IP" ] || [ "$PRINCIPAL_IP" = "null" ]; then
  echo "⚠ WARNING: Principal LoadBalancer IP not yet assigned"
  PRINCIPAL_IP="pending"
else
  echo "✓ Principal LoadBalancer IP: $PRINCIPAL_IP:$PRINCIPAL_PORT"
fi

# Check principal logs
echo ""
echo "Recent principal logs:"
kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=argocd-agent-principal --tail=20 || echo "⚠ Could not fetch logs"
echo ""

# ================================================================
# 2. VERIFY ARGOCD SERVER
# ================================================================
echo "[2/5] Verifying ArgoCD Server..."
echo "───────────────────────────────────────────────────────────────"

kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=argocd-server
echo ""

# ================================================================
# 3. VERIFY SPOKE AGENT DEPLOYMENTS
# ================================================================
echo "[3/5] Verifying Spoke Agent Deployments..."
echo "───────────────────────────────────────────────────────────────"

for SPOKE_CONTEXT in "${SPOKE_CONTEXTS[@]}"; do
  echo ""
  echo "Checking context: $SPOKE_CONTEXT"
  
  # Check if context exists
  if ! kubectl config get-contexts "$SPOKE_CONTEXT" &>/dev/null; then
    echo "  ⚠ WARNING: Context '$SPOKE_CONTEXT' not found in kubeconfig"
    continue
  fi
  
  # Switch to spoke context
  kubectl config use-context "$SPOKE_CONTEXT"
  
  # Check if namespace exists
  if ! kubectl get namespace $NAMESPACE &>/dev/null; then
    echo "  ✗ Namespace '$NAMESPACE' does not exist"
    echo "  This indicates spoke agent was NOT deployed"
    continue
  fi
  
  # Check agent deployment
  if kubectl get deployment argocd-agent-agent -n $NAMESPACE &>/dev/null; then
    AGENT_READY=$(kubectl get deployment argocd-agent-agent -n $NAMESPACE -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || echo "")
    if [ "$AGENT_READY" = "True" ]; then
      echo "  ✓ Agent deployment is ready"
      
      # Show agent pods
      kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=argocd-agent-agent
      
      # Check agent logs for connection status
      echo "  Recent agent logs:"
      kubectl logs -l app.kubernetes.io/name=argocd-agent-agent -n $NAMESPACE --tail=10 2>/dev/null | sed 's/^/    /' || echo "    ⚠ Could not fetch logs"
    else
      echo "  ✗ Agent deployment exists but is not ready"
      kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=argocd-agent-agent
    fi
  else
    echo "  ✗ Agent deployment not found"
    echo "  This indicates spoke agent was NOT deployed by Terraform"
  fi
done

# Switch back to hub context
kubectl config use-context "$HUB_CONTEXT"
echo ""

# ================================================================
# 4. VERIFY AGENT REGISTRATION ON HUB
# ================================================================
echo "[4/5] Verifying Agent Registration on Hub..."
echo "───────────────────────────────────────────────────────────────"

# Check if agent CRD exists
if kubectl get crd agents.argoproj.io &>/dev/null; then
  echo "✓ Agent CRD exists"
  
  # List registered agents
  echo ""
  echo "Registered agents:"
  if kubectl get agents -n $NAMESPACE &>/dev/null; then
    kubectl get agents -n $NAMESPACE
    
    AGENT_COUNT=$(kubectl get agents -n $NAMESPACE --no-headers 2>/dev/null | wc -l)
    echo ""
    echo "✓ Found $AGENT_COUNT registered agent(s)"
    
    # Show agent details
    if [ "$AGENT_COUNT" -gt 0 ]; then
      echo ""
      echo "Agent details:"
      kubectl get agents -n $NAMESPACE -o yaml
    fi
  else
    echo "⚠ No agents registered yet"
    echo "This is normal if spokes haven't connected to principal yet"
  fi
else
  echo "⚠ Agent CRD not found"
  echo "This may indicate ArgoCD Agent is not fully installed"
fi
echo ""

# ================================================================
# 5. VERIFY CERTIFICATES AND SECRETS
# ================================================================
echo "[5/5] Verifying Certificates and Secrets..."
echo "───────────────────────────────────────────────────────────────"

# Check hub certificates
echo "Hub cluster certificates:"
kubectl get secrets -n $NAMESPACE | grep -E "argocd-agent-ca|argocd-agent-server-tls" || echo "  ⚠ No agent certificates found on hub"

echo ""
echo "Spoke cluster certificates:"
for SPOKE_CONTEXT in "${SPOKE_CONTEXTS[@]}"; do
  if ! kubectl config get-contexts "$SPOKE_CONTEXT" &>/dev/null; then
    continue
  fi
  
  kubectl config use-context "$SPOKE_CONTEXT"
  
  if kubectl get namespace $NAMESPACE &>/dev/null; then
    echo "  $SPOKE_CONTEXT:"
    kubectl get secrets -n $NAMESPACE 2>/dev/null | grep -E "argocd-agent-ca|argocd-agent-client-tls" | sed 's/^/    /' || echo "    ⚠ No agent certificates found"
  fi
done

# Switch back to hub context
kubectl config use-context "$HUB_CONTEXT"
echo ""

# ================================================================
# SUMMARY
# ================================================================
echo "═══════════════════════════════════════════════════════════════"
echo "Verification Summary"
echo "═══════════════════════════════════════════════════════════════"
echo "✓ Principal pod status: $PRINCIPAL_READY"
echo "✓ Principal LoadBalancer IP: $PRINCIPAL_IP"
echo ""
echo "Spoke agents checked: ${#SPOKE_CONTEXTS[@]}"
echo "Check the output above for individual spoke status"
echo ""
echo "Next steps:"
if [ "$PRINCIPAL_IP" = "pending" ]; then
  echo "  1. Wait for Principal LoadBalancer IP to be assigned"
  echo "  2. Re-run GitHub workflow to update spoke configurations"
elif kubectl get agents -n $NAMESPACE &>/dev/null && [ "$(kubectl get agents -n $NAMESPACE --no-headers 2>/dev/null | wc -l)" -gt 0 ]; then
  echo "  ✓ Agents are registered and connected!"
  echo "  1. Deploy test application:"
  echo "     kubectl apply -f argocd-agent/applications/guestbook.yaml"
  echo "  2. Monitor application:"
  echo "     kubectl get application guestbook-agent-2 -n argocd -w"
else
  echo "  1. Check spoke agent logs for connection issues"
  echo "  2. Verify principal IP is reachable from spoke clusters"
  echo "  3. Check certificates are properly propagated"
fi
echo "═══════════════════════════════════════════════════════════════"
