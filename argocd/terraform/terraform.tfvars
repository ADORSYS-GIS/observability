control_plane_cluster = {
  name            = "control-plane"
  context_name    = "context-2"
  kubeconfig_path = "/home/ubuntu/.kube/merged-config"
  server_address  = "argocd-cp.local"
  server_port     = 443
  tls_enabled     = true
}

workload_clusters = [
  {
    name              = "workload-1"
    context_name      = "context_1"
    kubeconfig_path   = "/home/ubuntu/.kube/merged-config"
    principal_address = "argocd-cp.local"
    principal_port    = 443
    agent_name        = "agent-1"
    tls_enabled       = true
  }
]

tls_config = {
  generate_certs     = true
  cert_validity_days = 365
  tls_algorithm      = "RSA"
}

argocd_version         = "7.0.0"
argocd_image_version = "v2.11.2"
argocd_agent_version   = "v0.5.3"
enable_server_ui       = true
server_service_type    = "LoadBalancer"
controller_replicas    = 1
repo_server_replicas   = 1
agent_mode             = "autonomous"
create_certificate_authority = true

labels_common = {
  managed_by   = "terraform"
  application  = "argocd"
  environment  = "production"
}

annotations_common = {
  "terraform.io/managed" = "true"
  "owner"                = "devops-team"
}
