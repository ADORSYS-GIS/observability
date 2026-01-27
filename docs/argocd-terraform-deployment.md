# ArgoCD Terraform Deployment

Production-grade ArgoCD deployment with Keycloak OIDC integration using Terraform and Helm.

## Overview

This deployment configures ArgoCD with:

- **GitOps Continuous Delivery**: Declarative application deployment from Git repositories
- **High Availability**: Redis HA, multiple replicas for critical components
- **OIDC Authentication**: Keycloak integration for SSO and RBAC
- **Automated TLS**: Certificate management via cert-manager
- **Horizontal Autoscaling**: Dynamic scaling for repo-server and API server

## Prerequisites

| Requirement | Version | Purpose |
|-------------|---------|---------|
| **Terraform** | ≥ 1.5.0 | Infrastructure provisioning |
| **kubectl** | ≥ 1.24 | Kubernetes cluster access |
| **Kubernetes Cluster** | ≥ 1.24 | Target platform (GKE, EKS, AKS) |
| **Keycloak** | Latest | OIDC authentication provider |

### Required Infrastructure

- **Ingress Controller**: NGINX Ingress Controller must be installed
- **Cert-Manager**: For automated TLS certificates (recommended)
- **DNS Configuration**: Domain name pointing to ingress load balancer

> **Don't have these?** See [Ingress Controller Setup](ingress-controller-terraform-deployment.md) and [Cert-Manager Setup](cert-manager-terraform-deployment.md)

### Keycloak Setup

Before deploying ArgoCD, ensure Keycloak is configured:

1. **Realm Created**: e.g., `argocd`
2. **OIDC Client Created**: e.g., `argocd-client`
3. **Valid Redirect URIs**:
   - `https://argocd.YOUR_DOMAIN/auth/callback` (Browser login)
   - `http://localhost:8085/auth/callback` (CLI login)
4. **Users and Groups**: For authentication and RBAC

For Keycloak setup, see [Keycloak Getting Started Guide](https://www.keycloak.org/guides#getting-started) and [ArgoCD Keycloak Integration](https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/keycloak/).

## Installation

> **Existing Installation?** If you already have ArgoCD deployed and want to manage it with Terraform, see the [Adoption Guide](adopting-argocd.md) before proceeding.

### Step 1: Clone Repository

```bash
git clone https://github.com/Adorsys-gis/observability.git
cd observability/argocd/terraform
```

### Step 2: Verify Kubernetes Context

```bash
kubectl config current-context
```

Ensure you're pointing to the correct cluster.

### Step 3: Configure Variables

```bash
cp terraform.tfvars.template terraform.tfvars
```

Edit `terraform.tfvars` with your environment values:

```hcl
# Keycloak OIDC Configuration
keycloak_url      = "https://keycloak.example.com"
keycloak_user     = "admin"
keycloak_password = "your-secure-password"
target_realm      = "argocd"

# ArgoCD Configuration
argocd_url   = "https://argocd.example.com"
kube_context = "gke_project_region_cluster"
namespace    = "argocd"

# Infrastructure Components (set to false if managed elsewhere)
install_cert_manager  = false
install_nginx_ingress = false

# Reference Existing Infrastructure
nginx_ingress_namespace = "ingress-nginx"
cert_manager_namespace  = "cert-manager"
ingress_class_name      = "nginx"
letsencrypt_email       = "admin@example.com"
cert_issuer_name        = "letsencrypt-prod"
cert_issuer_kind        = "ClusterIssuer"

# Chart Version
argocd_version = "7.7.12"
```

### Complete Variable Reference

For all available variables, see [variables.tf](../argocd/terraform/variables.tf).

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `keycloak_url` | Keycloak server URL | - | ✓ |
| `keycloak_user` | Keycloak admin username | - | ✓ |
| `keycloak_password` | Keycloak admin password | - | ✓ |
| `target_realm` | Keycloak realm for ArgoCD | `argocd` | |
| `argocd_url` | ArgoCD public URL | - | ✓ |
| `kube_context` | Kubernetes context name | `""` | |
| `namespace` | ArgoCD namespace | `argocd` | |
| `install_nginx_ingress` | Deploy NGINX Ingress | `false` | |
| `install_cert_manager` | Deploy cert-manager | `false` | |
| `argocd_version` | ArgoCD Helm chart version | `7.7.12` | |
| `letsencrypt_email` | Let's Encrypt email | - | ✓ |

### Step 4: Initialize Terraform

```bash
terraform init
```

### Step 5: Plan Deployment

```bash
terraform plan
```

Review the planned changes carefully.

### Step 6: Apply Configuration

```bash
terraform apply
```

Type `yes` when prompted to confirm.

**Expected deployment time**: 3-5 minutes.

> **Warning**: If you see errors about resources already existing (ClusterRoles, Helm releases), **STOP** and follow the [Adoption Guide](adopting-argocd.md) to import existing resources.

### Step 7: Retrieve Admin Password

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo
```

Save this password securely for initial access.

## Verification

### Check Pod Status

```bash
kubectl get pods -n argocd
```

All pods should be in `Running` state.

Expected components:
- `argocd-server` - API server and UI
- `argocd-repo-server` - Repository server
- `argocd-application-controller` - Application controller
- `argocd-redis` - Redis cache
- `argocd-notifications-controller` - Notifications

### Check Ingress

```bash
kubectl get ingress -n argocd
```

Verify the ingress has an address assigned.

### Verify TLS Certificate

```bash
kubectl get certificate -n argocd
```

Certificate should show `Ready: True`.

### Access ArgoCD UI

1. Navigate to `https://argocd.example.com`
2. Login with:
   - **Username**: `admin`
   - **Password**: From kubectl output
3. Or use **Login via Keycloak** for SSO

### Test CLI Access

```bash
# Install ArgoCD CLI
# macOS
brew install argocd

# Linux
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x argocd
sudo mv argocd /usr/local/bin/

# Login to ArgoCD
argocd login argocd.example.com

# List applications
argocd app list
```

## Post-Deployment Configuration

### Configure Keycloak Groups for RBAC

Create groups in Keycloak for role-based access:

```bash
# Example groups:
# - argocd-admins (full access)
# - argocd-developers (limited access)
# - argocd-viewers (read-only)
```

Assign users to these groups in Keycloak. Groups are automatically mapped to ArgoCD roles.

### Create First Application

Test ArgoCD by deploying a sample application:

```bash
argocd app create guestbook \
  --repo https://github.com/argoproj/argocd-example-apps.git \
  --path guestbook \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace default

# Sync the application
argocd app sync guestbook

# Check status
argocd app get guestbook
```

### Change Admin Password (Optional)

For enhanced security:

```bash
argocd account update-password
```

Or disable admin user if using OIDC exclusively:

```bash
kubectl patch configmap argocd-cm -n argocd \
  --type merge \
  -p '{"data":{"admin.enabled":"false"}}'
```

## Operations

### Upgrade ArgoCD

Update chart version in `terraform.tfvars`:

```hcl
argocd_version = "7.8.0"  # New version
```

Apply changes:

```bash
terraform apply
```

### View Component Logs

```bash
# Server logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server --tail=100

# Application controller logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=100

# Repo server logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server --tail=100
```

### Scale Components

Edit Helm values if needed, then apply:

```bash
terraform apply
```

### Uninstall

```bash
terraform destroy
```

**Warning**: This will delete all ArgoCD applications and configurations. Ensure you have backups if needed.

## Troubleshooting

### ClusterRole Conflicts

```bash
# Check for conflicting ClusterRoles
kubectl get clusterrole | grep argocd

# Delete if adopting from different namespace
kubectl delete clusterrole argocd-server
kubectl delete clusterrole argocd-application-controller
```

### Keycloak Connection Issues

```bash
# Test from ArgoCD pod
kubectl exec -n argocd <argocd-server-pod> -- \
  curl -v https://keycloak.example.com/realms/argocd/.well-known/openid-configuration
```

### Ingress Not Working

```bash
# Verify ingress controller
kubectl get pods -n ingress-nginx

# Check ingress resource
kubectl describe ingress argocd-server -n argocd

# Verify DNS resolution
nslookup argocd.example.com
```

For detailed troubleshooting, see [Troubleshooting Guide](troubleshooting-argocd.md).