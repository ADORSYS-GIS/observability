#!/bin/bash
set -euo pipefail

# Verify LGTM Stack deployment health
# Generates HTML report with deployment status

NAMESPACE="${NAMESPACE:-observability}"
TIMEOUT="${TIMEOUT:-600}"
REPORT_FILE="verification-report.html"

echo "🔍 Verifying LGTM Stack deployment in namespace: $NAMESPACE"
echo "⏱️  Timeout: ${TIMEOUT}s"

# Initialize report
cat > "$REPORT_FILE" <<'EOF'
<!DOCTYPE html>
<html>
<head>
  <title>LGTM Stack Deployment Verification</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
    .container { max-width: 1200px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; }
    h1 { color: #333; border-bottom: 2px solid #4CAF50; padding-bottom: 10px; }
    .section { margin: 20px 0; padding: 15px; background: #f9f9f9; border-left: 4px solid #4CAF50; }
    .success { color: #4CAF50; }
    .error { color: #f44336; }
    .warning { color: #ff9800; }
    table { width: 100%; border-collapse: collapse; margin: 10px 0; }
    th, td { padding: 10px; text-align: left; border-bottom: 1px solid #ddd; }
    th { background-color: #4CAF50; color: white; }
    .status-ok { background-color: #c8e6c9; }
    .status-error { background-color: #ffcdd2; }
    .timestamp { color: #666; font-size: 0.9em; }
  </style>
</head>
<body>
<div class="container">
  <h1>🔍 LGTM Stack Deployment Verification</h1>
  <p class="timestamp">Generated: $(date)</p>
EOF

# Function to add section to report
add_section() {
  local title="$1"
  local content="$2"
  local status="${3:-success}"
  
  cat >> "$REPORT_FILE" <<EOF
  <div class="section">
    <h2 class="$status">$title</h2>
    <pre>$content</pre>
  </div>
EOF
}

# 1. Check namespace exists
echo "📂 Checking namespace..."
if kubectl get namespace "$NAMESPACE" >/dev/null; then
  add_section "✅ Namespace" "Namespace '$NAMESPACE' exists"
else
  echo "❌ Namespace check failed. Printing stderr for debugging..."
  kubectl get namespace "$NAMESPACE" || true
  add_section "❌ Namespace" "Namespace '$NAMESPACE' not found or authentication failed" "error"
  echo "</div></body></html>" >> "$REPORT_FILE"
  echo "❌ Verification failed: namespace not found or authentication failed"
  exit 1
fi

# 2. Wait for all pods to be ready
echo "⏳ Waiting for pods to be ready (timeout: ${TIMEOUT}s)..."
START_TIME=$(date +%s)

while true; do
  NOT_READY=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | grep -v "Running\|Completed" | wc -l || echo "0")
  
  if [ "$NOT_READY" -eq 0 ]; then
    echo "✅ All pods are ready"
    break
  fi
  
  ELAPSED=$(($(date +%s) - START_TIME))
  if [ "$ELAPSED" -gt "$TIMEOUT" ]; then
    echo "⏱️  Timeout waiting for pods"
    break
  fi
  
  echo "  ⏳ Waiting... ($NOT_READY pods not ready, ${ELAPSED}s elapsed)"
  sleep 10
done

# Get pod status
POD_STATUS=$(kubectl get pods -n "$NAMESPACE" -o wide 2>/dev/null || echo "No pods found")
add_section "📦 Pod Status" "$POD_STATUS"

# 3. Check deployments
echo "🚀 Checking deployments..."
DEPLOYMENTS=$(kubectl get deployments -n "$NAMESPACE" 2>/dev/null || echo "No deployments found")
add_section "🚀 Deployments" "$DEPLOYMENTS"

# 4. Check StatefulSets
echo "💾 Checking StatefulSets..."
STATEFULSETS=$(kubectl get statefulsets -n "$NAMESPACE" 2>/dev/null || echo "No StatefulSets found")
add_section "💾 StatefulSets" "$STATEFULSETS"

# 5. Check services
echo "🌐 Checking services..."
SERVICES=$(kubectl get services -n "$NAMESPACE" 2>/dev/null || echo "No services found")
add_section "🌐 Services" "$SERVICES"

# 6. Check ingress
echo "🔗 Checking ingress..."
INGRESS=$(kubectl get ingress -n "$NAMESPACE" 2>/dev/null || echo "No ingress found")
add_section "🔗 Ingress Resources" "$INGRESS"

# 7. Check PVCs
echo "💿 Checking PVCs..."
PVCS=$(kubectl get pvc -n "$NAMESPACE" 2>/dev/null || echo "No PVCs found")
add_section "💿 Persistent Volume Claims" "$PVCS"

# 8. Component-specific checks
echo "🔍 Checking LGTM components..."

# Grafana
if kubectl get deployment -n "$NAMESPACE" -l app.kubernetes.io/name=grafana &>/dev/null; then
  GRAFANA_READY=$(kubectl get deployment -n "$NAMESPACE" -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].status.readyReplicas}' 2>/dev/null || echo "0")
  if [ "$GRAFANA_READY" -gt 0 ]; then
    add_section "✅ Grafana" "Grafana is running ($GRAFANA_READY replicas ready)"
  else
    add_section "❌ Grafana" "Grafana is not ready" "error"
  fi
fi

# Loki
if kubectl get statefulset -n "$NAMESPACE" -l app.kubernetes.io/name=loki &>/dev/null; then
  LOKI_INFO=$(kubectl get statefulset -n "$NAMESPACE" -l app.kubernetes.io/name=loki)
  add_section "📝 Loki" "$LOKI_INFO"
fi

# Mimir
if kubectl get statefulset -n "$NAMESPACE" -l app.kubernetes.io/name=mimir &>/dev/null; then
  MIMIR_INFO=$(kubectl get statefulset -n "$NAMESPACE" -l app.kubernetes.io/name=mimir)
  add_section "📊 Mimir" "$MIMIR_INFO"
fi

# Tempo
if kubectl get statefulset -n "$NAMESPACE" -l app.kubernetes.io/name=tempo &>/dev/null; then
  TEMPO_INFO=$(kubectl get statefulset -n "$NAMESPACE" -l app.kubernetes.io/name=tempo)
  add_section "🔍 Tempo" "$TEMPO_INFO"
fi

# Prometheus
if kubectl get deployment -n "$NAMESPACE" -l app.kubernetes.io/name=prometheus &>/dev/null; then
  PROM_INFO=$(kubectl get deployment -n "$NAMESPACE" -l app.kubernetes.io/name=prometheus)
  add_section "🎯 Prometheus" "$PROM_INFO"
fi

# 9. Check for errors in recent logs
echo "📋 Checking recent logs for errors..."
ERROR_COUNT=0
for pod in $(kubectl get pods -n "$NAMESPACE" -o name 2>/dev/null); do
  ERRORS=$(kubectl logs "$pod" -n "$NAMESPACE" --tail=50 2>/dev/null | grep -i "error\|fatal\|panic" | head -5 || echo "")
  if [ -n "$ERRORS" ]; then
    ERROR_COUNT=$((ERROR_COUNT + 1))
  fi
done

if [ "$ERROR_COUNT" -eq 0 ]; then
  add_section "✅ Log Analysis" "No critical errors found in recent logs"
else
  add_section "⚠️ Log Analysis" "Found errors in $ERROR_COUNT pod(s) - check logs for details" "warning"
fi

# Close HTML
cat >> "$REPORT_FILE" <<EOF
  <div class="section">
    <h2>📊 Summary</h2>
    <p>Verification completed at: $(date)</p>
    <p>Namespace: $NAMESPACE</p>
  </div>
</div>
</body>
</html>
EOF

echo ""
echo "✅ Verification complete!"
echo "📄 Report saved to: $REPORT_FILE"
echo ""
echo "Quick Status:"
kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | awk '{print "  " $1 ": " $3}' || echo "  No pods found"
