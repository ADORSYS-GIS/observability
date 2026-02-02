# ArgoCD Agent - Configuration Reference

Complete Terraform variable reference verified against `terraform/environments/prod/variables.tf`.

---

## Quick Examples

### Minimal (LoadBalancer)
```hcl
hub_cluster_context = "gke_project_region_hub"
workload_clusters = {
  "agent-1" = "gke_project_region_spoke1"
}
```

### Production (Ingress + SSO + HA)
```hcl
hub_cluster_context = "gke_project_region_hub"
workload_clusters = {
  "agent-1" = "gke_project_region_spoke1"
  "agent-2" = "gke_project_region_spoke2"
}

# Exposure
ui_expose_method        = "ingress"
principal_expose_method = "loadbalancer"
argocd_host             = "argocd.example.com"

# SSO
enable_keycloak   = true
keycloak_url      = "https://keycloak.example.com"
keycloak_realm    = "argocd"
keycloak_password = "admin-pass"  # Use TF_VAR_keycloak_password
argocd_url        = "https://argocd.example.com"

# HA
principal_replicas = 2

# Use existing infrastructure
install_nginx_ingress = false
install_cert_manager  = false
```

---

## Core Variables

### Deployment Control

| Variable | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `hub_cluster_context` | string | Yes | - | Hub cluster kubectl context |
| `workload_clusters` | map(string) | Yes | `{}` | Spokes: `{"agent-1" = "context1"}` |
| `deploy_hub` | bool | No | `true` | Deploy hub components |
| `deploy_spokes` | bool | No | `true` | Deploy spoke agents |

**Deployment modes**:

| Mode | `deploy_hub` | `deploy_spokes` | Use Case |
|------|--------------|-----------------|----------|
| Full | `true` | `true` | New deployment |
| Hub-only | `true` | `false` | Initial hub setup |
| Spokes-only | `false` | `true` | Add spokes to existing hub |

### ArgoCD Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `argocd_version` | string | `"v0.5.3"` | ArgoCD agent version |
| `hub_namespace` | string | `"argocd"` | Hub namespace |
| `spoke_namespace` | string | `"argocd"` | Spoke namespace |

---

## Exposure Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `ui_expose_method` | string | `"ingress"` | `loadbalancer` or `ingress` |
| `principal_expose_method` | string | `"ingress"` | `loadbalancer`, `ingress`, or `nodeport` |
| `argocd_host` | string | `""` | UI hostname (required for ingress) |
| `principal_ingress_host` | string | `""` | Principal hostname (optional, ingress only) |
| `enable_principal_ingress` | bool | `false` | Expose Principal via Ingress in addition to LoadBalancer |

**Production recommendation**:
- UI: `ingress` (user-facing, TLS termination)
- Principal: `loadbalancer` (stable IP for agent connections)

---

## SSO with Keycloak

| Variable | Type | Default | Required If | Description |
|----------|------|---------|-------------|-------------|
| `enable_keycloak` | bool | `false` | - | Enable OIDC authentication |
| `keycloak_url` | string | `""` | SSO enabled | Keycloak URL |
| `keycloak_user` | string | `"admin"` | SSO enabled | Keycloak admin username |
| `keycloak_password` | string | `""` | SSO enabled | Keycloak admin password (sensitive) |
| `keycloak_realm` | string | `"argocd"` | - | Keycloak realm name |
| `keycloak_client_id` | string | `"argocd"` | - | OIDC client ID |
| `argocd_url` | string | `""` | SSO enabled | ArgoCD external URL |
| `keycloak_enable_pkce` | bool | `false` | - | Enable PKCE for CLI `--sso` login |

**Default admin user** (optional):

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `create_default_admin_user` | bool | `true` | Create initial admin user |
| `default_admin_username` | string | `"argocd-admin"` | Username |
| `default_admin_email` | string | `"admin@argocd.local"` | Email |
| `default_admin_password` | string | `""` | Password (sensitive, required) |
| `default_admin_password_temporary` | bool | `true` | Force password change on first login |

**Required Keycloak groups**: `ArgoCDAdmins`, `ArgoCDDevelopers`, `ArgoCDViewers`

See [RBAC guide](argocd-agent-rbac.md).

---

## High Availability

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `principal_replicas` | number | `1` | Principal replicas (2+ enables PDB and anti-affinity) |

**Production**: Set to `2` or more.

---

## Infrastructure Modules

### cert-manager

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `install_cert_manager` | bool | `false` | Install cert-manager |
| `cert_manager_version` | string | `"v1.19.2"` | Helm chart version |
| `cert_manager_namespace` | string | `"cert-manager"` | Namespace |
| `cert_issuer_name` | string | `"letsencrypt-prod"` | Issuer name |
| `cert_issuer_kind` | string | `"Issuer"` | `Issuer` or `ClusterIssuer` |
| `letsencrypt_email` | string | `""` | Email for notifications |

### ingress-nginx

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `install_nginx_ingress` | bool | `false` | Install ingress-nginx |
| `nginx_ingress_version` | string | `"2.4.2"` | Helm chart version |
| `nginx_ingress_namespace` | string | `"ingress-nginx"` | Namespace |
| `ingress_class_name` | string | `"nginx"` | Ingress class |

**Using existing infrastructure**:
```hcl
install_cert_manager  = false
install_nginx_ingress = false
cert_manager_namespace = "mstack-cert-manager"  # Point to existing
nginx_ingress_namespace = "mstack-ingress-nginx"
```

---

## Advanced Configuration

### External Principal (Spoke-Only Deployments)

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `principal_address` | string | `""` | External Principal IP (from hub output) |
| `principal_port` | number | `443` | Principal port |

Required when `deploy_hub = false`.

### AppProject Synchronization

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `enable_appproject_sync` | bool | `true` | Sync AppProjects to agents |
| `appproject_default_source_namespaces` | list(string) | `["*"]` | Default source namespaces |
| `appproject_default_dest_server` | string | `"*"` | Default destination server |
| `appproject_default_dest_namespaces` | list(string) | `["*"]` | Default destination namespaces |

### Timeouts

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `kubectl_timeout` | string | `"300s"` | kubectl wait timeout |
| `namespace_delete_timeout` | string | `"120s"` | Namespace deletion timeout |
| `argocd_install_retry_attempts` | number | `5` | Installation retries |
| `argocd_install_retry_delay` | number | `15` | Retry delay (seconds) |
| `principal_loadbalancer_wait_timeout` | number | `300` | LoadBalancer IP timeout (seconds) |

**Why extended timeouts?** Hub-spoke adds latency due to gRPC hops:
```
Request → Resource Proxy → Agent → Principal → Hub → Spoke
```

### Service Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `argocd_server_service_name` | string | `"argocd-server"` | UI service name |
| `principal_service_name` | string | `"argocd-agent-principal"` | Principal service name |
| `resource_proxy_service_name` | string | `"argocd-agent-resource-proxy"` | Resource proxy service |
| `resource_proxy_port` | number | `9090` | Resource proxy port |
| `enable_resource_proxy_credentials_secret` | bool | `true` | Store credentials in secret |

### Component Names

| Variable | Type | Default |
|----------|------|---------|
| `argocd_repo_server_name` | string | `"argocd-repo-server"` |
| `argocd_application_controller_name` | string | `"argocd-application-controller"` |
| `argocd_redis_name` | string | `"argocd-redis"` |
| `argocd_redis_network_policy_name` | string | `"argocd-redis-network-policy"` |
| `argocd_cmd_params_cm_name` | string | `"argocd-cmd-params-cm"` |
| `argocd_cm_name` | string | `"argocd-cm"` |
| `argocd_secret_name` | string | `"argocd-secret"` |

Only customize if using non-standard ArgoCD deployments.

### Tools

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `argocd_agentctl_path` | string | `"/usr/local/bin/argocd-agentctl"` | Path to argocd-agentctl binary |

---

## Environment Variables

Use environment variables for sensitive values:

```bash
export TF_VAR_keycloak_password="your-password"
export TF_VAR_default_admin_password="initial-password"
terraform apply
```

---

## Variable Validation

Terraform validates:
- `ui_expose_method`: must be `loadbalancer` or `ingress`
- `principal_expose_method`: must be `loadbalancer`, `ingress`, or `nodeport`
- `principal_replicas`: 1-5
- `kubectl_timeout`: valid duration (e.g., `300s`, `5m`)
- Keycloak variables: required when `enable_keycloak = true`

---

## Examples by Scenario

### Development (Single Spoke)
```hcl
hub_cluster_context = "minikube-hub"
workload_clusters = {
  "dev" = "minikube-spoke"
}
ui_expose_method        = "loadbalancer"
principal_expose_method = "loadbalancer"
```

### Staging (Multi-Region)
```hcl
hub_cluster_context = "gke_proj_us_hub"
workload_clusters = {
  "staging-us"   = "gke_proj_us_staging"
  "staging-eu"   = "gke_proj_eu_staging"
  "staging-asia" = "gke_proj_asia_staging"
}
ui_expose_method        = "ingress"
principal_expose_method = "loadbalancer"
argocd_host             = "argocd-staging.example.com"
```

### Production (HA + SSO)
```hcl
hub_cluster_context = "gke_prod_us_hub"
workload_clusters = {
  "prod-us"   = "gke_prod_us_workload"
  "prod-eu"   = "gke_prod_eu_workload"
  "prod-asia" = "gke_prod_asia_workload"
}

ui_expose_method        = "ingress"
principal_expose_method = "loadbalancer"
argocd_host             = "argocd.example.com"

enable_keycloak   = true
keycloak_url      = "https://keycloak.example.com"
keycloak_realm    = "production"
argocd_url        = "https://argocd.example.com"

principal_replicas = 3

install_cert_manager  = false  # Use existing
install_nginx_ingress = false
```

---

## Next Steps

- [Deployment guide](argocd-agent-terraform-deployment.md)
- [Operations guide](argocd-agent-operations.md)
- [Troubleshooting](argocd-agent-troubleshooting.md)
