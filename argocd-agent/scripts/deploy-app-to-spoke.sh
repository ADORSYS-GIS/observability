#!/bin/bash
set -euo pipefail

# =============================================================================
# Deploy Application to ArgoCD Agent Spoke Cluster
# =============================================================================
# This script helps deploy applications to spoke clusters in managed mode
# by ensuring they are created in the correct agent namespace.
#
# Usage:
#   ./deploy-app-to-spoke.sh <agent-name> <app-name> <git-repo> <path> [namespace]
#
# Example:
#   ./deploy-app-to-spoke.sh agent-1 sock-shop \
#     https://github.com/argoproj/argocd-example-apps.git sock-shop
# =============================================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored messages
info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Check arguments
if [ $# -lt 4 ]; then
    error "Usage: $0 <agent-name> <app-name> <git-repo> <path> [target-namespace]
    
Examples:
  $0 agent-1 sock-shop https://github.com/argoproj/argocd-example-apps.git sock-shop
  $0 agent-2 guestbook https://github.com/argoproj/argocd-example-apps.git guestbook default
  
Available agents:"
    kubectl get ns --context "${HUB_CONTEXT:-gke_observe-472521_europe-west3_observe-prod-cluster}" 2>/dev/null | grep "^agent-" | awk '{print "  - " $1}' || echo "  (unable to list agents)"
    exit 1
fi

AGENT_NAME="$1"
APP_NAME="$2"
GIT_REPO="$3"
GIT_PATH="$4"
TARGET_NAMESPACE="${5:-$APP_NAME}"

# Hub context (can override with env var)
HUB_CONTEXT="${HUB_CONTEXT:-gke_observe-472521_europe-west3_observe-prod-cluster}"

# Validate agent namespace exists on hub
info "Validating agent namespace '$AGENT_NAME' exists on hub..."
if ! kubectl get ns "$AGENT_NAME" --context "$HUB_CONTEXT" &>/dev/null; then
    error "Agent namespace '$AGENT_NAME' does not exist on hub cluster.
    
Available agent namespaces:"
    kubectl get ns --context "$HUB_CONTEXT" | grep "^agent-" | awk '{print "  - " $1}'
    exit 1
fi

# Warn if application already exists
if kubectl get app "$APP_NAME" -n "$AGENT_NAME" --context "$HUB_CONTEXT" &>/dev/null; then
    warn "Application '$APP_NAME' already exists in namespace '$AGENT_NAME'"
    read -p "Do you want to replace it? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
        info "Aborted."
        exit 0
    fi
    info "Deleting existing application..."
    kubectl delete app "$APP_NAME" -n "$AGENT_NAME" --context "$HUB_CONTEXT"
    sleep 2
fi

# Create application in the correct agent namespace
info "Creating application '$APP_NAME' in namespace '$AGENT_NAME'..."
info "  Git Repo: $GIT_REPO"
info "  Git Path: $GIT_PATH"
info "  Target Namespace: $TARGET_NAMESPACE"
info "  Agent: $AGENT_NAME"

cat <<EOF | kubectl apply -f - --context "$HUB_CONTEXT"
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: $APP_NAME
  namespace: $AGENT_NAME
spec:
  project: default
  source:
    repoURL: $GIT_REPO
    targetRevision: HEAD
    path: $GIT_PATH
  destination:
    server: https://argocd-agent-resource-proxy.argocd.svc.cluster.local:9090?agentName=$AGENT_NAME
    namespace: $TARGET_NAMESPACE
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
EOF

info "Application created successfully!"
info ""
info "Waiting for sync to start..."
sleep 5

# Check application status on hub
info "Application status on hub:"
kubectl get app "$APP_NAME" -n "$AGENT_NAME" --context "$HUB_CONTEXT"

info ""
info "To watch deployment progress:"
echo "  # On hub:"
echo "  kubectl get app $APP_NAME -n $AGENT_NAME --context $HUB_CONTEXT -w"
echo ""
echo "  # On spoke (determine spoke context from your config):"
echo "  kubectl get app $APP_NAME -n argocd --context <spoke-context>"
echo "  kubectl get pods -n $TARGET_NAMESPACE --context <spoke-context> -w"
echo ""
info "To access via ArgoCD UI:"
echo "  https://argocd.observe.camer.digital/applications/$AGENT_NAME/$APP_NAME"
