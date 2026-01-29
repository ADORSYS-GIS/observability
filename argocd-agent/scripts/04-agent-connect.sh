#!/bin/bash
# Step 4: Connect Agent (Official Guide - Adding Agents)
# https://argocd-agent.readthedocs.io/latest/user-guide/adding-agents/
#
# Steps per official doc:
# 5.1 Create Agent Config on Hub
# 5.2 Issue Agent Client Certificate (Hub -> Spoke)
# 5.3 Propagate CA (Hub -> Spoke)
# 5.4 Verify Certs
# 5.5 Create Agent Namespace on Hub
# 5.6 Deploy Agent
# 5.7 Configure Agent Connection
#
# IDEMPOTENCY: This script is fully idempotent - safe to re-run.
# It will delete and recreate all secrets/certs to ensure clean state.

set -e

# Configuration
HUB_CTX="${HUB_CTX:-}"
AGENT_NAME="${1:-}"
SPOKE_CTX="${2:-}"
VERSION="${VERSION:-v0.5.3}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Usage
if [ -z "$HUB_CTX" ] || [ -z "$AGENT_NAME" ] || [ -z "$SPOKE_CTX" ]; then
  echo "Usage: HUB_CTX=<hub-context> $0 <agent-name> <spoke-context>"
  echo ""
  echo "Example:"
  echo "  HUB_CTX=gke_proj_region_hub $0 agent-1 gke_proj_region_spoke1"
  echo ""
  echo "Environment variables:"
  echo "  HUB_CTX    - Hub cluster kubectl context (required)"
  echo "  VERSION    - ArgoCD version (default: v0.5.3)"
  echo ""
  echo "Available contexts:"
  kubectl config get-contexts -o name
  exit 1
fi

echo "════════════════════════════════════════════════"
echo "  Step 4: Connect Agent ($AGENT_NAME -> $SPOKE_CTX)"
echo "════════════════════════════════════════════════"
echo ""

# Check for argocd-agentctl
if [ ! -f "$SCRIPT_DIR/argocd-agentctl" ]; then
  echo "✗ argocd-agentctl not found in $SCRIPT_DIR"
  echo "  Download from: https://github.com/argoproj-labs/argocd-agent/releases"
  exit 1
fi

# Get Principal IP automatically
PRINCIPAL_IP=$(kubectl get svc argocd-agent-principal -n argocd \
  --context $HUB_CTX -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
if [ -z "$PRINCIPAL_IP" ]; then
  echo "✗ Could not find Principal IP. Is it installed?"
  exit 1
fi
echo "→ Using Principal IP: $PRINCIPAL_IP"

# Get Principal service port
SVC_PORT=$(kubectl get svc argocd-agent-principal -n argocd --context $HUB_CTX \
  -o jsonpath='{.spec.ports[0].port}')
echo "→ Using Principal Port: $SVC_PORT"

# ═══════════════════════════════════════════════════════════════════════════════
# 5.1 Create Agent Configuration (on Hub)
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "→ [5.1] Creating Agent Configuration on Hub..."
# Delete existing agent cluster secret for idempotency
kubectl delete secret cluster-$AGENT_NAME -n argocd --context $HUB_CTX --ignore-not-found=true

$SCRIPT_DIR/argocd-agentctl agent create $AGENT_NAME \
  --principal-context $HUB_CTX \
  --principal-namespace argocd \
  --resource-proxy-server argocd-agent-resource-proxy.argocd.svc.cluster.local:9090

# ═══════════════════════════════════════════════════════════════════════════════
# Update Principal's allowed-namespaces to include this agent
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "→ Updating Principal allowed-namespaces to include '$AGENT_NAME'..."
CURRENT_NS=$(kubectl get configmap argocd-agent-params -n argocd --context $HUB_CTX \
  -o jsonpath='{.data.principal\.allowed-namespaces}' 2>/dev/null || echo "")

if [ -z "$CURRENT_NS" ]; then
  NEW_NS="$AGENT_NAME"
elif [[ "$CURRENT_NS" != *"$AGENT_NAME"* ]]; then
  NEW_NS="$CURRENT_NS,$AGENT_NAME"
else
  NEW_NS="$CURRENT_NS"
fi

kubectl patch configmap argocd-agent-params -n argocd --context $HUB_CTX \
  --type='merge' \
  --patch "{\"data\":{\"principal.allowed-namespaces\":\"$NEW_NS\"}}"

# Restart Principal to pick up new allowed-namespace
echo "→ Restarting Principal to recognize new agent namespace..."
kubectl rollout restart deployment argocd-agent-principal -n argocd --context $HUB_CTX
kubectl wait --for=condition=available --timeout=120s \
  deployment/argocd-agent-principal -n argocd --context $HUB_CTX

# ═══════════════════════════════════════════════════════════════════════════════
# 5.2 Issue Agent Client Certificate (CRITICAL: Delete old cert first!)
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "→ [5.2] Issuing Agent Client Certificate..."
# Delete existing client TLS secret for idempotency (ensures fresh cert)
kubectl delete secret argocd-agent-client-tls -n argocd --context $SPOKE_CTX --ignore-not-found=true

$SCRIPT_DIR/argocd-agentctl pki issue agent $AGENT_NAME \
  --principal-context $HUB_CTX \
  --agent-context $SPOKE_CTX \
  --agent-namespace argocd \
  --upsert

# ═══════════════════════════════════════════════════════════════════════════════
# 5.3 Propagate CA (CRITICAL: Must match Hub's current CA!)
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "→ [5.3] Propagating CA to Spoke..."
# Delete existing CA secret for idempotency (argocd-agentctl doesn't have --upsert for propagate)
kubectl delete secret argocd-agent-ca -n argocd --context $SPOKE_CTX --ignore-not-found=true

$SCRIPT_DIR/argocd-agentctl pki propagate \
  --principal-context $HUB_CTX \
  --principal-namespace argocd \
  --agent-context $SPOKE_CTX \
  --agent-namespace argocd

# ═══════════════════════════════════════════════════════════════════════════════
# 5.4 Verify Certificates
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "→ [5.4] Verifying certificates on Spoke..."
kubectl get secret argocd-agent-client-tls -n argocd --context $SPOKE_CTX >/dev/null
kubectl get secret argocd-agent-ca -n argocd --context $SPOKE_CTX >/dev/null
echo "  ✓ Certificates verified"

# ═══════════════════════════════════════════════════════════════════════════════
# 5.5 Create Agent Namespace on Hub (for managed agents)
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "→ [5.5] Creating Agent Namespace '$AGENT_NAME' on Hub..."
kubectl create namespace $AGENT_NAME --context $HUB_CTX --dry-run=client -o yaml | \
  kubectl apply --context $HUB_CTX -f -

# ═══════════════════════════════════════════════════════════════════════════════
# 5.6 Deploy Agent
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "→ [5.6] Deploying Agent on Spoke ref=${VERSION}..."
kubectl apply -n argocd \
  -k "https://github.com/argoproj-labs/argocd-agent/install/kubernetes/agent?ref=${VERSION}" \
  --context $SPOKE_CTX

# ═══════════════════════════════════════════════════════════════════════════════
# 5.7 Configure Agent Connection
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "→ [5.7] Configuring Agent Connection..."
kubectl patch configmap argocd-agent-params -n argocd --context $SPOKE_CTX \
  --type='merge' \
  --patch "{\"data\":{
    \"agent.server.address\":\"$PRINCIPAL_IP\",
    \"agent.server.port\":\"$SVC_PORT\",
    \"agent.mode\":\"managed\",
    \"agent.creds\":\"mtls:^CN=(.+)$\",
    \"agent.tls.client.insecure\":\"false\",
    \"agent.tls.secret-name\":\"argocd-agent-client-tls\",
    \"agent.tls.root-ca-secret-name\":\"argocd-agent-ca\",
    \"agent.log.level\":\"info\"
  }}"

# ═══════════════════════════════════════════════════════════════════════════════
# Force Restart Agent (CRITICAL: Delete pod to ensure fresh start with new certs)
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "→ Force restarting Agent (deleting pod for fresh start with new certs)..."
kubectl delete pod -l app.kubernetes.io/name=argocd-agent-agent -n argocd --context $SPOKE_CTX --ignore-not-found=true
kubectl wait --for=condition=available --timeout=300s \
  deployment/argocd-agent-agent -n argocd --context $SPOKE_CTX

echo ""
echo "════════════════════════════════════════════════"
echo "  Step 4 Complete. Agent '$AGENT_NAME' Connected."
echo "════════════════════════════════════════════════"
echo ""
echo "Verify with: ./05-verify.sh $AGENT_NAME $SPOKE_CTX"
