# =============================================================================
# ARGOCD RESOURCE HEALTH CUSTOMIZATIONS FOR SPOKE CLUSTERS
# =============================================================================
# Configures resource health checks to prevent applications from being stuck
# in "Progressing" state due to Ingress resources without LoadBalancer IPs
# =============================================================================

resource "null_resource" "spoke_argocd_resource_health_config" {
  for_each = var.clusters

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -e
      set -o pipefail
      
      LOG_FILE="/tmp/argocd-spoke-resource-health-${each.key}-$$(date +%Y%m%d-%H%M%S).log"
      
      echo "Configuring ArgoCD resource health customizations on spoke cluster ${each.key}..." | tee -a "$LOG_FILE"
      
      # Configure argocd-cm with resource health check overrides
      if ! kubectl patch configmap argocd-cm -n ${var.spoke_namespace} \
        --context ${each.value} \
        --type='merge' \
        --patch '{"data":{
          "resource.customizations.health.networking.k8s.io_Ingress": "hs = {}\nhs.status = \"Healthy\"\nreturn hs\n"
        }}' 2>&1 | tee -a "$LOG_FILE"; then
        echo "✗ ERROR: Failed to patch argocd-cm ConfigMap on spoke. Check logs: $LOG_FILE" | tee -a "$LOG_FILE"
        exit 1
      fi
      
      echo "Restarting application-controller to apply changes..." | tee -a "$LOG_FILE"
      kubectl rollout restart statefulset/argocd-application-controller \
        -n ${var.spoke_namespace} \
        --context ${each.value} 2>&1 | tee -a "$LOG_FILE" || true
      
      echo "✓ Resource health customizations configured on spoke cluster ${each.key}" | tee -a "$LOG_FILE"
      echo "Configuration logs saved to: $LOG_FILE"
    EOT
  }

  depends_on = [null_resource.spoke_argocd_installation]

  triggers = {
    config_version  = "v1"
    cluster_context = each.value
    agent_name      = each.key
  }
}
