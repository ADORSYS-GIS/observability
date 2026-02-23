#!/bin/bash
set -euo pipefail

# Detect cloud provider from kubeconfig context
# Outputs: gke, eks, aks, or generic

CONTEXT=$(kubectl config current-context 2>/dev/null || echo "unknown")
SERVER=$(kubectl config view -o jsonpath="{.clusters[?(@.name==\"$(kubectl config current-context)\")].cluster.server}" 2>/dev/null || echo "")

echo "🔍 Detecting cloud provider from context: $CONTEXT"
echo "📡 Cluster server: $SERVER"

if [[ "$SERVER" == *"googleapis.com"* ]] || [[ "$CONTEXT" == *"gke_"* ]]; then
  echo "gke"
  exit 0
fi

if [[ "$SERVER" == *"eks.amazonaws.com"* ]] || [[ "$CONTEXT" == *"eks"* ]] || [[ "$CONTEXT" == *"arn:aws"* ]]; then
  echo "eks"
  exit 0
fi

if [[ "$SERVER" == *"azmk8s.io"* ]] || [[ "$CONTEXT" == *"aks"* ]]; then
  echo "aks"
  exit 0
fi

echo "⚠️ Could not detect specific cloud provider, defaulting to: generic"
echo "generic"
