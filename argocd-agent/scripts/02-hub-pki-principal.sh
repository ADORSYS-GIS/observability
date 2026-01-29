#!/bin/bash
# Step 2: PKI & Principal Setup (Official Guide)
# 2.1 Init CA
# 2.2 Issue Principal Certs
# 2.3 Create JWT Key
# 3.1 Deploy Principal
# 3.2 Expose Principal Service

set -e

# Configuration
HUB_CTX="${HUB_CTX:-}"
VERSION="${VERSION:-v0.5.3}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INITIAL_ALLOWED_NAMESPACES="${1:-agent-1}"

# Usage
if [ -z "$HUB_CTX" ]; then
  echo "Usage: HUB_CTX=<context> [VERSION=v0.5.3] $0 [allowed-namespaces]"
  echo ""
  echo "Example:"
  echo "  HUB_CTX=gke_project_region_hub $0 agent-1,agent-2"
  echo ""
  echo "Available contexts:"
  kubectl config get-contexts -o name
  exit 1
fi

echo "════════════════════════════════════════════════"
echo "  Step 2: PKI & Principal Setup"
echo "════════════════════════════════════════════════"
echo ""

# Check for argocd-agentctl
if [ ! -f "$SCRIPT_DIR/argocd-agentctl" ]; then
  echo "✗ argocd-agentctl not found in $SCRIPT_DIR"
  echo "  Download from: https://github.com/argoproj-labs/argocd-agent/releases"
  exit 1
fi

# 2.1 Initialize CA
echo "→ Initializing PKI..."
$SCRIPT_DIR/argocd-agentctl pki init \
  --principal-context $HUB_CTX \
  --principal-namespace argocd

# 3.1 Deploy Principal (Install first to expose and get IP for certs)
echo "→ Installing Principal ref=${VERSION}..."
kubectl apply -n argocd \
  -k "https://github.com/argoproj-labs/argocd-agent/install/kubernetes/principal?ref=${VERSION}" \
  --context $HUB_CTX

# Patch: Allow Principal to access Redis (Hub NetworkPolicy blocks it by default)
echo "→ Patching Hub Redis NetworkPolicy to allow Principal..."
kubectl patch netpol argocd-redis-network-policy -n argocd --context $HUB_CTX \
  --type='json' \
  -p='[{"op": "add", "path": "/spec/ingress/0/from/-", "value": {"podSelector": {"matchLabels": {"app.kubernetes.io/name": "argocd-agent-principal"}}}}]' \
  2>/dev/null || echo "  (NetPol already patched or doesn't exist)"

# 3.2 Expose Principal Service (LoadBalancer)
echo "→ Exposing Principal Service via LoadBalancer..."
kubectl patch svc argocd-agent-principal -n argocd --context $HUB_CTX \
  --patch '{"spec":{"type":"LoadBalancer"}}'

echo "→ Waiting for Principal External IP..."
PRINCIPAL_IP=""
while [ -z "$PRINCIPAL_IP" ]; do
  echo "  Waiting for IP..."
  sleep 5
  PRINCIPAL_IP=$(kubectl get svc argocd-agent-principal -n argocd --context $HUB_CTX \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
done
echo "✓ Principal IP: $PRINCIPAL_IP"

# 2.2 Issue Principal Certificates
echo "→ Issuing Principal Certificates..."
# Issue gRPC server certificate (agents connect to this)
$SCRIPT_DIR/argocd-agentctl pki issue principal \
  --principal-context $HUB_CTX \
  --principal-namespace argocd \
  --ip "127.0.0.1,$PRINCIPAL_IP" \
  --dns "localhost,argocd-agent-principal.argocd.svc.cluster.local" \
  --upsert

# Issue resource proxy certificate (Argo CD connects to this)
$SCRIPT_DIR/argocd-agentctl pki issue resource-proxy \
  --principal-context $HUB_CTX \
  --principal-namespace argocd \
  --ip "127.0.0.1" \
  --dns "localhost,argocd-agent-resource-proxy.argocd.svc.cluster.local" \
  --upsert

# 2.3 Create JWT Signing Key
echo "→ Creating JWT Signing Key..."
$SCRIPT_DIR/argocd-agentctl jwt create-key \
  --principal-context $HUB_CTX \
  --principal-namespace argocd \
  --upsert

# Configure Principal (Allow Agent Namespaces)
echo "→ Configuring Principal (allowed-namespaces: $INITIAL_ALLOWED_NAMESPACES)..."
kubectl patch configmap argocd-agent-params -n argocd --context $HUB_CTX \
  --type='merge' \
  --patch "{\"data\":{\"principal.allowed-namespaces\":\"$INITIAL_ALLOWED_NAMESPACES\"}}"

# Restart Principal to apply all changes
echo "→ Restarting Principal..."
kubectl rollout restart deployment argocd-agent-principal -n argocd --context $HUB_CTX
kubectl wait --for=condition=available --timeout=300s \
  deployment/argocd-agent-principal -n argocd --context $HUB_CTX

echo ""
echo "Step 2 Complete. Principal Ready at $PRINCIPAL_IP"
echo "IMPORTANT: Save this IP for agent configuration."
