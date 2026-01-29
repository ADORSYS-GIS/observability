#!/bin/bash
# Step 1: Control Plane Setup (Official Guide)
# 1.1 Create Namespace
# 1.2 Install Argo CD (Principal Profile)
# 1.3 Enable Apps-in-Any-Namespace
# 1.4 Expose UI

set -e

# Configuration
HUB_CTX="${HUB_CTX:-}"
VERSION="${VERSION:-v0.5.3}"

# Usage
if [ -z "$HUB_CTX" ]; then
  echo "Usage: HUB_CTX=<context> [VERSION=v0.5.3] $0"
  echo ""
  echo "Example:"
  echo "  HUB_CTX=gke_project_region_cluster VERSION=v0.5.3 $0"
  echo ""
  echo "Available contexts:"
  kubectl config get-contexts -o name
  exit 1
fi

echo "════════════════════════════════════════════════"
echo "  Step 1: Control Plane Setup"
echo "════════════════════════════════════════════════"
echo ""

# 1.1 Create Namespace
echo "→ Creating namespace 'argocd'..."
kubectl create namespace argocd --context $HUB_CTX --dry-run=client -o yaml | kubectl apply --context $HUB_CTX -f -

# 1.2 Install Argo CD (Principal Profile)
echo "→ Installing Argo CD (Principal Profile) ref=${VERSION}..."
kubectl apply -n argocd \
  -k "https://github.com/argoproj-labs/argocd-agent/install/kubernetes/argo-cd/principal?ref=${VERSION}" \
  --context $HUB_CTX

echo "→ Waiting for argocd-server..."
kubectl wait --for=condition=available --timeout=300s \
  deployment/argocd-server -n argocd --context $HUB_CTX

# 1.3 Enable Apps-in-Any-Namespace
echo "→ Enabling apps-in-any-namespace..."
kubectl patch configmap argocd-cmd-params-cm -n argocd --context $HUB_CTX \
  --type='merge' \
  --patch '{"data":{"application.namespaces":"*"}}'

echo "→ Restarting argocd-server..."
kubectl rollout restart deployment argocd-server -n argocd --context $HUB_CTX
kubectl rollout status deployment/argocd-server -n argocd --context $HUB_CTX

# 1.4 Expose Argo CD UI (LoadBalancer)
echo "→ Exposing Argo CD UI via LoadBalancer..."
kubectl patch svc argocd-server -n argocd --context $HUB_CTX \
  --patch '{"spec":{"type":"LoadBalancer"}}'

echo "→ Waiting for External IP..."
EXTERNAL_IP=""
while [ -z "$EXTERNAL_IP" ]; do
  echo "  Waiting for IP..."
  sleep 5
  EXTERNAL_IP=$(kubectl get svc argocd-server -n argocd --context $HUB_CTX -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
done
echo "✓ Argo CD UI available at https://$EXTERNAL_IP"
echo ""
echo "Step 1 Complete."
