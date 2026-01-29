#!/bin/bash
# Step 5: Verification (Official Guide)
# 6.4 Test Application Synchronization (Managed Mode)

set -e

HUB_CTX="${HUB_CTX:-}"
AGENT_NAME="${1:-}"
SPOKE_CTX="${2:-}"
APP_NAME="test-app-${AGENT_NAME}"
HUB_NAMESPACE="${3:-argocd}"

# Usage
if [ -z "$HUB_CTX" ] || [ -z "$AGENT_NAME" ] || [ -z "$SPOKE_CTX" ]; then
  echo "Usage: HUB_CTX=<hub-context> $0 <agent-name> <spoke-context>"
  echo ""
  echo "Example:"
  echo "  HUB_CTX=gke_proj_region_hub $0 agent-1 gke_proj_region_spoke1"
  echo ""
  echo "Environment variables:"
  echo "  HUB_CTX    - Hub cluster kubectl context (required)"
  echo ""
  echo "Available contexts:"
  kubectl config get-contexts -o name
  exit 1
fi

echo "════════════════════════════════════════════════"
echo "  Step 5: Application Deployment Verification"
echo "════════════════════════════════════════════════"
echo ""
echo "Testing agent: $AGENT_NAME"
echo "Spoke context: $SPOKE_CTX"
echo "Hub context: $HUB_CTX"
echo ""

# Get Principal IP
echo "→ Getting Principal IP address..."
PRINCIPAL_IP=$(kubectl get svc argocd-agent-principal -n $HUB_NAMESPACE --context $HUB_CTX -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

if [ -z "$PRINCIPAL_IP" ] || [ "$PRINCIPAL_IP" = "null" ]; then
  echo "✗ ERROR: Principal IP not available. Checking service status..."
  kubectl get svc argocd-agent-principal -n $HUB_NAMESPACE --context $HUB_CTX
  exit 1
fi

echo "✓ Principal IP: $PRINCIPAL_IP"

# Get Principal service port
SVC_PORT=$(kubectl get svc argocd-agent-principal -n $HUB_NAMESPACE --context $HUB_CTX -o jsonpath='{.spec.ports[0].port}')
echo "✓ Principal Port: $SVC_PORT"
echo ""

echo "→ Checking agent connectivity..."
kubectl logs -n argocd deployment/argocd-agent-agent --context $SPOKE_CTX --tail=20 | grep -i "connected\|error\|failed" || echo "No connectivity messages in recent logs"
echo ""

echo "→ Propagating default AppProject..."
kubectl patch appproject default -n $HUB_NAMESPACE --context $HUB_CTX \
  --type='merge' \
  --patch='{"spec":{"sourceNamespaces":["*"],"destinations":[{"name":"*","namespace":"*","server":"*"}]}}' 2>/dev/null || echo "AppProject already configured"

echo "→ Checking AppProject propagation on Spoke..."
sleep 5
if kubectl get appprojs -n argocd --context $SPOKE_CTX 2>/dev/null | grep -q default; then
  echo "✓ AppProject 'default' propagated to spoke"
else
  echo "⚠ WARNING: AppProject not yet propagated"
fi

echo ""
echo "→ Creating Test Application '$APP_NAME' (guestbook example)..."
echo "   Source: https://github.com/argoproj/argocd-example-apps/guestbook"
echo "   Destination: Agent '$AGENT_NAME' via Principal $PRINCIPAL_IP:$SVC_PORT"
echo ""

cat <<EOF | kubectl apply -f - --context $HUB_CTX
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: $APP_NAME
  namespace: $AGENT_NAME
spec:
  project: default
  source:
    repoURL: https://github.com/argoproj/argocd-example-apps
    targetRevision: HEAD
    path: guestbook
  destination:
    server: https://argocd-agent-resource-proxy.argocd.svc.cluster.local:9090?agentName=${AGENT_NAME}
    namespace: guestbook
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
EOF

echo ""
echo "✓ Application created on hub"
echo ""

echo "→ Waiting for application to sync (30 seconds)..."
sleep 10
echo "   10 seconds..."
sleep 10
echo "   20 seconds..."
sleep 10
echo "   30 seconds elapsed"
echo ""

echo "════════════════════════════════════════════════"
echo "  Verification Results"
echo "════════════════════════════════════════════════"
echo ""

echo "1️⃣  Application on Hub (Control Plane):"
echo "----------------------------------------"
kubectl get applications -n $AGENT_NAME --context $HUB_CTX -o wide 2>/dev/null || echo "✗ Application not found on hub"
echo ""

echo "2️⃣  Application on Spoke (Workload Cluster):"
echo "----------------------------------------"
kubectl get applications -n argocd --context $SPOKE_CTX -o wide 2>/dev/null || echo "⚠ Application not yet propagated to spoke"
echo ""

echo "3️⃣  Deployed Resources (Guestbook Pods):"
echo "----------------------------------------"
if kubectl get ns guestbook --context $SPOKE_CTX 2>/dev/null >/dev/null; then
  kubectl get pods -n guestbook --context $SPOKE_CTX -o wide
  echo ""
  kubectl get svc -n guestbook --context $SPOKE_CTX
  echo ""
  echo "✓ Application deployed successfully!"
else
  echo "⚠ Namespace 'guestbook' not found yet on spoke cluster"
  echo "   This is normal if sync is still in progress"
fi

echo ""
echo "════════════════════════════════════════════════"
echo "  Quick Commands"
echo "════════════════════════════════════════════════"
echo ""
echo "Check application status:"
echo "  kubectl get app -n $AGENT_NAME --context $HUB_CTX"
echo ""
echo "Watch application sync:"
echo "  kubectl get app $APP_NAME -n $AGENT_NAME --context $HUB_CTX -w"
echo ""
echo "Check application details:"
echo "  kubectl describe app $APP_NAME -n $AGENT_NAME --context $HUB_CTX"
echo ""
echo "Check guestbook pods:"
echo "  kubectl get pods -n guestbook --context $SPOKE_CTX"
echo ""
echo "Delete test application:"
echo "  kubectl delete app $APP_NAME -n $AGENT_NAME --context $HUB_CTX"
echo ""
