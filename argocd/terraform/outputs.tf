output "control_plane_namespace" {
  description = "Argo CD namespace on control plane"
  value       = kubernetes_namespace.argocd_control_plane.metadata[0].name
}

output "workload_namespace" {
  description = "Argo CD namespace on workload cluster"
  value       = kubernetes_namespace.argocd_workload.metadata[0].name
}

output "principal_server_address" {
  description = "Principal server address for agents to connect to"
  value       = var.control_plane_cluster.server_address
}

output "principal_server_port" {
  description = "Principal server port for agents to connect to"
  value       = var.control_plane_cluster.server_port
}

output "principal_tls_enabled" {
  description = "Whether TLS is enabled on principal"
  value       = var.control_plane_cluster.tls_enabled
}

output "agent_name" {
  description = "Registered agent name"
  value       = var.workload_clusters[0].agent_name
}

output "agent_mode" {
  description = "Agent mode (autonomous or managed)"
  value       = var.agent_mode
}



output "connection_commands" {
  description = "Commands to verify agent connection"
  value = {
    check_principal_deployment = "kubectl -n ${kubernetes_namespace.argocd_control_plane.metadata[0].name} get deployment"
    check_agent_deployment     = "kubectl -n ${kubernetes_namespace.argocd_workload.metadata[0].name} get deployment"
    check_agent_logs           = "kubectl -n ${kubernetes_namespace.argocd_workload.metadata[0].name} logs -f deployment/argocd-agent"
    check_principal_logs       = "kubectl -n ${kubernetes_namespace.argocd_control_plane.metadata[0].name} logs -f deployment/argocd-server"
    port_forward_principal     = "kubectl -n ${kubernetes_namespace.argocd_control_plane.metadata[0].name} port-forward svc/argocd-server 8080:80"
    port_forward_agent         = "kubectl -n ${kubernetes_namespace.argocd_workload.metadata[0].name} port-forward svc/argocd-agent 8081:8080"
  }
}

output "tls_configuration" {
  description = "TLS configuration summary"
  value = {
    mTLS_enabled              = var.workload_clusters[0].tls_enabled
    CA_created                = var.create_certificate_authority
    certificate_validity_days = var.tls_config.cert_validity_days
    tls_algorithm             = var.tls_config.tls_algorithm
  }
}

output "kubectl_contexts" {
  description = "Kubectl contexts for both clusters"
  value = {
    control_plane = var.control_plane_cluster.context_name
    workload      = var.workload_clusters[0].context_name
  }
}

output "helm_release_status" {
  description = "Helm release information"
  value = {
    control_plane_release = helm_release.argocd_control_plane.metadata[0].values
    workload_release      = helm_release.argocd_workload.metadata[0].values
  }
  sensitive = true
}

output "verification_commands" {
  description = "Commands to verify the setup"
  value = [
    "# Verify control plane Argo CD",
    "kubectl --context=${var.control_plane_cluster.context_name} -n ${kubernetes_namespace.argocd_control_plane.metadata[0].name} get pods",
    "",
    "# Verify workload agent",
    "kubectl --context=${var.workload_clusters[0].context_name} -n ${kubernetes_namespace.argocd_workload.metadata[0].name} get pods",
    "",
    "# Check agent logs",
    "kubectl --context=${var.workload_clusters[0].context_name} -n ${kubernetes_namespace.argocd_workload.metadata[0].name} logs -f deployment/argocd-agent",
    "",
    "# Check TLS certificates",
    "kubectl --context=${var.control_plane_cluster.context_name} -n ${kubernetes_namespace.argocd_control_plane.metadata[0].name} get secret argocd-server-tls -o yaml",
    "kubectl --context=${var.workload_clusters[0].context_name} -n ${kubernetes_namespace.argocd_workload.metadata[0].name} get secret argocd-agent-client-tls -o yaml"
  ]
}
