# Adopting Existing ArgoCD Installation

This guide walks you through adopting an existing ArgoCD installation into Terraform management, including Keycloak OIDC integration.

## Prerequisites

- Existing ArgoCD installation in your cluster
- Keycloak instance for OIDC authentication
- Terraform >= 1.0
- `kubectl` configured for your cluster
- `helm` CLI installed

---

## Step 1: Discover Existing Installation

Run these commands to gather information about your current ArgoCD setup.

### 1. Helm Release Status

```bash
# List all ArgoCD releases
helm list -A | grep argocd

# Expected Output:
# NAME      NAMESPACE    REVISION  STATUS    CHART           APP_VERSION
# argocd    argocd-test  1         deployed  argo-cd-5.51.0  v2.9.3
```

### 2. Kubernetes Resources

```bash
# Check Namespace
kubectl get ns | grep argocd

# Check ClusterRoles (Cluster-wide resources)
kubectl get clusterrole | grep argocd-server

# Check CRDs
kubectl get crd | grep "argoproj.io"
```

### 3. Keycloak Configuration

Access your Keycloak Admin Console and identify:
- **Realm**: The realm where ArgoCD is registered (e.g., `argocd`).
- **Client UUID**: The internal ID of the client (URL format: `.../clients/<UUID>/settings`).
- **Client ID**: The public client ID (e.g., `argocd-client`).

**Record these values**:
- Release Name (e.g., `argocd`)
- Namespace (e.g., `argocd-test`)
- Keycloak Client UUID (for import)

---

## Step 2: Configure `terraform.tfvars`

Navigate to the Terraform directory:

```bash
cd argocd/terraform
```

> [!IMPORTANT]
> **Critical**: Ensure `install_cert_manager` and `install_nginx_ingress` are set to `false` if they are managed by other stacks, to avoid conflicts.

Copy the template:

```bash
cp terraform.tfvars.template terraform.tfvars
```

Update `terraform.tfvars` with your discovery values:

```hcl
# Keycloak Settings
keycloak_url      = "https://keycloak.example.com"
keycloak_user     = "admin"
keycloak_password = "your-password"
target_realm      = "argocd"

# ArgoCD Settings
argocd_url   = "https://argocd.example.com"
kube_context = "gke_project_region_cluster"
namespace    = "argocd-test" # MUST match existing namespace

# Shared Infrastructure (Set to false if adopting only ArgoCD)
install_nginx_ingress = false
install_cert_manager  = false

# Infrastructure References
nginx_ingress_namespace = "ingress-nginx"
ingress_class_name      = "nginx"
cert_manager_namespace  = "cert-manager"
letsencrypt_email       = "admin@example.com"
cert_issuer_name        = "letsencrypt-prod"
cert_issuer_kind        = "ClusterIssuer"
```

---

## Step 3: Initialize Terraform

```bash
terraform init
```

---

## Step 4: Clean Up Conflicting Resources

> [!CAUTION]
> If you are adopting ArgoCD into a **different namespace** than where it currently exists, you MUST clean up old cluster-wide resources first.

If keeping the same namespace, skip this step.

```bash
# Delete old ClusterRoles
kubectl delete clusterrole argocd-server
kubectl delete clusterrole argocd-application-controller
kubectl delete clusterrole argocd-notifications-controller

# Delete old ClusterRoleBindings
kubectl delete clusterrolebinding argocd-server
kubectl delete clusterrolebinding argocd-application-controller
kubectl delete clusterrolebinding argocd-notifications-controller
```

---

## Step 5: Import Resources

You must import the existing resources into the Terraform state.

### 1. Import ArgoCD Helm Release

Format: `<namespace>/<release_name>`

```bash
terraform import 'helm_release.argocd-test' argocd-test/argocd
```

### 2. Import Keycloak Client

Format: `<realm_id>/<client_uuid>`

```bash
# Example:
terraform import 'keycloak_openid_client.argocd' argocd/12345678-abcd-efgh-ijkl-1234567890ab
```

> **Note**: You do not need to import the Default Scopes or Group Mapper; Terraform will manage or recreate them if they don't exactly match the state ID.

---

## Step 6: Verify the Import

```bash
terraform plan
```

**Expected output**:
- **No changes** to the Helm Release (if versions match).
- **Modifications** to Keycloak Client (adding terraform-managed attributes).
- **Creation** of Group Mappers (if they didn't exist in a way Terraform recognized).

---

## Common Issues

### Error: "ClusterRole exists and cannot be imported"
**Fix**: Delete the conflicting ClusterRole manually (`kubectl delete clusterrole ...`) and let Terraform recreate it.

### Error: "Keycloak Client not found"
**Fix**: Ensure you are using the **UUID** from the URL, not the "Client ID" string.

---

## Next Steps

1. **Test Login**: Verify you can log in via Keycloak.
2. **Check RBAC**: Verify "Groups" are working (Admins have access).
