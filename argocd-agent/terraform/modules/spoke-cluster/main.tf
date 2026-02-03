# =============================================================================
# SPOKE CLUSTER MODULE
# =============================================================================
# This module manages ArgoCD agent installations on spoke clusters
# =============================================================================

resource "null_resource" "spoke_namespace" {
  for_each = var.clusters

  # Capture values at creation time for destroy provisioner
  triggers = {
    namespace = var.spoke_namespace
    context   = each.value
    agent     = each.key
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -e
      
      if ! kubectl get namespace ${self.triggers.namespace} --context ${self.triggers.context} >/dev/null 2>&1; then
        echo "Creating namespace ${self.triggers.namespace} in cluster ${self.triggers.context}..."
        kubectl create namespace ${self.triggers.namespace} --context ${self.triggers.context}
        echo "✓ Namespace ${self.triggers.namespace} created in ${self.triggers.context}"
      else
        echo "✓ Namespace ${self.triggers.namespace} already exists in ${self.triggers.context}"
      fi
    EOT
  }

  provisioner "local-exec" {
    when        = destroy
    on_failure  = continue
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      echo "Deleting namespace ${self.triggers.namespace} from ${self.triggers.context}..."
      
      # Graceful deletion with timeout
      if ! kubectl delete namespace ${self.triggers.namespace} \
        --context ${self.triggers.context} \
        --ignore-not-found=true \
        --timeout=120s 2>&1 | tee /tmp/ns-delete-${self.triggers.agent}.log; then
        
        echo "WARNING: Graceful deletion timed out, attempting force deletion..."
        
        # Remove finalizers
        kubectl patch namespace ${self.triggers.namespace} \
          -p '{"metadata":{"finalizers":null}}' \
          --context ${self.triggers.context} 2>/dev/null || true
        
        # Force delete
        kubectl delete namespace ${self.triggers.namespace} \
          --context ${self.triggers.context} \
          --ignore-not-found=true \
          --grace-period=0 \
          --force 2>&1 || true
      fi
      
      echo "✓ Namespace ${self.triggers.namespace} cleanup completed for ${self.triggers.context}"
    EOT
  }
}

# Installs ArgoCD in agent-managed mode on spoke clusters (minimal components)
resource "null_resource" "spoke_argocd_installation" {
  for_each = var.clusters

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      GIT_HTTP_USER_AGENT   = "kubectl-kustomize"
      GIT_CONFIG_PARAMETERS = "'http.lowSpeedLimit=1000' 'http.lowSpeedTime=600'"
    }
    command = <<-EOT
      set -e
      set -o pipefail
      
      LOG_FILE="/tmp/argocd-spoke-install-${each.key}-$$(date +%Y%m%d-%H%M%S).log"
      MAX_RETRIES=${var.argocd_install_retry_attempts}
      RETRY_DELAY=${var.argocd_install_retry_delay}
      RETRY=0
      
      echo "Installing ArgoCD (agent-managed) on spoke cluster: ${each.key}" | tee -a "$$LOG_FILE"
      echo "Installation URL: ${local.agent_spoke_managed_install_url}" | tee -a "$$LOG_FILE"
      
      while [ $RETRY -lt $MAX_RETRIES ]; do
        echo "[Attempt $((RETRY+1))/$MAX_RETRIES] Applying ArgoCD agent-managed manifests..." | tee -a "$$LOG_FILE"
        
        if kubectl apply -n ${var.spoke_namespace} \
          --context ${each.value} \
          --server-side=true \
          --timeout=300s \
          -k "${local.agent_spoke_managed_install_url}" 2>&1 | tee -a "$$LOG_FILE"; then
          echo "✓ ArgoCD manifests applied successfully to ${each.key}" | tee -a "$$LOG_FILE"
          break
        fi
        
        RETRY=$((RETRY+1))
        if [ $RETRY -lt $MAX_RETRIES ]; then
          echo "WARNING: Apply failed, retrying in $RETRY_DELAY seconds..." | tee -a "$$LOG_FILE"
          sleep $RETRY_DELAY
        else
          echo "✗ ERROR: Failed after $MAX_RETRIES attempts. Check logs: $$LOG_FILE" | tee -a "$$LOG_FILE"
          exit 1
        fi
      done
      
      echo "Waiting for ${var.argocd_repo_server_name} deployment..." | tee -a "$$LOG_FILE"
      if ! kubectl wait --for=condition=available --timeout=${var.kubectl_timeout} \
        deployment/${var.argocd_repo_server_name} -n ${var.spoke_namespace} \
        --context ${each.value} 2>&1 | tee -a "$$LOG_FILE"; then
        echo "✗ ERROR: ${var.argocd_repo_server_name} deployment failed. Check logs: $$LOG_FILE" | tee -a "$$LOG_FILE"
        kubectl describe deployment/${var.argocd_repo_server_name} -n ${var.spoke_namespace} --context ${each.value} | tee -a "$$LOG_FILE"
        exit 1
      fi
      
      echo "✓ ArgoCD agent-managed components ready on ${each.key}" | tee -a "$$LOG_FILE"
      echo "Installation logs saved to: $$LOG_FILE"
    EOT
  }

  provisioner "local-exec" {
    when        = destroy
    on_failure  = continue
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      echo "Uninstalling ArgoCD from spoke cluster ${self.triggers.agent}..."
      kubectl delete -n ${self.triggers.namespace} \
        --context ${self.triggers.context} \
        -k "${self.triggers.manifest_url}" \
        --ignore-not-found=true \
        --timeout=120s || true
      echo "✓ ArgoCD uninstalled from ${self.triggers.agent}"
    EOT
  }

  depends_on = [
    null_resource.spoke_namespace
  ]

  triggers = {
    version      = var.argocd_version
    manifest_url = local.agent_spoke_managed_install_url
    agent        = each.key
    context      = each.value
    namespace    = var.spoke_namespace
  }
}

# Patches ArgoCD secret with server.secretkey required for agent-managed mode
resource "null_resource" "spoke_argocd_secret_patch" {
  for_each = var.clusters

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -e
      set -o pipefail
      
      LOG_FILE="/tmp/argocd-spoke-secret-${each.key}-$$(date +%Y%m%d-%H%M%S).log"
      
      echo "Patching ${var.argocd_secret_name} with server.secretkey for ${each.key}..." | tee -a "$$LOG_FILE"
      
      # Generate random secret key (already base64 encoded)
      SECRET_KEY="$$(openssl rand -base64 32)"
      
      # Use stringData to avoid double base64 encoding
      if ! kubectl patch secret ${var.argocd_secret_name} -n ${var.spoke_namespace} \
        --context ${each.value} \
        --type='json' \
        -p='[{"op": "add", "path": "/stringData", "value": {"server.secretkey": "'"$$SECRET_KEY"'"}}]' 2>&1 | tee -a "$$LOG_FILE"; then
        echo "WARNING: Warning: Secret patch failed - may not exist yet, will retry on next run" | tee -a "$$LOG_FILE"
      else
        echo "✓ ArgoCD secret patched successfully for ${each.key}" | tee -a "$$LOG_FILE"
      fi
      
      echo "Secret patch logs saved to: $$LOG_FILE"
    EOT
  }

  depends_on = [null_resource.spoke_argocd_installation]
}

# Creates in-cluster secret required for application-controller to deploy to local cluster
resource "null_resource" "spoke_cluster_secret" {
  for_each = var.clusters

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -e
      set -o pipefail
      
      LOG_FILE="/tmp/argocd-spoke-cluster-secret-${each.key}-$$(date +%Y%m%d-%H%M%S).log"
      
      echo "Creating in-cluster secret for application-controller on ${each.key}..." | tee -a "$$LOG_FILE"
      
      cat <<EOF | kubectl apply -f - --context ${each.value} 2>&1 | tee -a "$$LOG_FILE"
apiVersion: v1
kind: Secret
metadata:
  name: cluster-in-cluster
  namespace: ${var.spoke_namespace}
  labels:
    argocd.argoproj.io/secret-type: cluster
type: Opaque
stringData:
  name: in-cluster
  server: https://kubernetes.default.svc
  config: |
    {
      "tlsClientConfig": {
        "insecure": false
      }
    }
EOF
      
      # Check exit code of kubectl (first command in pipeline)
      if [ $${PIPESTATUS[0]} -eq 0 ]; then
        echo "✓ In-cluster secret created successfully for ${each.key}" | tee -a "$$LOG_FILE"
      else
        echo "✗ ERROR: Failed to create in-cluster secret. Check logs: $$LOG_FILE" | tee -a "$$LOG_FILE"
        exit 1
      fi
      
      echo "Cluster secret logs saved to: $$LOG_FILE"
    EOT
  }

  provisioner "local-exec" {
    when        = destroy
    on_failure  = continue
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      echo "Deleting in-cluster secret from ${self.triggers.agent}..."
      kubectl delete secret cluster-in-cluster -n ${self.triggers.namespace} \
        --context ${self.triggers.context} \
        --ignore-not-found=true || true
      echo "✓ In-cluster secret deleted from ${self.triggers.agent}"
    EOT
  }

  depends_on = [null_resource.spoke_argocd_installation]

  triggers = {
    agent     = each.key
    context   = each.value
    namespace = var.spoke_namespace
  }
}

# Applies k3s-specific Redis workaround (hostNetwork mode and NetworkPolicy removal)
resource "null_resource" "spoke_k3s_redis_workaround" {
  for_each = var.clusters

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -e
      set -o pipefail
      
      LOG_FILE="/tmp/argocd-spoke-k3s-redis-${each.key}-$$(date +%Y%m%d-%H%M%S).log"
      
      echo "Checking if ${each.key} is k3s cluster..." | tee -a "$$LOG_FILE"
      
      if kubectl get node -o wide --context ${each.value} 2>&1 | tee -a "$$LOG_FILE" | grep -q "k3s"; then
        echo "✓ Detected k3s cluster. Applying Redis HostNetwork workaround..." | tee -a "$$LOG_FILE"
        
        if ! kubectl patch deployment ${var.argocd_redis_name} -n ${var.spoke_namespace} \
          --context ${each.value} \
          --patch '{"spec": {"template": {"spec": {"hostNetwork": true, "dnsPolicy": "ClusterFirstWithHostNet"}}}}' \
          2>&1 | tee -a "$$LOG_FILE"; then
          echo "✗ ERROR: Failed to patch ${var.argocd_redis_name} deployment. Check logs: $$LOG_FILE" | tee -a "$$LOG_FILE"
          exit 1
        fi
        
        echo "Removing Redis NetworkPolicy..." | tee -a "$$LOG_FILE"
        kubectl delete networkpolicy ${var.argocd_redis_network_policy_name} -n ${var.spoke_namespace} \
          --context ${each.value} --ignore-not-found=true 2>&1 | tee -a "$$LOG_FILE"
        
        echo "Waiting for Redis rollout..." | tee -a "$$LOG_FILE"
        if ! kubectl rollout status deployment/${var.argocd_redis_name} -n ${var.spoke_namespace} \
          --context ${each.value} --timeout=${var.namespace_delete_timeout} 2>&1 | tee -a "$$LOG_FILE"; then
          echo "✗ ERROR: Redis rollout failed. Check logs: $$LOG_FILE" | tee -a "$$LOG_FILE"
          exit 1
        fi
        
        echo "✓ k3s Redis workaround applied successfully" | tee -a "$$LOG_FILE"
      else
        echo "✓ Cluster ${each.key} is not k3s. Skipping workaround." | tee -a "$$LOG_FILE"
      fi
      
      echo "Logs saved to: $$LOG_FILE"
    EOT
  }

  depends_on = [
    null_resource.spoke_argocd_installation,
    null_resource.spoke_cluster_secret
  ]
}

# Waits for all ArgoCD components to be ready on spoke clusters
resource "null_resource" "spoke_argocd_readiness_check" {
  for_each = var.clusters

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -e
      set -o pipefail
      
      LOG_FILE="/tmp/argocd-spoke-ready-${each.key}-$$(date +%Y%m%d-%H%M%S).log"
      
      echo "Waiting for ArgoCD components on ${each.key}..." | tee -a "$$LOG_FILE"
      
      echo "Checking ${var.argocd_application_controller_name} statefulset..." | tee -a "$$LOG_FILE"
      if ! kubectl rollout status statefulset/${var.argocd_application_controller_name} \
        -n ${var.spoke_namespace} \
        --context ${each.value} \
        --timeout=${var.kubectl_timeout} 2>&1 | tee -a "$$LOG_FILE"; then
        echo "✗ ERROR: ${var.argocd_application_controller_name} failed. Check logs: $$LOG_FILE" | tee -a "$$LOG_FILE"
        kubectl describe statefulset/${var.argocd_application_controller_name} -n ${var.spoke_namespace} --context ${each.value} | tee -a "$$LOG_FILE"
        exit 1
      fi
      
      echo "Checking ${var.argocd_repo_server_name} deployment..." | tee -a "$$LOG_FILE"
      if ! kubectl wait --for=condition=available --timeout=${var.kubectl_timeout} \
        deployment/${var.argocd_repo_server_name} -n ${var.spoke_namespace} \
        --context ${each.value} 2>&1 | tee -a "$$LOG_FILE"; then
        echo "✗ ERROR: ${var.argocd_repo_server_name} failed. Check logs: $$LOG_FILE" | tee -a "$$LOG_FILE"
        kubectl describe deployment/${var.argocd_repo_server_name} -n ${var.spoke_namespace} --context ${each.value} | tee -a "$$LOG_FILE"
        exit 1
      fi
      
      echo "✓ All ArgoCD components ready on ${each.key}" | tee -a "$$LOG_FILE"
      echo "Readiness check logs saved to: $$LOG_FILE"
    EOT
  }

  depends_on = [
    null_resource.spoke_argocd_secret_patch,
    null_resource.spoke_k3s_redis_workaround
  ]
}

# =============================================================================
# SECTION 6: AGENT CONNECTION TO HUB (04-agent-connect.sh)
# CRITICAL: Exact script order
# =============================================================================

# Generate random passwords for agent resource proxy authentication
resource "random_password" "agent_proxy_password" {
  for_each         = var.clusters
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
}

# Creates agent configuration on hub cluster for spoke agent authentication

resource "null_resource" "spoke_agent_client_certificate" {
  for_each = var.clusters

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -e
      set -o pipefail
      
      LOG_FILE="/tmp/argocd-agent-cert-${each.key}-$$(date +%Y%m%d-%H%M%S).log"
      
      echo "Issuing client certificate for agent ${each.key}..." | tee -a "$$LOG_FILE"
      
      echo "Removing existing certificate for idempotency..." | tee -a "$$LOG_FILE"
      kubectl delete secret argocd-agent-client-tls -n ${var.spoke_namespace} \
        --context ${each.value} --ignore-not-found=true 2>&1 | tee -a "$$LOG_FILE"
      
      echo "Generating new client certificate..." | tee -a "$$LOG_FILE"
      if ! ${var.argocd_agentctl_path} pki issue agent ${each.key} \
        --principal-context ${var.hub_cluster_context} \
        --agent-context ${each.value} \
        --agent-namespace ${var.spoke_namespace} \
        --upsert 2>&1 | tee -a "$$LOG_FILE"; then
        echo "✗ ERROR: Failed to issue client certificate. Check logs: $$LOG_FILE" | tee -a "$$LOG_FILE"
        exit 1
      fi
      
      echo "✓ Client certificate issued for ${each.key}" | tee -a "$$LOG_FILE"
      echo "Certificate logs saved to: $$LOG_FILE"
    EOT
  }

  provisioner "local-exec" {
    when        = destroy
    on_failure  = continue
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      echo "Deleting client certificate for agent ${self.triggers.agent}..."
      kubectl delete secret argocd-agent-client-tls \
        -n ${self.triggers.namespace} \
        --context ${self.triggers.context} \
        --ignore-not-found=true || true
      echo "✓ Client certificate deleted for ${self.triggers.agent}"
    EOT
  }

  depends_on = [null_resource.spoke_argocd_readiness_check]

  triggers = {
    agent     = each.key
    context   = each.value
    namespace = var.spoke_namespace
  }
}

# Propagates CA certificate from hub to spoke cluster for mTLS trust chain
resource "null_resource" "spoke_agent_ca_propagation" {
  for_each = var.clusters

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -e
      set -o pipefail
      
      LOG_FILE="/tmp/argocd-agent-ca-${each.key}-$$(date +%Y%m%d-%H%M%S).log"
      
      echo "Propagating CA certificate to ${each.key}..." | tee -a "$LOG_FILE"
      
      echo "Removing existing CA for idempotency..." | tee -a "$LOG_FILE"
      kubectl delete secret argocd-agent-ca -n ${var.spoke_namespace} \
        --context ${each.value} --ignore-not-found=true 2>&1 | tee -a "$LOG_FILE"
      
      echo "Propagating CA from hub to spoke..." | tee -a "$LOG_FILE"
      if ! ${var.argocd_agentctl_path} pki propagate \
        --principal-context ${var.hub_cluster_context} \
        --principal-namespace ${var.hub_namespace} \
        --agent-context ${each.value} \
        --agent-namespace ${var.spoke_namespace} 2>&1 | tee -a "$LOG_FILE"; then
        echo "✗ ERROR: Failed to propagate CA. Check logs: $LOG_FILE" | tee -a "$LOG_FILE"
        exit 1
      fi
      
      echo "✓ CA certificate propagated to ${each.key}" | tee -a "$LOG_FILE"
      echo "CA propagation logs saved to: $LOG_FILE"
    EOT
  }

  provisioner "local-exec" {
    when        = destroy
    on_failure  = continue
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      echo "Deleting CA certificate from ${self.triggers.agent}..."
      kubectl delete secret argocd-agent-ca \
        -n ${self.triggers.namespace} \
        --context ${self.triggers.context} \
        --ignore-not-found=true || true
      echo "✓ CA certificate deleted from ${self.triggers.agent}"
    EOT
  }

  depends_on = [null_resource.spoke_agent_client_certificate]

  triggers = {
    agent     = each.key
    context   = each.value
    namespace = var.spoke_namespace
  }
}

# 5.4 Verify Certificates (implicit in Terraform - will fail if missing)

# Deploys agent client component to spoke cluster
resource "null_resource" "spoke_agent_installation" {
  for_each = var.clusters

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -e
      set -o pipefail
      
      LOG_FILE="/tmp/argocd-agent-install-${each.key}-$$(date +%Y%m%d-%H%M%S).log"
      MAX_RETRIES=${var.argocd_install_retry_attempts}
      RETRY_DELAY=${var.argocd_install_retry_delay}
      RETRY=0
      
      echo "Installing agent client on ${each.key}..." | tee -a "$LOG_FILE"
      echo "Installation URL: ${local.agent_client_install_url}" | tee -a "$LOG_FILE"
      
      while [ $RETRY -lt $MAX_RETRIES ]; do
        echo "[Attempt $((RETRY+1))/$MAX_RETRIES] Applying agent manifests..." | tee -a "$LOG_FILE"
        
        if kubectl apply -n ${var.spoke_namespace} \
          --context ${each.value} \
          --server-side=true \
          --force-conflicts=true \
          -k "${local.agent_client_install_url}" 2>&1 | tee -a "$LOG_FILE"; then
          echo "✓ Agent manifests applied successfully to ${each.key}" | tee -a "$LOG_FILE"
          break
        fi
        
        RETRY=$((RETRY+1))
        if [ $RETRY -lt $MAX_RETRIES ]; then
          echo "WARNING: Apply failed, retrying in $RETRY_DELAY seconds..." | tee -a "$LOG_FILE"
          sleep $RETRY_DELAY
        else
          echo "✗ ERROR: Failed after $MAX_RETRIES attempts. Check logs: $LOG_FILE" | tee -a "$LOG_FILE"
          exit 1
        fi
      done
      
      echo "✓ Agent manifests deployed to ${each.key}" | tee -a "$LOG_FILE"
      echo "Installation logs saved to: $LOG_FILE"
    EOT
  }

  provisioner "local-exec" {
    when        = destroy
    on_failure  = continue
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      echo "Uninstalling agent client from ${self.triggers.agent}..."
      kubectl delete -n ${self.triggers.namespace} \
        --context ${self.triggers.context} \
        -k "${self.triggers.manifest_url}" \
        --ignore-not-found=true \
        --timeout=120s || true
      echo "✓ Agent client uninstalled from ${self.triggers.agent}"
    EOT
  }

  depends_on = [
    null_resource.spoke_agent_ca_propagation,
    null_resource.spoke_namespace
  ]

  triggers = {
    version      = var.argocd_version
    manifest_url = local.agent_client_install_url
    agent        = each.key
    context      = each.value
    namespace    = var.spoke_namespace
  }
}

# Configures agent connection parameters for mTLS connectivity to Principal
resource "null_resource" "spoke_agent_configuration" {
  for_each = var.clusters

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -e
      set -o pipefail
      
      LOG_FILE="/tmp/argocd-agent-config-${each.key}-$(date +%Y%m%d-%H%M%S).log"
      
      echo "Configuring agent ${each.key}..." | tee -a "$LOG_FILE"
      echo "Principal address: ${var.principal_address}:${var.principal_port}" | tee -a "$LOG_FILE"
      
      if [ "${var.principal_address}" = "pending" ]; then
        echo "✗ ERROR: Principal address not available. Check logs: $LOG_FILE" | tee -a "$LOG_FILE"
        exit 1
      fi
      
      echo "Applying agent configuration with mTLS and gRPC keep-alive..." | tee -a "$LOG_FILE"
      if ! kubectl patch configmap argocd-agent-params -n ${var.spoke_namespace} \
        --context ${each.value} \
        --type='merge' \
        --patch '{"data":{
          "agent.server.address":"${var.principal_address}",
          "agent.server.port":"${var.principal_port}",
          "agent.mode":"managed",
          "agent.creds":"mtls:^CN=(.+)$",
          "agent.tls.client.insecure":"false",
          "agent.tls.secret-name":"argocd-agent-client-tls",
          "agent.tls.root-ca-secret-name":"argocd-agent-ca",
          "agent.log.level":"info",
          "agent.keep-alive.interval":"30s"
        }}' 2>&1 | tee -a "$LOG_FILE"; then
        echo "✗ ERROR: Failed to configure agent. Check logs: $LOG_FILE" | tee -a "$LOG_FILE"
        exit 1
      fi
      
      echo "✓ Agent configuration applied with 30s keep-alive" | tee -a "$LOG_FILE"
      
      echo "✓ Agent ${each.key} configured successfully" | tee -a "$LOG_FILE"
      echo "Configuration logs saved to: $LOG_FILE"
    EOT
  }

  depends_on = [null_resource.spoke_agent_installation]
}

# CRITICAL FIX: Force agent pod deletion to reset gRPC connections
# This matches the working scripts approach (04-agent-connect.sh:166)
# Ensures fresh connections after principal configuration/restart
resource "null_resource" "spoke_agent_restart" {
  for_each = var.clusters

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -e
      set -o pipefail
      
      LOG_FILE="/tmp/argocd-agent-restart-${each.key}-$$(date +%Y%m%d-%H%M%S).log"
      
      echo "Force restarting agent ${each.key} (deleting pod for fresh gRPC connection)..." | tee -a "$LOG_FILE"
      
      # CRITICAL: Delete pod instead of rollout restart to force complete connection reset
      # This ensures any stale gRPC connections are fully terminated
      echo "Deleting agent pod to force fresh start..." | tee -a "$LOG_FILE"
      kubectl delete pod -l app.kubernetes.io/name=argocd-agent-agent \
        -n ${var.spoke_namespace} \
        --context ${each.value} \
        --ignore-not-found=true 2>&1 | tee -a "$LOG_FILE"
      
      echo "Waiting for agent deployment to create new pod..." | tee -a "$LOG_FILE"
      if ! kubectl wait --for=condition=available --timeout=${var.kubectl_timeout} \
        deployment/argocd-agent-agent \
        -n ${var.spoke_namespace} \
        --context ${each.value} 2>&1 | tee -a "$LOG_FILE"; then
        echo "✗ ERROR: Agent deployment failed. Check logs: $LOG_FILE" | tee -a "$LOG_FILE"
        kubectl describe deployment/argocd-agent-agent -n ${var.spoke_namespace} --context ${each.value} | tee -a "$LOG_FILE"
        exit 1
      fi
      
      echo "✓ Agent ${each.key} restarted with fresh pod" | tee -a "$LOG_FILE"
      
      # Wait additional time for gRPC connection to establish
      echo "Waiting 10 seconds for gRPC connection establishment..." | tee -a "$LOG_FILE"
      sleep 10
      
      echo "Verifying agent pod health and connection..." | tee -a "$LOG_FILE"
      READY_PODS="$$(kubectl get pods -n ${var.spoke_namespace} \
        --context ${each.value} \
        -l app.kubernetes.io/name=argocd-agent-agent \
        -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' 2>&1 | tee -a "$LOG_FILE")"
      
      if [[ "$$READY_PODS" == *"True"* ]]; then
        echo "✓ Agent pod is healthy and ready" | tee -a "$LOG_FILE"
        
        # Check agent logs for successful connection
        echo "Checking agent connection status..." | tee -a "$LOG_FILE"
        AGENT_LOGS="$$(kubectl logs -l app.kubernetes.io/name=argocd-agent-agent \
          -n ${var.spoke_namespace} \
          --context ${each.value} \
          --tail=50 2>&1 | tee -a "$LOG_FILE")"
        
        if echo "$$AGENT_LOGS" | grep -qi "authentication successful\|connected to\|connection established"; then
          echo "✓ Agent successfully connected to principal" | tee -a "$LOG_FILE"
        elif echo "$$AGENT_LOGS" | grep -qi "error\|failed\|EOF"; then
          echo "WARNING: WARNING: Agent may have connection issues. Check logs:" | tee -a "$LOG_FILE"
          echo "  kubectl logs -l app.kubernetes.io/name=argocd-agent-agent -n ${var.spoke_namespace} --context ${each.value}" | tee -a "$LOG_FILE"
        else
          echo "WARNING: Agent connection status unclear. Manual verification recommended." | tee -a "$LOG_FILE"
        fi
      else
        echo "WARNING: WARNING: Agent pod may not be healthy. Check with:" | tee -a "$LOG_FILE"
        echo "  kubectl logs -l app.kubernetes.io/name=argocd-agent-agent -n ${var.spoke_namespace} --context ${each.value}" | tee -a "$LOG_FILE"
      fi
      
      echo "Agent restart logs saved to: $LOG_FILE"
    EOT
  }

  depends_on = [null_resource.spoke_agent_configuration]
}

# =============================================================================
# APPPROJECT CONFIGURATION
# =============================================================================
# =============================================================================
# APPPROJECT CONFIGURATION & SYNCHRONIZATION
# Manages AppProject propagation to agents for managed mode
# =============================================================================

# =============================================================================
# SECTION 1: CONFIGURE DEFAULT APPPROJECT ON HUB
# =============================================================================

# Patch the default AppProject with proper source and destination namespaces
# This is CRITICAL for managed mode agents to sync applications
resource "null_resource" "appproject_default_config" {
  count = var.enable_appproject_sync ? 1 : 0

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      # Build destination configuration based on whether agents exist
      if [ -z "${local.all_agent_names_str}" ] || [ "${local.all_agent_names_str}" = "" ]; then
        # No agents yet - use wildcard
        DEST_SERVER="*"
      else
        # Agents exist - use wildcard for server
        DEST_SERVER="*"
      fi

      # Create AppProject patch file
      cat <<EOF > appproject-patch.yaml
spec:
  sourceNamespaces: ${jsonencode(var.appproject_default_source_namespaces)}
  destinations:
    - name: "*"
      namespace: "*"
      server: "$DEST_SERVER"
EOF

      # Patch default AppProject with proper permissions
      kubectl patch appproject default -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} \
        --type='merge' \
        --patch-file appproject-patch.yaml

      rm appproject-patch.yaml
      echo "✓ Default AppProject configured for managed mode"
EOT
  }

  provisioner "local-exec" {
    when        = destroy
    on_failure  = continue
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      echo "Resetting default AppProject to default configuration..."
      kubectl patch appproject default -n ${self.triggers.hub_namespace} \
        --context ${self.triggers.hub_context} \
        --type='merge' \
        --patch '{"spec":{"sourceNamespaces":["*"],"destinations":[{"namespace":"*","server":"*"}]}}' \
        --ignore-not-found=true || true
      echo "✓ Default AppProject reset"
    EOT
  }

  depends_on = [null_resource.spoke_namespace]

  triggers = {
    source_namespaces = jsonencode(var.appproject_default_source_namespaces)
    dest_namespaces   = jsonencode(var.appproject_default_dest_namespaces)
    hub_namespace     = var.hub_namespace
    hub_context       = var.hub_cluster_context
  }
}

# =============================================================================
# SECTION 2: APPPROJECT PROPAGATION TO AGENTS (Managed Mode)
# =============================================================================

# The default AppProject will be automatically synchronized to agents
# by the ArgoCD Agent framework when agents connect in managed mode.
# This resource documents the process but doesn't need explicit Terraform action.

# Verify AppProject exists on hub before agents connect
resource "null_resource" "appproject_verify" {
  count = var.enable_appproject_sync ? 1 : 0

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      # Wait for AppProject to be ready
      kubectl wait --for=condition=Ready appproject/default \
        -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} \
        --timeout=60s || true

      # Verify AppProject has proper configuration
      APPPROJ=$(kubectl get appproject default -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} \
        -o jsonpath='{.spec.sourceNamespaces}' 2>/dev/null)

      if [ -z "$APPPROJ" ]; then
        echo "WARNING: AppProject configuration not fully applied yet"
        exit 1
      fi

      echo "✓ AppProject verified on hub"
    EOT
  }

  depends_on = [
    null_resource.appproject_default_config,
    null_resource.spoke_argocd_readiness_check
  ]
}

# =============================================================================
# SECTION 3: PER-AGENT APPPROJECT NAMESPACE PREPARATION
# =============================================================================

# Create agent-specific AppProject if custom per-agent restrictions are needed
# By default, the default AppProject is shared across all agents (recommended)



# Optional: Create custom AppProject per agent for finer control
# This is disabled by default - using default AppProject is simpler
resource "null_resource" "appproject_per_agent" {
  for_each = {}

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      # This section can be used for per-agent AppProject customization
      # Currently disabled to use the default AppProject approach
      echo "Per-agent AppProject configuration disabled (using default)"
    EOT
  }

  depends_on = [null_resource.spoke_agent_restart]
}

# =============================================================================
# SECTION 4: APPPROJECT SYNCHRONIZATION VALIDATION
# =============================================================================

# Validate that AppProject syncs to agents after connection
resource "null_resource" "appproject_sync_validation" {
  for_each = var.enable_appproject_sync ? var.clusters : {}

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      # Wait for agent to connect first
      sleep 30

      # Check if AppProject has been synchronized to the agent
      MAX_ATTEMPTS=60
      ATTEMPT=0
      while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
        APPPROJ=$(kubectl get appproject default -n ${var.spoke_namespace} \
          --context ${each.value} \
          -o jsonpath='{.metadata.name}' 2>/dev/null)

        if [ "$APPPROJ" = "default" ]; then
          echo "✓ AppProject synchronized to agent ${each.key}"
          exit 0
        fi

        ATTEMPT=$((ATTEMPT + 1))
        echo "Waiting for AppProject sync to agent ${each.key}... ($ATTEMPT/$MAX_ATTEMPTS)"
        sleep 2
      done

      echo "WARNING: AppProject not yet synchronized to agent ${each.key} (may be normal if agent just connected)"
      exit 0
    EOT
  }

  depends_on = [
    null_resource.spoke_agent_restart,
    null_resource.appproject_default_config
  ]

  triggers = {
    agent = each.key
  }
}

# =============================================================================
# SECTION 5: OUTPUTS
# =============================================================================

output "appproject_default_name" {
  description = "Default AppProject name for managed agents"
  value       = var.enable_appproject_sync ? "default" : null
}

output "appproject_source_namespaces" {
  description = "Allowed source namespaces (repositories) for ApplicationSets"
  value       = var.enable_appproject_sync ? var.appproject_default_source_namespaces : null
}

output "appproject_destinations" {
  description = "Allowed destination servers and namespaces for Applications"
  value = var.enable_appproject_sync ? {
    server    = var.appproject_default_dest_server
    namespace = var.appproject_default_dest_namespaces
  } : null
}

output "appproject_sync_status" {
  description = "AppProject synchronization status instructions"
  value = var.enable_appproject_sync ? format(
    "AppProject 'default' will be automatically synchronized to connected agents. Verify with: kubectl get appproject -n %s --context <agent-context>",
    var.spoke_namespace
  ) : null
}
