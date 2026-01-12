# Adopting Existing ArgoCD Installation

This guide walks you through adopting an existing ArgoCD installation into Terraform management, including Keycloak OIDC integration.

## Prerequisites

- Existing ArgoCD installation in your cluster
- Keycloak instance for OIDC authentication
- Terraform >= 1.0
- `kubectl` configured for your cluster
- `helm` CLI installed

## Step 1: Discover Existing Installation

Run these commands to gather information about your current ArgoCD setup:

```bash
# 1. Find the Helm release
helm list -A | grep argocd

# Expected output format:
# RELEASE_NAME  NAMESPACE     REVISION  UPDATED                   STATUS    CHART           APP_VERSION
# argocd        argocd-test   1         2026-01-12 14:15:22...    deployed  argo-cd-5.51.0  v2.9.3

# 2. Check for ArgoCD namespaces
kubectl get ns | grep argocd

# 3. Check for ClusterRoles (these are cluster-wide)
kubectl get clusterrole | grep argocd

# 4. Check for CRDs
kubectl get crd | grep argoproj

# 5. Check Keycloak client (if using Keycloak)
# Access Keycloak admin console and note:
# - Realm name
# - Client ID
# - Redirect URIs
```

**Record these values**:
- Release name (e.g., `argocd`)
- Namespace (e.g., `argocd-test`)
- Chart version (e.g., `5.51.0`)
- Keycloak realm (e.g., `argocd`)
- Keycloak client ID (e.g., `argocd-client`)

---

## Step 2: Clean Up Conflicting Resources

> [!CAUTION]
> **Critical**: If you're adopting an ArgoCD installation in a **different namespace** than the original, you MUST clean up old cluster-wide resources first.

### Check for Conflicts

```bash
# List all ArgoCD ClusterRoles
kubectl get clusterrole | grep argocd

# List all ArgoCD ClusterRoleBindings
kubectl get clusterrolebinding | grep argocd

# List ArgoCD CRDs
kubectl get crd | grep argoproj
```

### Clean Up Old Resources (if namespace changed)

```bash
# Delete old ClusterRoles
kubectl delete clusterrole argocd-server
kubectl delete clusterrole argocd-application-controller
kubectl delete clusterrole argocd-notifications-controller

# Delete old ClusterRoleBindings
kubectl delete clusterrolebinding argocd-server
kubectl delete clusterrolebinding argocd-application-controller
kubectl delete clusterrolebinding argocd-notifications-controller

# Delete CRDs (only if reinstalling fresh)
kubectl delete crd applications.argoproj.io
kubectl delete crd applicationsets.argoproj.io
kubectl delete crd appprojects.argoproj.io
```

---

## Step 3: Configure `terraform.tfvars`

Create or update `terraform.tfvars` with values matching your setup:

```hcl
# Keycloak Settings
keycloak_url      = "https://keycloak.example.com"
keycloak_user     = "admin"
keycloak_password = "your-password"
target_realm      = "argocd"

# ArgoCD Settings
argocd_url   = "https://argocd.example.com"
kube_context = "gke_project_region_cluster"

# Infrastructure (if managing cert-manager/ingress)
install_nginx_ingress = false  # Set to true only if you want Terraform to manage it
install_cert_manager  = false  # Set to true only if you want Terraform to manage it

# Reference existing infrastructure
nginx_ingress_namespace = "ingress-nginx"
ingress_class_name      = "nginx"
cert_manager_namespace  = "cert-manager"
namespace               = "argocd-test"
letsencrypt_email       = "admin@example.com"
cert_issuer_name        = "letsencrypt-prod"
cert_issuer_kind        = "ClusterIssuer"
```

---

## Step 4: Initialize Terraform

```bash
cd argocd/terraform
terraform init
```

---

## Step 5: Import Resources

### Import ArgoCD Helm Release

```bash
# Format: terraform import <resource_address> <namespace>/<release_name>
terraform import 'helm_release.argocd-test' argocd-test/argocd
```

### Import Keycloak Resources (if already configured)

```bash
# Import the OIDC client
terraform import 'keycloak_openid_client.argocd' <realm>/<client-id>

# Example:
terraform import 'keycloak_openid_client.argocd' argocd/4c2be9ef-878f-484a-8674-0fed256181ae
```

**Note**: You can find the client ID in Keycloak Admin Console → Clients → argocd-client → Settings (it's the UUID in the URL).

---

## Step 6: Verify the Import

```bash
terraform plan
```

**Expected output**: Should show **no changes** or only minor metadata updates.

---

## Common Issues

### ❌ Error: "ClusterRole exists and cannot be imported"

**Symptoms**:
```
Error: Unable to continue with install: ClusterRole "argocd-server" in namespace "" exists 
and cannot be imported into the current release: invalid ownership metadata; 
annotation validation error: key "meta.helm.sh/release-namespace" must equal "argocd-test": 
current value is "argocd"
```

**Cause**: Old ArgoCD installation left cluster-wide resources with different namespace annotations.

**Fix**: Delete the conflicting ClusterRoles (see Step 2 above).

---

### ❌ Error: "CRDs cannot be imported"

**Symptoms**:
```
Warning: Helm uninstall returned an information message

These resources were kept due to the resource policy:
[CustomResourceDefinition] applications.argoproj.io
[CustomResourceDefinition] applicationsets.argoproj.io
[CustomResourceDefinition] appprojects.argoproj.io
```

**Cause**: ArgoCD CRDs are retained by default when uninstalling.

**Fix**: Manually delete them if you want a clean reinstall:
```bash
kubectl delete crd applications.argoproj.io
kubectl delete crd applicationsets.argoproj.io
kubectl delete crd appprojects.argoproj.io
```

---

### ❌ Keycloak OIDC Login Fails

**Symptoms**: After adoption, ArgoCD login redirects to Keycloak but fails with "invalid redirect URI".

**Fix**: Verify the redirect URIs in Keycloak match your `argocd_url`:

```bash
# In Keycloak Admin Console:
# Clients → argocd-client → Settings → Valid Redirect URIs

# Should include:
https://argocd.example.com/auth/callback
https://argocd.example.com/*
```

---

## Next Steps

After successful adoption:

1. **Test Login**: Verify Keycloak OIDC authentication works
2. **Test GitOps**: Deploy a test application to verify ArgoCD functionality
3. **Document**: Update your team's runbook with the adopted configuration

---

## See Also

- [Manual ArgoCD Deployment Guide](manual-argocd-deployment.md)
- [Troubleshooting ArgoCD](troubleshooting-argocd.md)
