#!/bin/bash
# Step 3: Workload Cluster Setup (Official Guide)
# 4.1 Mode: Managed (implied by script selection)
# 4.2 Create Namespace
# 4.3 Install Argo CD (Agent-Managed Profile)

set -e

# Configuration
SPOKE_CTX="${1:-}"
VERSION="${VERSION:-v0.5.3}"

# Usage
if [ -z "$SPOKE_CTX" ]; then
  echo "Usage: [VERSION=v0.5.3] $0 <spoke-context>"
  echo ""
  echo "Example:"
  echo "  $0 gke_project_region_spoke1"
  echo "  VERSION=v0.5.4 $0 gke_project_region_spoke1"
  echo ""
  echo "Available contexts:"
  kubectl config get-contexts -o name
  exit 1
fi

echo "════════════════════════════════════════════════"
echo "  Step 3: Workload Cluster Setup"
echo "════════════════════════════════════════════════"
echo ""

# 4.2 Create Namespace
echo "→ Creating namespace 'argocd' on Spoke..."
kubectl create namespace argocd --context $SPOKE_CTX --dry-run=client -o yaml | kubectl apply --context $SPOKE_CTX -f -

# 4.3 Install Argo CD (Agent-Managed Profile)
echo "→ Installing Argo CD (Agent-Managed Profile) ref=${VERSION}..."
kubectl apply -n argocd \
  -k "https://github.com/argoproj-labs/argocd-agent/install/kubernetes/argo-cd/agent-managed?ref=${VERSION}" \
  --context $SPOKE_CTX


# Patch: Generate Secret Key (Critical for Agent-Managed mode)
echo "→ Patching argocd-secret with generated server.secretkey..."
SECRET_KEY=$(openssl rand -base64 32 | base64 -w 0)
kubectl patch secret argocd-secret -n argocd --context $SPOKE_CTX --patch "{\"data\":{\"server.secretkey\":\"$SECRET_KEY\"}}" || echo "Secret patch warning (ignore if first run)"

# Patch: k3s Redis Workaround (HostNetwork + delete NetworkPolicy)
if kubectl get node -o wide --context $SPOKE_CTX | grep -q "k3s"; then
  echo "→ Detected k3s cluster. Applying Redis HostNetwork workaround for connectivity..."
  kubectl patch deployment argocd-redis -n argocd --context $SPOKE_CTX --patch '{"spec": {"template": {"spec": {"hostNetwork": true, "dnsPolicy": "ClusterFirstWithHostNet"}}}}'
  
  # CRITICAL: NetworkPolicy doesn't work correctly with hostNetwork pods
  # Pod traffic comes from node network, not pod network, bypassing NetworkPolicy selectors
  echo "→ Deleting Redis NetworkPolicy (incompatible with hostNetwork)..."
  kubectl delete networkpolicy argocd-redis-network-policy -n argocd --context $SPOKE_CTX --ignore-not-found=true
  
  # Wait for Redis to restart with hostNetwork
  echo "→ Waiting for Redis to restart with hostNetwork..."
  kubectl rollout status deployment/argocd-redis -n argocd --context $SPOKE_CTX --timeout=120s
fi

echo "→ Waiting for argocd-application-controller..."
kubectl rollout status statefulset/argocd-application-controller -n argocd --context $SPOKE_CTX

echo "→ Waiting for argocd-repo-server..."
kubectl wait --for=condition=available --timeout=300s \
  deployment/argocd-repo-server -n argocd --context $SPOKE_CTX

echo ""
echo "Step 3 Complete."
