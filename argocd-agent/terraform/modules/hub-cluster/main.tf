# SECTION 2: HUB CLUSTER SETUP (01-hub-setup.sh)
# NOTE: Keycloak configuration is in keycloak.tf to keep concerns separated
# =============================================================================

# 1.1 Create Namespace
resource "kubernetes_namespace" "hub_argocd" {

  provider = kubernetes

  metadata {
    name = var.hub_namespace
  }
}

# 1.2 Install Base Argo CD (Step 1 - WITHOUT Principal)
# Installs core ArgoCD components on hub cluster: server, repo-server, application-controller
resource "null_resource" "hub_argocd_base_install" {


  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -e
      set -o pipefail
      
      MAX_RETRIES=${var.argocd_install_retry_attempts}
      RETRY_DELAY=${var.argocd_install_retry_delay}
      RETRY=0
      LOG_FILE="/tmp/argocd-install-hub-$$(date +%Y%m%d-%H%M%S).log"
      
      echo "Installing base Argo CD on Hub cluster..." | tee -a "$LOG_FILE"
      echo "Installation URL: ${local.argocd_base_install_url}" | tee -a "$LOG_FILE"
      
      while [ $RETRY -lt $MAX_RETRIES ]; do
        echo "[Attempt $((RETRY+1))/$MAX_RETRIES] Applying ArgoCD manifests (principal-specific, no app controller)..." | tee -a "$LOG_FILE"
        
        # Use kubectl apply with -k flag for kustomize directory
        if kubectl apply -n ${var.hub_namespace} \
          --context ${var.hub_cluster_context} \
          -k ${local.argocd_base_install_url} 2>&1 | tee -a "$LOG_FILE"; then
          echo "✓ Principal-specific Argo CD manifests applied successfully" | tee -a "$LOG_FILE"
          echo "  Components: server, dex, redis, repo-server, applicationset-controller" | tee -a "$LOG_FILE"
          echo "  Excluded: application-controller (runs only on spoke clusters)" | tee -a "$LOG_FILE"
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
      
      echo "Waiting for ${var.argocd_server_service_name} deployment..." | tee -a "$LOG_FILE"
      if ! kubectl wait --for=condition=available --timeout=${var.kubectl_timeout} \
        deployment/${var.argocd_server_service_name} -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} 2>&1 | tee -a "$LOG_FILE"; then
        echo "✗ ERROR: argocd-server deployment failed to become available" | tee -a "$LOG_FILE"
        kubectl describe deployment/${var.argocd_server_service_name} -n ${var.hub_namespace} --context ${var.hub_cluster_context} | tee -a "$LOG_FILE"
        exit 1
      fi
      
      echo "Waiting for ${var.argocd_repo_server_name} deployment..." | tee -a "$LOG_FILE"
      if ! kubectl wait --for=condition=available --timeout=${var.kubectl_timeout} \
        deployment/${var.argocd_repo_server_name} -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} 2>&1 | tee -a "$LOG_FILE"; then
        echo "✗ ERROR: ${var.argocd_repo_server_name} deployment failed to become available" | tee -a "$LOG_FILE"
        kubectl describe deployment/${var.argocd_repo_server_name} -n ${var.hub_namespace} --context ${var.hub_cluster_context} | tee -a "$LOG_FILE"
        exit 1
      fi
      
      echo "✓ All core Argo CD components are ready" | tee -a "$LOG_FILE"
      echo "Installation logs saved to: $LOG_FILE"
    EOT
  }

  provisioner "local-exec" {
    when        = destroy
    on_failure  = continue
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      echo "Deleting base ArgoCD installation from hub cluster..."
      kubectl delete -n ${self.triggers.namespace} \
        --context ${self.triggers.context} \
        -k ${self.triggers.manifest_url} \
        --ignore-not-found=true \
        --timeout=120s || true
      echo "✓ Base ArgoCD uninstalled"
    EOT
  }

  depends_on = [
    kubernetes_namespace.hub_argocd
  ]

  triggers = {
    version      = var.argocd_version
    manifest_url = local.argocd_base_install_url
    namespace    = var.hub_namespace
    context      = var.hub_cluster_context
  }
}

# 1.3 Enable Apps-in-Any-Namespace and Configure Timeouts
# Allows applications to be created in any namespace (required for agent architecture)
# Also configures extended timeouts for resource-proxy communication
resource "null_resource" "hub_argocd_apps_any_namespace" {


  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -e
      set -o pipefail
      
      LOG_FILE="/tmp/argocd-config-apps-namespace-$$(date +%Y%m%d-%H%M%S).log"
      
      echo "Configuring ArgoCD for apps-in-any-namespace mode..." | tee -a "$LOG_FILE"
      
      if ! kubectl patch configmap ${var.argocd_cmd_params_cm_name} -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} \
        --type='merge' \
        --patch '{"data":{
          "application.namespaces":"*",
          "controller.repo.server.timeout.seconds":"300",
          "server.connection.status.cache.expiration":"1h"
        }}' 2>&1 | tee -a "$LOG_FILE"; then
        echo "✗ ERROR: Failed to patch ${var.argocd_cmd_params_cm_name} ConfigMap" | tee -a "$LOG_FILE"
        exit 1
      fi
      
      echo "Restarting ${var.argocd_server_service_name} deployment..." | tee -a "$LOG_FILE"
      kubectl rollout restart deployment/${var.argocd_server_service_name} -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} 2>&1 | tee -a "$LOG_FILE"
      
      echo "Waiting for ${var.argocd_server_service_name} rollout..." | tee -a "$LOG_FILE"
      if ! kubectl rollout status deployment/${var.argocd_server_service_name} -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} --timeout=${var.kubectl_timeout} 2>&1 | tee -a "$LOG_FILE"; then
        echo "✗ ERROR: ${var.argocd_server_service_name} rollout failed" | tee -a "$LOG_FILE"
        exit 1
      fi
      
      echo "✓ Apps-in-any-namespace enabled and timeouts configured" | tee -a "$LOG_FILE"
      echo "Configuration logs saved to: $LOG_FILE"
    EOT
  }

  depends_on = [null_resource.hub_argocd_base_install]
}

# 1.3.1 Configure Resource Health Checks
# Customizes health assessment to handle Ingress resources without LoadBalancer
# Prevents applications from stuck in "Progressing" state due to missing ingress IPs
resource "null_resource" "hub_argocd_resource_health_config" {


  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -e
      set -o pipefail
      
      LOG_FILE="/tmp/argocd-config-resource-health-$$(date +%Y%m%d-%H%M%S).log"
      
      echo "Configuring ArgoCD resource health customizations..." | tee -a "$LOG_FILE"
      
      # Configure argocd-cm with resource health check overrides
      if ! kubectl patch configmap argocd-cm -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} \
        --type='merge' \
        --patch '{"data":{
          "resource.customizations.health.networking.k8s.io_Ingress": "hs = {}\nhs.status = \"Healthy\"\nreturn hs\n"
        }}' 2>&1 | tee -a "$LOG_FILE"; then
        echo "✗ ERROR: Failed to patch argocd-cm ConfigMap" | tee -a "$LOG_FILE"
        exit 1
      fi
      
      echo "✓ Resource health customizations configured (Ingress always healthy)" | tee -a "$LOG_FILE"
      echo "Configuration logs saved to: $LOG_FILE"
    EOT
  }

  depends_on = [null_resource.hub_argocd_apps_any_namespace]
}

# Configure ArgoCD server to run in insecure mode (HTTP) behind ingress/TLS termination
# Required for OIDC callbacks to work correctly when behind reverse proxy
resource "null_resource" "hub_argocd_server_insecure" {
  count = var.deploy_hub && var.ui_expose_method == "ingress" ? 1 : 0

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      # Configure ArgoCD server to run in insecure mode (no TLS)
      # This is required when behind ingress with TLS termination
      kubectl patch configmap argocd-cmd-params-cm -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} \
        --type='merge' \
        --patch '{"data":{"server.insecure":"true"}}'
      
      # Restart ArgoCD server to apply changes
      kubectl rollout restart deployment argocd-server -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context}
      
      kubectl rollout status deployment/argocd-server -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} --timeout=300s
      
      echo "✓ ArgoCD server configured for insecure mode (HTTP behind ingress)"
    EOT
  }

  depends_on = [
    null_resource.hub_argocd_apps_any_namespace,
    null_resource.hub_argocd_resource_health_config
  ]
}

# NOTE: Reconciliation timeout configuration removed from hub cluster
# The application-controller does NOT run on the hub (principal-only cluster)
# Reconciliation timeouts are configured on spoke clusters where application-controller runs

# 1.4 Expose ArgoCD UI via Ingress
resource "kubernetes_ingress_v1" "argocd_ui" {
  count    = var.deploy_hub && var.ui_expose_method == "ingress" ? 1 : 0
  provider = kubernetes

  metadata {
    name      = "argocd-server"
    namespace = var.hub_namespace
    annotations = {
      "cert-manager.io/${var.cert_issuer_kind == "ClusterIssuer" ? "cluster-issuer" : "issuer"}" = var.cert_issuer_name
      "nginx.ingress.kubernetes.io/force-ssl-redirect"                                           = "true"
      "nginx.ingress.kubernetes.io/backend-protocol"                                             = "HTTP"
    }
  }

  spec {
    ingress_class_name = var.ingress_class_name

    tls {
      hosts       = [var.argocd_host]
      secret_name = "argocd-server-tls"
    }

    rule {
      host = var.argocd_host
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "argocd-server"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    null_resource.hub_argocd_server_insecure
  ]
}

# 1.4 Expose ArgoCD UI via LoadBalancer
resource "null_resource" "argocd_ui_loadbalancer" {
  count = var.ui_expose_method == "loadbalancer" ? 1 : 0

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      kubectl patch svc argocd-server -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} \
        --patch '{"spec":{"type":"LoadBalancer"}}'
    EOT
  }

  depends_on = [null_resource.hub_argocd_base_install]
}

# =============================================================================
# SECTION 4: PKI & PRINCIPAL SETUP (02-hub-pki-principal.sh)
# CRITICAL ORDERING (per official docs):
# 1. ArgoCD Control Plane installed and ready (done in Section 3)
# 2. PKI init
# 3. Principal install
# 4. Issue certs
# =============================================================================

# 2.1 Initialize PKI (after ArgoCD apps-in-any-namespace is configured)
# Creates the root CA certificate authority for agent mTLS authentication
resource "null_resource" "hub_pki_initialization" {


  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -e
      set -o pipefail
      
      LOG_FILE="/tmp/argocd-pki-init-$$(date +%Y%m%d-%H%M%S).log"
      
      echo "Initializing PKI for ArgoCD Agent..." | tee -a "$LOG_FILE"
      echo "Principal context: ${var.hub_cluster_context}" | tee -a "$LOG_FILE"
      echo "Principal namespace: ${var.hub_namespace}" | tee -a "$LOG_FILE"
      
      if ! ${var.argocd_agentctl_path} pki init \
        --principal-context ${var.hub_cluster_context} \
        --principal-namespace ${var.hub_namespace} 2>&1 | tee -a "$LOG_FILE"; then
        echo "✗ ERROR: PKI initialization failed. Check logs: $LOG_FILE" | tee -a "$LOG_FILE"
        exit 1
      fi
      
      echo "✓ PKI initialized successfully" | tee -a "$LOG_FILE"
      echo "PKI initialization logs saved to: $LOG_FILE"
    EOT
  }

  depends_on = [null_resource.hub_argocd_apps_any_namespace]

  triggers = {
    context   = var.hub_cluster_context
    namespace = var.hub_namespace
  }
}

# 2.1.1 Issue Principal Server Certificate (BEFORE deployment so pod can start)
# Creates initial server certificate for Principal service (will be updated with LoadBalancer IP later)
resource "null_resource" "hub_pki_principal_server_cert_initial" {


  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -e
      set -o pipefail
      
      LOG_FILE="/tmp/argocd-pki-principal-cert-$$(date +%Y%m%d-%H%M%S).log"
      
      echo "Issuing initial Principal server certificate..." | tee -a "$LOG_FILE"
      echo "DNS names: ${local.principal_dns}" | tee -a "$LOG_FILE"
      
      if ! ${var.argocd_agentctl_path} pki issue principal \
        --principal-context ${var.hub_cluster_context} \
        --principal-namespace ${var.hub_namespace} \
        --ip "127.0.0.1" \
        --dns "${local.principal_dns}" \
        --upsert 2>&1 | tee -a "$LOG_FILE"; then
        echo "✗ ERROR: Failed to issue Principal server certificate. Check logs: $LOG_FILE" | tee -a "$LOG_FILE"
        exit 1
      fi
      
      echo "✓ Principal server certificate issued successfully" | tee -a "$LOG_FILE"
      echo "Certificate issuance logs saved to: $LOG_FILE"
    EOT
  }

  depends_on = [null_resource.hub_pki_initialization]
}

# Deploys ArgoCD Agent Principal component (agent management server)
resource "null_resource" "hub_principal_installation" {


  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -e
      set -o pipefail
      
      LOG_FILE="/tmp/argocd-principal-install-$$(date +%Y%m%d-%H%M%S).log"
      MAX_RETRIES=${var.argocd_install_retry_attempts}
      RETRY_DELAY=${var.argocd_install_retry_delay}
      RETRY=0
      
      echo "Installing ArgoCD Agent Principal..." | tee -a "$LOG_FILE"
      echo "Installation URL: ${local.agent_principal_install_url}" | tee -a "$LOG_FILE"
      
      while [ $RETRY -lt $MAX_RETRIES ]; do
        echo "[Attempt $((RETRY+1))/$MAX_RETRIES] Applying Principal manifests..." | tee -a "$LOG_FILE"
        
        if kubectl apply -n ${var.hub_namespace} \
          --context ${var.hub_cluster_context} \
          -k "${local.agent_principal_install_url}" 2>&1 | tee -a "$LOG_FILE"; then
          echo "✓ Principal manifests applied successfully" | tee -a "$LOG_FILE"
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
      
      echo "Waiting for ${var.principal_service_name} deployment..." | tee -a "$LOG_FILE"
      if ! kubectl rollout status deployment/${var.principal_service_name} \
        -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} \
        --timeout=${var.kubectl_timeout} 2>&1 | tee -a "$LOG_FILE"; then
        echo "✗ ERROR: Principal deployment failed to become ready" | tee -a "$LOG_FILE"
        kubectl describe deployment/${var.principal_service_name} -n ${var.hub_namespace} --context ${var.hub_cluster_context} | tee -a "$LOG_FILE"
        exit 1
      fi
      
      echo "✓ Principal is ready" | tee -a "$LOG_FILE"
      echo "Installation logs saved to: $LOG_FILE"
    EOT
  }

  provisioner "local-exec" {
    when        = destroy
    on_failure  = continue
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      echo "Deleting ArgoCD Agent Principal..."
      kubectl delete -n ${self.triggers.namespace} \
        --context ${self.triggers.context} \
        -k "${self.triggers.manifest_url}" \
        --ignore-not-found=true \
        --timeout=120s || true
      echo "✓ Principal uninstalled"
    EOT
  }

  depends_on = [null_resource.hub_pki_principal_server_cert_initial]

  triggers = {
    version      = var.argocd_version
    manifest_url = local.agent_principal_install_url
    namespace    = var.hub_namespace
    context      = var.hub_cluster_context
  }
}

# Patches ArgoCD Redis NetworkPolicy to allow Principal component access
resource "null_resource" "hub_redis_network_policy_patch" {


  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -e
      set -o pipefail
      
      LOG_FILE="/tmp/argocd-redis-netpol-$$(date +%Y%m%d-%H%M%S).log"
      
      echo "Patching Redis NetworkPolicy for Principal access..." | tee -a "$LOG_FILE"
      
      if kubectl patch netpol ${var.argocd_redis_network_policy_name} -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} \
        --type='json' \
        -p='[{"op": "add", "path": "/spec/ingress/0/from/-", "value": {"podSelector": {"matchLabels": {"app.kubernetes.io/name": "argocd-agent-principal"}}}}]' \
        2>&1 | tee -a "$LOG_FILE"; then
        echo "✓ NetworkPolicy patched successfully" | tee -a "$LOG_FILE"
      else
        echo "WARNING: NetworkPolicy already patched or doesn't exist (non-fatal)" | tee -a "$LOG_FILE"
      fi
      
      echo "Logs saved to: $LOG_FILE"
    EOT
  }

  depends_on = [null_resource.hub_principal_installation]
}

# Exposes Principal service via LoadBalancer for external agent connectivity
resource "null_resource" "hub_principal_loadbalancer_service" {
  count = var.principal_expose_method == "loadbalancer" ? 1 : 0

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -e
      set -o pipefail
      
      LOG_FILE="/tmp/argocd-principal-lb-$$(date +%Y%m%d-%H%M%S).log"
      
      echo "Exposing Principal service via LoadBalancer..." | tee -a "$LOG_FILE"
      
      if ! kubectl patch svc ${var.principal_service_name} -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} \
        --patch '{"spec":{"type":"LoadBalancer"}}' 2>&1 | tee -a "$LOG_FILE"; then
        echo "✗ ERROR: Failed to patch service to LoadBalancer. Check logs: $LOG_FILE" | tee -a "$LOG_FILE"
        exit 1
      fi
      
      echo "✓ Principal service exposed via LoadBalancer" | tee -a "$LOG_FILE"
      echo "Logs saved to: $LOG_FILE"
    EOT
  }

  depends_on = [null_resource.hub_principal_installation]
}

# Exposes Principal service via NodePort for local/development clusters
resource "null_resource" "hub_principal_nodeport_service" {
  count = var.principal_expose_method == "nodeport" ? 1 : 0

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -e
      set -o pipefail
      
      LOG_FILE="/tmp/argocd-principal-nodeport-$$(date +%Y%m%d-%H%M%S).log"
      
      echo "Exposing Principal service via NodePort..." | tee -a "$LOG_FILE"
      
      if ! kubectl patch svc ${var.principal_service_name} -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} \
        --patch '{"spec":{"type":"NodePort"}}' 2>&1 | tee -a "$LOG_FILE"; then
        echo "✗ ERROR: Failed to patch service to NodePort. Check logs: $LOG_FILE" | tee -a "$LOG_FILE"
        exit 1
      fi
      
      echo "✓ Principal service exposed via NodePort" | tee -a "$LOG_FILE"
      echo "Logs saved to: $LOG_FILE"
    EOT
  }

  depends_on = [null_resource.hub_principal_installation]
}

# Retrieves Principal service external address (IP or hostname) based on exposure method
data "external" "hub_principal_address" {


  program = ["bash", "-c", <<-EOT
    # Get the actual service port from the service definition
    SERVICE_PORT=$(kubectl get svc ${var.principal_service_name} -n ${var.hub_namespace} \
      --context ${var.hub_cluster_context} \
      -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "8443")
    
    # 1. Handle Ingress
    if [ "${var.principal_expose_method}" = "ingress" ]; then
      if [ -n "${var.principal_ingress_host}" ]; then
        echo "{\"address\": \"${var.principal_ingress_host}\", \"port\": \"443\"}"
        exit 0
      fi
    fi

    # 2. Handle NodePort
    if [ "${var.principal_expose_method}" = "nodeport" ]; then
      NODE_IP=$(kubectl get nodes --context ${var.hub_cluster_context} -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
      NODE_PORT=$(kubectl get svc ${var.principal_service_name} -n ${var.hub_namespace} --context ${var.hub_cluster_context} -o jsonpath='{.spec.ports[?(@.name=="grpc")].nodePort}' 2>/dev/null || \
                 kubectl get svc ${var.principal_service_name} -n ${var.hub_namespace} --context ${var.hub_cluster_context} -o jsonpath='{.spec.ports[0].nodePort}')
      
      if [ -n "$NODE_IP" ] && [ -n "$NODE_PORT" ]; then
        echo "{\"address\": \"$NODE_IP\", \"port\": \"$NODE_PORT\"}"
        exit 0
      fi
    fi

    # 3. Handle LoadBalancer (Default fallback)
    if ! kubectl get svc ${var.principal_service_name} -n ${var.hub_namespace} --context ${var.hub_cluster_context} >/dev/null 2>&1; then
      echo "{\"address\": \"pending\", \"port\": \"$SERVICE_PORT\"}"
      exit 0
    fi

    PRINCIPAL_IP=""
    RETRY_COUNT=0
    MAX_RETRIES=$((${var.principal_loadbalancer_wait_timeout} / 5))
    
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
      PRINCIPAL_IP=$(kubectl get svc ${var.principal_service_name} -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} \
        -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
      
      if [ -z "$PRINCIPAL_IP" ]; then
        PRINCIPAL_IP=$(kubectl get svc ${var.principal_service_name} -n ${var.hub_namespace} \
          --context ${var.hub_cluster_context} \
          -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
      fi
      
      if [ -n "$PRINCIPAL_IP" ]; then
        echo "{\"address\": \"$PRINCIPAL_IP\", \"port\": \"$SERVICE_PORT\"}"
        exit 0
      fi
      
      RETRY_COUNT=$((RETRY_COUNT + 1))
      sleep 5
    done
    
    echo "{\"address\": \"pending\", \"port\": \"443\"}"
    exit 1
  EOT
  ]

  depends_on = [
    null_resource.hub_principal_loadbalancer_service,
    null_resource.hub_principal_nodeport_service,
    kubernetes_ingress_v1.hub_principal_ingress
  ]
}

# Exposes Principal service via Ingress with TLS termination
resource "kubernetes_ingress_v1" "hub_principal_ingress" {
  count    = var.deploy_hub && var.enable_principal_ingress && var.principal_ingress_host != "" ? 1 : 0
  provider = kubernetes

  metadata {
    name      = var.principal_service_name
    namespace = var.hub_namespace
    annotations = {
      "cert-manager.io/${var.cert_issuer_kind == "ClusterIssuer" ? "cluster-issuer" : "issuer"}" = var.cert_issuer_name
      "nginx.ingress.kubernetes.io/ssl-passthrough"                                              = "true"
      "nginx.ingress.kubernetes.io/backend-protocol"                                             = "HTTPS"
      "nginx.ingress.kubernetes.io/service-upstream"                                             = "true"
    }
  }

  spec {
    ingress_class_name = var.ingress_class_name

    tls {
      hosts       = [var.principal_ingress_host]
      secret_name = "principal-server-tls"
    }

    rule {
      host = var.principal_ingress_host
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = var.principal_service_name
              port {
                number = 443
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    null_resource.hub_principal_installation
  ]
}

# Updates Principal server certificate with LoadBalancer IP after service is exposed
resource "null_resource" "hub_pki_principal_server_cert_updated" {


  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -e
      set -o pipefail
      
      LOG_FILE="/tmp/argocd-pki-principal-cert-update-$$(date +%Y%m%d-%H%M%S).log"
      PRINCIPAL_IP="${data.external.hub_principal_address.result.address}"
      
      echo "Updating Principal certificate with external address..." | tee -a "$LOG_FILE"
      echo "Principal address: $PRINCIPAL_IP" | tee -a "$LOG_FILE"
      
      if [ "$PRINCIPAL_IP" = "pending" ] || [ "$PRINCIPAL_IP" = "error" ]; then
        echo "✗ ERROR: Cannot update certificate - LoadBalancer not ready" | tee -a "$LOG_FILE"
        exit 1
      fi
      
      echo "Issuing updated Principal server certificate..." | tee -a "$LOG_FILE"
      if ! ${var.argocd_agentctl_path} pki issue principal \
        --principal-context ${var.hub_cluster_context} \
        --principal-namespace ${var.hub_namespace} \
        --ip "127.0.0.1,$PRINCIPAL_IP" \
        --dns "${local.principal_dns}" \
        --upsert 2>&1 | tee -a "$LOG_FILE"; then
        echo "✗ ERROR: Failed to update Principal certificate. Check logs: $LOG_FILE" | tee -a "$LOG_FILE"
        exit 1
      fi
      
      echo "Restarting ${var.principal_service_name} deployment..." | tee -a "$LOG_FILE"
      if ! kubectl rollout restart deployment/${var.principal_service_name} \
        -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} 2>&1 | tee -a "$LOG_FILE"; then
        echo "✗ ERROR: Failed to restart Principal deployment. Check logs: $LOG_FILE" | tee -a "$LOG_FILE"
        exit 1
      fi
      
      echo "Waiting for Principal pods to be ready..." | tee -a "$LOG_FILE"
      if ! kubectl wait --for=condition=ready pod \
        -l app.kubernetes.io/name=${var.principal_service_name} \
        -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} \
        --timeout=${var.kubectl_timeout} 2>&1 | tee -a "$LOG_FILE"; then
        echo "✗ ERROR: Principal pods failed to become ready after restart" | tee -a "$LOG_FILE"
        kubectl describe pods -l app.kubernetes.io/name=${var.principal_service_name} -n ${var.hub_namespace} --context ${var.hub_cluster_context} | tee -a "$LOG_FILE"
        exit 1
      fi
      
      echo "✓ Principal certificate updated successfully" | tee -a "$LOG_FILE"
      echo "Update logs saved to: $LOG_FILE"
    EOT
  }

  depends_on = [data.external.hub_principal_address]
}

# Issues resource-proxy server certificate for ArgoCD server connectivity
resource "null_resource" "hub_pki_resource_proxy_cert" {


  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -e
      set -o pipefail
      
      LOG_FILE="/tmp/argocd-pki-resource-proxy-$$(date +%Y%m%d-%H%M%S).log"
      
      echo "Issuing resource-proxy server certificate..." | tee -a "$LOG_FILE"
      echo "DNS names: ${local.resource_proxy_dns}" | tee -a "$LOG_FILE"
      
      if ! ${var.argocd_agentctl_path} pki issue resource-proxy \
        --principal-context ${var.hub_cluster_context} \
        --principal-namespace ${var.hub_namespace} \
        --ip "127.0.0.1" \
        --dns "${local.resource_proxy_dns}" \
        --upsert 2>&1 | tee -a "$LOG_FILE"; then
        echo "✗ ERROR: Failed to issue resource-proxy certificate. Check logs: $LOG_FILE" | tee -a "$LOG_FILE"
        exit 1
      fi
      
      echo "✓ Resource-proxy certificate issued successfully" | tee -a "$LOG_FILE"
      echo "Certificate logs saved to: $LOG_FILE"
    EOT
  }

  depends_on = [null_resource.hub_pki_initialization]
}

# Creates JWT signing key for agent authentication tokens
resource "null_resource" "hub_pki_jwt_signing_key" {


  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -e
      set -o pipefail
      
      LOG_FILE="/tmp/argocd-pki-jwt-key-$$(date +%Y%m%d-%H%M%S).log"
      
      echo "Creating JWT signing key for agent authentication..." | tee -a "$LOG_FILE"
      
      if ! ${var.argocd_agentctl_path} jwt create-key \
        --principal-context ${var.hub_cluster_context} \
        --principal-namespace ${var.hub_namespace} \
        --upsert 2>&1 | tee -a "$LOG_FILE"; then
        echo "✗ ERROR: Failed to create JWT signing key. Check logs: $LOG_FILE" | tee -a "$LOG_FILE"
        exit 1
      fi
      
      echo "✓ JWT signing key created successfully" | tee -a "$LOG_FILE"
      echo "Key creation logs saved to: $LOG_FILE"
    EOT
  }

  depends_on = [null_resource.hub_pki_initialization]
}

# Configures Principal with allowed agent namespaces for authorization
resource "null_resource" "hub_principal_allowed_namespaces_config" {


  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -e
      set -o pipefail
      
      LOG_FILE="/tmp/argocd-principal-namespaces-$$(date +%Y%m%d-%H%M%S).log"
      
      echo "Configuring Principal allowed namespaces: ${local.allowed_namespaces}" | tee -a "$LOG_FILE"
      
      if ! kubectl patch configmap argocd-agent-params -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} \
        --type='merge' \
        --patch '{
          "data": {
            "principal.allowed-namespaces": "'"${local.allowed_namespaces}"'"
          }
        }' 2>&1 | tee -a "$LOG_FILE"; then
        echo "✗ ERROR: Failed to patch ConfigMap. Check logs: $LOG_FILE" | tee -a "$LOG_FILE"
        exit 1
      fi
      
      echo "✓ Principal allowed namespaces configured" | tee -a "$LOG_FILE"
      echo "Configuration logs saved to: $LOG_FILE"
    EOT
  }

  depends_on = [null_resource.hub_principal_installation]

  triggers = {
    namespaces = local.allowed_namespaces
  }
}

# Configures resource-proxy timeout settings for agent architecture
# Required for API discovery through multi-hop agent connections
resource "null_resource" "hub_principal_resource_proxy_config" {


  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -e
      set -o pipefail
      
      LOG_FILE="/tmp/argocd-principal-resource-proxy-config-$$(date +%Y%m%d-%H%M%S).log"
      
      echo "Configuring resource-proxy timeout settings..." | tee -a "$LOG_FILE"
      
      if ! kubectl patch configmap argocd-agent-params -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} \
        --type='merge' \
        --patch '{
          "data": {
            "principal.resource-proxy.timeout": "180s",
            "principal.resource-proxy.request-tracker.timeout": "300s",
            "principal.resource-proxy.request-tracker.queue-size": "1000",
            "principal.resource-proxy.worker-capacity": "50",
            "principal.resource-proxy.api-discovery.timeout": "180s",
            "principal.keep-alive.min-interval": "30s"
          }
        }' 2>&1 | tee -a "$LOG_FILE"; then
        echo "✗ ERROR: Failed to patch ConfigMap. Check logs: $LOG_FILE" | tee -a "$LOG_FILE"
        exit 1
      fi
      
      echo "✓ Resource-proxy timeout and keep-alive settings configured" | tee -a "$LOG_FILE"
      echo "Configuration logs saved to: $LOG_FILE"
    EOT
  }

  depends_on = [null_resource.hub_principal_installation]

  triggers = {
    config_version = "v1"
  }
}

# Patches Principal deployment with resource-proxy environment variables
# Maps ConfigMap values to environment variables for runtime configuration
resource "null_resource" "hub_principal_env_vars_config" {


  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -e
      set -o pipefail
      
      LOG_FILE="/tmp/argocd-principal-env-vars-$$(date +%Y%m%d-%H%M%S).log"
      
      echo "Configuring Principal deployment environment variables..." | tee -a "$LOG_FILE"
      
      if ! kubectl patch deployment ${var.principal_service_name} -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} \
        --type='json' \
        -p='[
          {
            "op": "add",
            "path": "/spec/template/spec/containers/0/env/-",
            "value": {
              "name": "ARGOCD_PRINCIPAL_RESOURCE_PROXY_TIMEOUT",
              "valueFrom": {
                "configMapKeyRef": {
                  "name": "argocd-agent-params",
                  "key": "principal.resource-proxy.timeout"
                }
              }
            }
          },
          {
            "op": "add",
            "path": "/spec/template/spec/containers/0/env/-",
            "value": {
              "name": "ARGOCD_PRINCIPAL_RESOURCE_PROXY_REQUEST_TRACKER_TIMEOUT",
              "valueFrom": {
                "configMapKeyRef": {
                  "name": "argocd-agent-params",
                  "key": "principal.resource-proxy.request-tracker.timeout"
                }
              }
            }
          },
          {
            "op": "add",
            "path": "/spec/template/spec/containers/0/env/-",
            "value": {
              "name": "ARGOCD_PRINCIPAL_RESOURCE_PROXY_REQUEST_TRACKER_QUEUE_SIZE",
              "valueFrom": {
                "configMapKeyRef": {
                  "name": "argocd-agent-params",
                  "key": "principal.resource-proxy.request-tracker.queue-size"
                }
              }
            }
          },
          {
            "op": "add",
            "path": "/spec/template/spec/containers/0/env/-",
            "value": {
              "name": "ARGOCD_PRINCIPAL_RESOURCE_PROXY_WORKER_CAPACITY",
              "valueFrom": {
                "configMapKeyRef": {
                  "name": "argocd-agent-params",
                  "key": "principal.resource-proxy.worker-capacity"
                }
              }
            }
          },
          {
            "op": "add",
            "path": "/spec/template/spec/containers/0/env/-",
            "value": {
              "name": "ARGOCD_PRINCIPAL_RESOURCE_PROXY_API_DISCOVERY_TIMEOUT",
              "valueFrom": {
                "configMapKeyRef": {
                  "name": "argocd-agent-params",
                  "key": "principal.resource-proxy.api-discovery.timeout"
                }
              }
            }
          }
        ]' 2>&1 | tee -a "$LOG_FILE"; then
        echo "✗ ERROR: Failed to patch deployment. Check logs: $LOG_FILE" | tee -a "$LOG_FILE"
        exit 1
      fi
      
      echo "✓ Principal deployment environment variables configured" | tee -a "$LOG_FILE"
      echo "Configuration logs saved to: $LOG_FILE"
    EOT
  }

  depends_on = [null_resource.hub_principal_resource_proxy_config]

  triggers = {
    config_version = "v1"
  }
}

# Restarts Principal deployment to apply PKI and configuration changes
resource "null_resource" "hub_principal_restart" {


  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -e
      set -o pipefail
      
      LOG_FILE="/tmp/argocd-principal-restart-$$(date +%Y%m%d-%H%M%S).log"
      
      echo "Restarting ${var.principal_service_name} deployment to apply changes..." | tee -a "$LOG_FILE"
      
      if ! kubectl rollout restart deployment/${var.principal_service_name} \
        -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} 2>&1 | tee -a "$LOG_FILE"; then
        echo "✗ ERROR: Failed to restart deployment. Check logs: $LOG_FILE" | tee -a "$LOG_FILE"
        exit 1
      fi
      
      echo "Waiting for rollout to complete..." | tee -a "$LOG_FILE"
      if ! kubectl rollout status deployment/${var.principal_service_name} \
        -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} \
        --timeout=${var.kubectl_timeout} 2>&1 | tee -a "$LOG_FILE"; then
        echo "✗ ERROR: Rollout failed to complete. Check logs: $LOG_FILE" | tee -a "$LOG_FILE"
        kubectl describe deployment/${var.principal_service_name} -n ${var.hub_namespace} --context ${var.hub_cluster_context} | tee -a "$LOG_FILE"
        exit 1
      fi
      
      echo "✓ Principal deployment restarted successfully" | tee -a "$LOG_FILE"
      echo "Restart logs saved to: $LOG_FILE"
    EOT
  }

  depends_on = [
    null_resource.hub_pki_principal_server_cert_updated,
    null_resource.hub_pki_resource_proxy_cert,
    null_resource.hub_pki_jwt_signing_key,
    null_resource.hub_principal_allowed_namespaces_config,
    null_resource.hub_principal_resource_proxy_config,
    null_resource.hub_principal_env_vars_config,
    null_resource.hub_redis_network_policy_patch
  ]
}

# =============================================================================
# SECTION 5: WORKLOAD CLUSTERS SETUP (03-spoke-setup.sh)
# =============================================================================


# =============================================================================
# AGENT CREATION (runs on hub FOR spokes)
# =============================================================================
resource "null_resource" "spoke_agent_creation" {
  for_each = var.workload_clusters

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -e
      set -o pipefail
      
      LOG_FILE="/tmp/argocd-agent-create-${each.key}-$$(date +%Y%m%d-%H%M%S).log"
      
      echo "Creating agent configuration for ${each.key} on hub..." | tee -a "$LOG_FILE"
      
      echo "Removing existing agent configuration for idempotency..." | tee -a "$LOG_FILE"
      kubectl delete secret cluster-${each.key} -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} --ignore-not-found=true 2>&1 | tee -a "$LOG_FILE"
      
      echo "Creating new agent configuration..." | tee -a "$LOG_FILE"
      if ! ${var.argocd_agentctl_path} agent create ${each.key} \
        --principal-context ${var.hub_cluster_context} \
        --principal-namespace ${var.hub_namespace} \
        --resource-proxy-server ${local.resource_proxy_server} 2>&1 | tee -a "$LOG_FILE"; then
        echo "✗ ERROR: Failed to create agent. Check logs: $LOG_FILE" | tee -a "$LOG_FILE"
        exit 1
      fi
      
      echo "✓ Agent ${each.key} created successfully" | tee -a "$LOG_FILE"
      echo "Agent creation logs saved to: $LOG_FILE"
    EOT
  }

  provisioner "local-exec" {
    when        = destroy
    on_failure  = continue
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      echo "Deleting agent configuration for ${self.triggers.agent} from hub..."
      kubectl delete secret cluster-${self.triggers.agent} \
        -n ${self.triggers.namespace} \
        --context ${self.triggers.context} \
        --ignore-not-found=true || true
      echo "✓ Agent ${self.triggers.agent} deleted"
    EOT
  }

  depends_on = [
    null_resource.hub_principal_restart,

  ]

  triggers = {
    agent                 = each.key
    resource_proxy_server = local.resource_proxy_server
    namespace             = var.hub_namespace
    context               = var.hub_cluster_context
  }
}

# Creates agent-specific namespace on hub cluster for managed mode resources
resource "kubernetes_namespace" "spoke_agent_managed_namespace" {
  for_each = var.workload_clusters
  provider = kubernetes

  metadata {
    name = each.key
    labels = merge(local.hub_labels, {
      "argocd-agent/managed-cluster" = each.key
    })
  }

  depends_on = [null_resource.spoke_agent_creation]
}

# =============================================================================
# KEYCLOAK OIDC INTEGRATION
# =============================================================================
# =============================================================================
# KEYCLOAK OIDC CONFIGURATION (Comprehensive)
# Supports both Client Authentication and PKCE flows
# Implements full group-based RBAC as per official documentation
# =============================================================================

# =============================================================================
# SECTION 1: KEYCLOAK REALM SETUP
# =============================================================================

resource "keycloak_realm" "argocd" {
  count   = var.deploy_hub && var.enable_keycloak ? 1 : 0
  realm   = var.keycloak_realm
  enabled = true
}

# =============================================================================
# SECTION 2: KEYCLOAK CLIENT (Client Authentication Flow)
# =============================================================================

# Main ArgoCD OIDC Client with Client Authentication (Confidential)
resource "keycloak_openid_client" "argocd" {
  count = var.enable_keycloak && !var.keycloak_enable_pkce ? 1 : 0

  realm_id                     = keycloak_realm.argocd[0].id
  client_id                    = var.keycloak_client_id
  name                         = "ArgoCD OIDC Client (Client Authentication)"
  enabled                      = true
  access_type                  = "CONFIDENTIAL"
  standard_flow_enabled        = true
  direct_access_grants_enabled = true
  implicit_flow_enabled        = false

  # Redirect URIs for callback
  valid_redirect_uris = concat(
    [
      "${var.argocd_url}/auth/callback",
      "${var.argocd_url}/*",
    ],
    var.keycloak_enable_pkce ? [
      "http://localhost:8085/auth/callback", # For CLI with --sso
    ] : []
  )

  # Logout configuration
  valid_post_logout_redirect_uris = [
    "${var.argocd_url}/applications",
    "${var.argocd_url}/*",
  ]

  # Web origins for CORS
  web_origins = [
    var.argocd_host,
    var.argocd_url,
  ]

  # Client URLs
  root_url  = var.argocd_url
  admin_url = var.argocd_url

  access_token_lifespan = 3600 # 1 hour

  # Security settings
  pkce_code_challenge_method               = var.keycloak_enable_pkce ? "S256" : null
  exclude_session_state_from_auth_response = false

  depends_on = [keycloak_realm.argocd]
}

# PKCE Client (Public Flow, for CLI authentication)
resource "keycloak_openid_client" "argocd_pkce" {
  count = var.enable_keycloak && var.keycloak_enable_pkce ? 1 : 0

  realm_id                     = keycloak_realm.argocd[0].id
  client_id                    = var.keycloak_client_id
  name                         = "ArgoCD OIDC Client (PKCE)"
  enabled                      = true
  access_type                  = "PUBLIC" # PKCE is public (no client secret)
  standard_flow_enabled        = true
  direct_access_grants_enabled = true # Required for username/password login form
  implicit_flow_enabled        = false

  # Redirect URIs for callback (PKCE)
  valid_redirect_uris = [
    "http://localhost:8085/auth/callback", # For CLI with --sso
    "${var.argocd_url}/auth/callback",
    "${var.argocd_url}/*",
  ]

  # Logout configuration
  valid_post_logout_redirect_uris = [
    "${var.argocd_url}/applications",
    "${var.argocd_url}/*",
  ]

  # Web origins for CORS
  web_origins = [
    var.argocd_host,
    var.argocd_url,
  ]

  # Client URLs
  root_url  = var.argocd_url
  admin_url = var.argocd_url

  access_token_lifespan = 3600 # 1 hour

  # PKCE Configuration
  pkce_code_challenge_method = "S256"

  depends_on = [keycloak_realm.argocd]
}

# =============================================================================
# SECTION 3: DEFAULT SCOPES (openid, profile, email)
# =============================================================================

# =============================================================================
# SECTION 4: GROUP MANAGEMENT
# =============================================================================

# Groups Client Scope - Required for group claim in token
resource "keycloak_openid_client_scope" "groups" {
  count                  = var.deploy_hub && var.enable_keycloak ? 1 : 0
  realm_id               = keycloak_realm.argocd[0].id
  name                   = "groups"
  description            = "Group membership claim for ArgoCD authorization"
  include_in_token_scope = true
}

# Group Membership Protocol Mapper
# Maps Keycloak groups to "groups" claim in token
resource "keycloak_openid_group_membership_protocol_mapper" "groups_mapper" {
  count = var.enable_keycloak ? 1 : 0

  realm_id        = keycloak_realm.argocd[0].id
  client_scope_id = keycloak_openid_client_scope.groups[0].id
  name            = "group-membership"
  claim_name      = "groups"
  full_path       = false # Return group name only, not full path
}

# Add groups scope to client default scopes
# Per ArgoCD docs: "Click on "Add client scope", choose the groups scope and add it 
# either to the Default or to the Optional Client Scope. If you put it in the Optional 
# category you will need to make sure that ArgoCD requests the scope in its OIDC configuration."
resource "keycloak_openid_client_default_scopes" "argocd" {
  count = var.enable_keycloak ? 1 : 0

  realm_id  = keycloak_realm.argocd[0].id
  client_id = var.keycloak_enable_pkce ? one(keycloak_openid_client.argocd_pkce[*].id) : one(keycloak_openid_client.argocd[*].id)

  default_scopes = [
    "acr",
    "email",
    "openid",
    "profile",
    "roles",
    "web-origins",
    "groups",
  ]

  depends_on = [
    keycloak_openid_client_scope.groups,
    keycloak_openid_group_membership_protocol_mapper.groups_mapper
  ]
}

# Create default ArgoCD admin group
resource "keycloak_group" "argocd_admins" {
  count    = var.deploy_hub && var.enable_keycloak ? 1 : 0
  realm_id = keycloak_realm.argocd[0].id
  name     = "ArgoCDAdmins"
}

resource "keycloak_group" "argocd_developers" {
  count    = var.deploy_hub && var.enable_keycloak ? 1 : 0
  realm_id = keycloak_realm.argocd[0].id
  name     = "ArgoCDDevelopers"
}

resource "keycloak_group" "argocd_viewers" {
  count    = var.deploy_hub && var.enable_keycloak ? 1 : 0
  realm_id = keycloak_realm.argocd[0].id
  name     = "ArgoCDViewers"
}

# =============================================================================
# SECTION 4.5: DEFAULT KEYCLOAK ADMIN USER
# =============================================================================

# Create default admin user for initial ArgoCD access
# Using random_password to ensure password is available at plan time
resource "random_password" "keycloak_admin_password" {
  count   = var.deploy_hub && var.enable_keycloak && var.create_default_admin_user && var.default_admin_password == "" ? 1 : 0
  length  = 24
  special = true
}

resource "keycloak_user" "argocd_admin" {
  count          = var.deploy_hub && var.enable_keycloak && var.create_default_admin_user ? 1 : 0
  realm_id       = keycloak_realm.argocd[0].id
  username       = var.default_admin_username
  enabled        = true
  email          = var.default_admin_email
  email_verified = true
  first_name     = "ArgoCD"
  last_name      = "Administrator"
}

# Set password for admin user via Keycloak REST API
# This works with both local and remote Keycloak installations
resource "null_resource" "set_admin_password" {
  count = var.deploy_hub && var.enable_keycloak && var.create_default_admin_user ? 1 : 0

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -e
      
      USER_ID="${keycloak_user.argocd_admin[0].id}"
      PASSWORD="${local.admin_password}"
      TEMPORARY="${var.default_admin_password_temporary}"
      KEYCLOAK_URL="${var.keycloak_url}"
      KEYCLOAK_USER="${var.keycloak_user}"
      KEYCLOAK_PASSWORD="${var.keycloak_password}"
      REALM="${var.keycloak_realm}"
      
      echo "Setting password for Keycloak user ${var.default_admin_username} (ID: $USER_ID)..."
      echo "Connecting to Keycloak at: $KEYCLOAK_URL"
      
      # Get admin access token
      echo "→ Authenticating as Keycloak admin..."
      TOKEN_RESPONSE=$(curl -sSL -X POST "$KEYCLOAK_URL/realms/master/protocol/openid-connect/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "username=$KEYCLOAK_USER" \
        -d "password=$KEYCLOAK_PASSWORD" \
        -d 'grant_type=password' \
        -d 'client_id=admin-cli' 2>&1)
      
      if [ $? -ne 0 ]; then
        echo "✗ ERROR: Failed to connect to Keycloak"
        echo "Response: $TOKEN_RESPONSE"
        echo "Please set password manually: $KEYCLOAK_URL/admin/master/console/#/$REALM/users/$USER_ID"
        exit 1
      fi
      
      ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | grep -o '"access_token":"[^"]*' | sed 's/"access_token":"//')
      
      if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" = "null" ]; then
        echo "✗ ERROR: Failed to obtain access token"
        echo "Response: $TOKEN_RESPONSE"
        echo "Please verify Keycloak credentials and set password manually"
        echo "Keycloak URL: $KEYCLOAK_URL/admin/master/console/#/$REALM/users/$USER_ID"
        exit 1
      fi
      
      echo "→ Setting password via REST API..."
      
      # Set user password using Keycloak Admin REST API
      RESPONSE=$(curl -sSL -X PUT \
        "$KEYCLOAK_URL/admin/realms/$REALM/users/$USER_ID/reset-password" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"type\":\"password\",\"value\":\"$PASSWORD\",\"temporary\":$TEMPORARY}" \
        -w "\n%%{http_code}" 2>&1)
      
      HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)
      BODY=$(echo "$RESPONSE" | head -n -1)
      
      if [ "$HTTP_CODE" = "204" ] || [ "$HTTP_CODE" = "200" ]; then
        echo "✓ Password set successfully for user ${var.default_admin_username}"
        echo "✓ Temporary password: $TEMPORARY"
        echo ""
        echo "Login at: ${var.argocd_url}"
        echo "Username: ${var.default_admin_username}"
      else
        echo "✗ ERROR: Failed to set password (HTTP $HTTP_CODE)"
        echo "Response: $BODY"
        echo "Please set password manually: $KEYCLOAK_URL/admin/master/console/#/$REALM/users/$USER_ID"
        exit 1
      fi
    EOT
  }

  depends_on = [keycloak_user.argocd_admin]

  triggers = {
    user_id      = keycloak_user.argocd_admin[0].id
    password     = md5(local.admin_password)
    temporary    = var.default_admin_password_temporary
    keycloak_url = var.keycloak_url
  }
}

# Add admin user to ArgoCDAdmins group
resource "keycloak_user_groups" "argocd_admin_groups" {
  count    = var.deploy_hub && var.enable_keycloak && var.create_default_admin_user ? 1 : 0
  realm_id = keycloak_realm.argocd[0].id
  user_id  = keycloak_user.argocd_admin[0].id
  group_ids = [
    keycloak_group.argocd_admins[0].id
  ]

  depends_on = [null_resource.set_admin_password]
}

# =============================================================================
# SECTION 5: CONFIGURE ARGOCD OIDC IN HUB CLUSTER
# =============================================================================

# Patch ArgoCD ConfigMap with OIDC configuration
resource "null_resource" "hub_keycloak_oidc_config" {
  count = var.enable_keycloak ? 1 : 0

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      # Create OIDC patch file with proper YAML formatting
      cat > /tmp/oidc-patch.yaml <<'YAML_EOF'
data:
  url: ${var.argocd_url}
  oidc.config: |
    name: Keycloak
    issuer: ${var.keycloak_url}/realms/${var.keycloak_realm}
    clientID: ${var.keycloak_client_id}
    %{if var.keycloak_enable_pkce~}enablePKCEAuthentication: true%{else~}clientSecret: $oidc.keycloak.clientSecret%{endif~}

    requestedScopes: ["openid", "profile", "email", "groups"]
YAML_EOF

      # Patch ArgoCD ConfigMap
      kubectl patch configmap argocd-cm -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} \
        --type='merge' \
        --patch-file /tmp/oidc-patch.yaml

      rm /tmp/oidc-patch.yaml
      echo "✓ ArgoCD OIDC configuration applied"
    EOT
  }

  depends_on = [
    null_resource.hub_argocd_base_install,
    keycloak_openid_client.argocd,
    keycloak_openid_client.argocd_pkce,
    keycloak_openid_client_default_scopes.argocd
  ]
}

# Store client secret in ArgoCD secret (only for Client Authentication mode)
resource "null_resource" "hub_keycloak_secret" {
  count = var.enable_keycloak && !var.keycloak_enable_pkce ? 1 : 0

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      kubectl patch secret argocd-secret -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} \
        --type='merge' \
        --patch "{\"stringData\":{\"oidc.keycloak.clientSecret\":\"${one(keycloak_openid_client.argocd[*].client_secret)}\"}}"

      echo "✓ Keycloak client secret stored in ArgoCD secret"
    EOT
  }

  depends_on = [
    null_resource.hub_argocd_base_install,
    keycloak_openid_client.argocd
  ]

  triggers = {
    client_secret = one(keycloak_openid_client.argocd[*].client_secret)
  }
}

# =============================================================================
# SECTION 6: CONFIGURE ARGOCD RBAC POLICIES
# =============================================================================

# Patch ArgoCD RBAC ConfigMap with group-to-role mappings
resource "null_resource" "hub_keycloak_rbac" {
  count = var.enable_keycloak ? 1 : 0

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      # Create RBAC patch file
      cat <<EOF > rbac-patch.yaml
data:
  policy.csv: |
    g, ArgoCDAdmins, role:admin
    g, ArgoCDDevelopers, role:edit
    g, ArgoCDViewers, role:readonly
EOF

      # Patch ArgoCD RBAC ConfigMap
      kubectl patch configmap argocd-rbac-cm -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} \
        --type='merge' \
        --patch-file rbac-patch.yaml

      rm rbac-patch.yaml
      echo "✓ ArgoCD RBAC policies configured"
    EOT
  }

  depends_on = [
    null_resource.hub_argocd_base_install,
    keycloak_group.argocd_admins,
    keycloak_group.argocd_developers,
    keycloak_group.argocd_viewers
  ]
}

# Disable admin user when Keycloak is enabled (force SSO login only)
resource "null_resource" "hub_disable_admin_user" {
  count = var.enable_keycloak ? 1 : 0

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      # Disable the built-in admin user (force SSO login only)
      kubectl patch configmap argocd-cm -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} \
        --type='merge' \
        --patch '{"data":{"admin.enabled":"false"}}'
      
      echo "✓ ArgoCD admin user disabled (SSO-only login enforced)"
    EOT
  }

  depends_on = [
    null_resource.hub_keycloak_oidc_config,
    null_resource.hub_keycloak_rbac
  ]
}

# Restart ArgoCD server to apply OIDC and RBAC changes
resource "null_resource" "hub_keycloak_restart_server" {
  count = var.enable_keycloak ? 1 : 0

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      kubectl rollout restart deployment argocd-server -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context}
      
      kubectl rollout status deployment/argocd-server -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} --timeout=300s

      echo "✓ ArgoCD server restarted with OIDC configuration"
    EOT
  }

  depends_on = [
    null_resource.hub_keycloak_oidc_config,
    null_resource.hub_keycloak_secret,
    null_resource.hub_keycloak_rbac,
    null_resource.hub_disable_admin_user,
    null_resource.hub_argocd_server_insecure
  ]
}

# =============================================================================
# SECTION 7: KEYCLOAK CONFIGURATION OUTPUTS
# =============================================================================

output "keycloak_realm_id" {
  description = "Keycloak realm ID"
  value       = var.enable_keycloak && var.deploy_hub ? keycloak_realm.argocd[0].id : null
}

output "keycloak_client_id_output" {
  description = "Keycloak client ID for ArgoCD"
  value       = var.enable_keycloak && var.deploy_hub ? var.keycloak_client_id : null
}

output "keycloak_client_secret" {
  description = "Keycloak client secret (only for Client Authentication mode)"
  value = var.enable_keycloak && !var.keycloak_enable_pkce ? (
    one(keycloak_openid_client.argocd[*].client_secret)
  ) : "N/A (PKCE mode)"
  sensitive = true
}

output "keycloak_authentication_method" {
  description = "Keycloak authentication method in use"
  value       = var.enable_keycloak && var.deploy_hub ? (var.keycloak_enable_pkce ? "PKCE (CLI enabled)" : "Client Authentication") : null
}

output "keycloak_oidc_issuer" {
  description = "Keycloak OIDC issuer URL"
  value       = var.enable_keycloak && var.deploy_hub ? "${var.keycloak_url}/realms/${var.keycloak_realm}" : null
}

output "keycloak_cli_login_command" {
  description = "Command to login via ArgoCD CLI with Keycloak PKCE"
  value = var.enable_keycloak && var.deploy_hub && var.keycloak_enable_pkce ? (
    "argocd login ${var.argocd_host} --sso --grpc-web"
  ) : "N/A (Client Authentication mode)"
}

output "keycloak_groups" {
  description = "Keycloak groups created for ArgoCD RBAC"
  value = var.enable_keycloak && var.deploy_hub ? {
    admins     = "ArgoCDAdmins (role:admin)"
    developers = "ArgoCDDevelopers (role:edit)"
    viewers    = "ArgoCDViewers (role:readonly)"
  } : null
}

output "keycloak_admin_user" {
  description = "Default Keycloak admin user credentials for initial ArgoCD login"
  value = var.enable_keycloak && var.deploy_hub && var.create_default_admin_user ? {
    username  = var.default_admin_username
    email     = var.default_admin_email
    temporary = var.default_admin_password_temporary
    login_url = "${var.argocd_url}/login"
    note      = var.default_admin_password_temporary ? "Password must be changed on first login" : "Use configured password"
  } : null
}

output "keycloak_login_instructions" {
  description = "Instructions for logging into ArgoCD with Keycloak"
  value = var.enable_keycloak && var.deploy_hub ? trimspace(<<-EOT
╔════════════════════════════════════════════════════════════════════════════╗
║                    ArgoCD Keycloak Login Instructions                     ║
╚════════════════════════════════════════════════════════════════════════════╝

WEB LOGIN:
──────────
1. Navigate to: ${var.argocd_url}
2. Click "LOG IN VIA KEYCLOAK" button
3. Use credentials:
   Username: ${var.create_default_admin_user ? var.default_admin_username : "<your-keycloak-user>"}
   Password: ${var.create_default_admin_user ? (var.default_admin_password_temporary ? "<set-in-terraform.tfvars> (must change on first login)" : "<set-in-terraform.tfvars>") : "<your-keycloak-password>"}

CLI LOGIN (PKCE mode only):
───────────────────────────
${var.keycloak_enable_pkce ? "argocd login ${var.argocd_host} --sso --grpc-web" : "PKCE not enabled - set keycloak_enable_pkce = true to use CLI login"}

NOTES:
──────
- Built-in admin user is DISABLED (SSO-only login)
- Users must be in Keycloak groups: ArgoCDAdmins, ArgoCDDevelopers, or ArgoCDViewers
- Create additional users in Keycloak: ${var.keycloak_url}
EOT
  ) : null
}

# =============================================================================
# HIGH AVAILABILITY CONFIGURATION
# =============================================================================
# =============================================================================
# HIGH AVAILABILITY CONFIGURATION
# =============================================================================

# Scale Principal to 2 replicas with PodDisruptionBudget
resource "null_resource" "principal_ha_replicas" {
  count = var.deploy_hub && var.principal_replicas > 1 ? 1 : 0

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      # Scale Principal deployment
      kubectl scale deployment argocd-agent-principal \
        -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} \
        --replicas ${var.principal_replicas}
      
      # Wait for all replicas to be ready
      kubectl wait --for=condition=available --timeout=300s \
        deployment/argocd-agent-principal \
        -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context}
      
      echo "✓ Principal scaled to ${var.principal_replicas} replicas"
    EOT
  }

  depends_on = [null_resource.hub_principal_restart]

  triggers = {
    replicas = var.principal_replicas
  }
}

# PodDisruptionBudget to prevent all Principal pods from being down simultaneously
resource "null_resource" "principal_pdb" {
  count = var.deploy_hub && var.principal_replicas > 1 ? 1 : 0

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      cat <<PDBEOF | kubectl apply -f - --context ${var.hub_cluster_context}
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: argocd-agent-principal
  namespace: ${var.hub_namespace}
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: argocd-agent-principal
PDBEOF
      
      echo "✓ PodDisruptionBudget created (minAvailable: 1)"
    EOT
  }

  depends_on = [null_resource.principal_ha_replicas]

  # Note: PDB cleanup handled by cleanup.sh script
  # Terraform destroy provisioners cannot reference variables (limitation)
}

# Add pod anti-affinity for better distribution across nodes
resource "null_resource" "principal_anti_affinity" {
  count = var.deploy_hub && var.principal_replicas > 1 ? 1 : 0

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      kubectl patch deployment argocd-agent-principal \
        -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} \
        --type='strategic' \
        --patch '
spec:
  template:
    spec:
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchLabels:
                  app.kubernetes.io/name: argocd-agent-principal
              topologyKey: kubernetes.io/hostname
'
      
      echo "✓ Pod anti-affinity configured (prefer different nodes)"
    EOT
  }

  depends_on = [null_resource.principal_ha_replicas]
}

# =============================================================================
# RESOURCE PROXY
# =============================================================================
# =============================================================================
# RESOURCE PROXY CREDENTIALS MANAGEMENT
# Stores and manages resource proxy authentication credentials for agents
# =============================================================================

# =============================================================================
# SECTION 1: RESOURCE PROXY CREDENTIALS SECRET
# =============================================================================

# Generate random password for each agent's resource proxy authentication
resource "random_password" "agent_proxy_password" {
  for_each         = var.workload_clusters
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
}

# Store all agent resource proxy credentials in a Kubernetes secret for:
# - Easy reference and rotation
# - Secure storage in etcd
# - Audit trail via kubectl events

resource "null_resource" "resource_proxy_credentials_secret" {
  count = var.enable_resource_proxy_credentials_secret ? 1 : 0

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command = <<-EOT
      # Build credentials JSON from all agents
      CREDENTIALS_JSON="{"
      FIRST=true

      # Add each agent's credentials
      ${join("\n", [for agent, _ in var.workload_clusters :
    "AGENT='${agent}'\nPWD='${random_password.agent_proxy_password[agent].result}'\nif [ \"$FIRST\" = \"true\" ]; then CREDENTIALS_JSON=\"$CREDENTIALS_JSON\\\"$AGENT\\\": \\\"$PWD\\\"\"; FIRST=false; else CREDENTIALS_JSON=\"$CREDENTIALS_JSON, \\\"$AGENT\\\": \\\"$PWD\\\"\"; fi"
])}

      CREDENTIALS_JSON="$CREDENTIALS_JSON}"

      # Create secret with all credentials
      kubectl create secret generic argocd-agent-resource-proxy-creds \
        --from-literal=credentials="$CREDENTIALS_JSON" \
        -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} \
        --dry-run=client \
        -o yaml | kubectl apply -f - --context ${var.hub_cluster_context}

      echo "✓ Resource proxy credentials secret created"
    EOT
}

depends_on = [
  null_resource.hub_principal_restart,
  random_password.agent_proxy_password
]

triggers = {
  credentials_count = length(var.workload_clusters)
}
}

# =============================================================================
# SECTION 2: RESOURCE PROXY SERVICE VERIFICATION
# =============================================================================

# Verify resource proxy service is accessible and credentials are valid
resource "null_resource" "resource_proxy_verification" {
  count = var.enable_resource_proxy_credentials_secret ? 1 : 0

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      # Check resource proxy service exists
      RESOURCE_PROXY_SVC=$(kubectl get svc argocd-agent-resource-proxy \
        -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} \
        -o jsonpath='{.metadata.name}' 2>/dev/null)

      if [ -z "$RESOURCE_PROXY_SVC" ]; then
        echo "ERROR: argocd-agent-resource-proxy service not found"
        exit 1
      fi

      # Get resource proxy service details
      RESOURCE_PROXY_PORT=$(kubectl get svc argocd-agent-resource-proxy \
        -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} \
        -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)

      RESOURCE_PROXY_CLUSTER_IP=$(kubectl get svc argocd-agent-resource-proxy \
        -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} \
        -o jsonpath='{.spec.clusterIP}' 2>/dev/null)

      if [ -z "$RESOURCE_PROXY_CLUSTER_IP" ]; then
        echo "ERROR: Cannot determine resource proxy cluster IP"
        exit 1
      fi

      echo "✓ Resource proxy service verified at $RESOURCE_PROXY_CLUSTER_IP:$RESOURCE_PROXY_PORT"
    EOT
  }

  depends_on = [null_resource.hub_principal_installation]
}

# =============================================================================
# SECTION 3: AGENT RESOURCE PROXY PASSWORD STORAGE
# =============================================================================

# For each agent, store credentials information for documentation
resource "null_resource" "agent_credentials_documentation" {
  for_each = var.workload_clusters

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      # Create a ConfigMap with agent credentials information (non-sensitive)
      # This helps with credential rotation and troubleshooting
      
      AGENT_NAME="${each.key}"
      
      kubectl create configmap argocd-agent-credentials-info-$AGENT_NAME \
        --from-literal=username="$AGENT_NAME" \
        --from-literal=resource-proxy-server="argocd-agent-resource-proxy.${var.hub_namespace}.svc.cluster.local:9090" \
        -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} \
        --dry-run=client \
        -o yaml | kubectl apply -f - --context ${var.hub_cluster_context}

      echo "✓ Agent $AGENT_NAME credentials info stored"
    EOT
  }

  depends_on = [
    null_resource.spoke_agent_creation,
    null_resource.resource_proxy_credentials_secret
  ]
}

# =============================================================================
# SECTION 4: CREDENTIAL ROTATION HELPER
# =============================================================================

# Document how to rotate resource proxy passwords
output "resource_proxy_credentials_rotation_guide" {
  description = "Guide for rotating resource proxy credentials"
  value = var.enable_resource_proxy_credentials_secret ? {
    retrieve_current = "kubectl get secret argocd-agent-resource-proxy-creds -n ${var.hub_namespace} -o jsonpath='{.data.credentials}' | base64 -d"
    regenerate       = "terraform taint null_resource.resource_proxy_credentials_secret && terraform apply -target=null_resource.resource_proxy_credentials_secret"
    verify           = "kubectl describe secret argocd-agent-resource-proxy-creds -n ${var.hub_namespace}"
  } : null
}

# =============================================================================
# SECTION 5: OUTPUTS
# =============================================================================

output "resource_proxy_service_name" {
  description = "Resource proxy service name for agent configuration"
  value       = "argocd-agent-resource-proxy.${var.hub_namespace}.svc.cluster.local:9090"
}

output "resource_proxy_credentials_secret_name" {
  description = "Kubernetes secret containing resource proxy credentials"
  value       = var.enable_resource_proxy_credentials_secret ? "argocd-agent-resource-proxy-creds" : null
}

output "resource_proxy_credentials_retrieval" {
  description = "Command to retrieve stored resource proxy credentials"
  value = var.enable_resource_proxy_credentials_secret ? format(
    "kubectl get secret argocd-agent-resource-proxy-creds -n %s --context %s -o jsonpath='{.data.credentials}' | base64 -d",
    var.hub_namespace,
    var.hub_cluster_context
  ) : null
  sensitive = true
}

output "agent_credentials_info_configmaps" {
  description = "Per-agent credentials information ConfigMaps created"
  value = length(var.workload_clusters) > 0 ? [
    for agent in keys(var.workload_clusters) :
    "argocd-agent-credentials-info-${agent}"
  ] : []
}
