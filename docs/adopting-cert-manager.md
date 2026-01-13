# Adopting Existing Cert-Manager Installation

This guide walks you through adopting an existing Cert-Manager installation into Terraform management.

## Prerequisites

- Existing Cert-Manager installation in your cluster
- Terraform >= 1.0
- `kubectl` configured for your cluster
- `helm` CLI installed

## Step 1: Discover Existing Installation

Run these commands to gather information about your current Cert-Manager setup:

```bash
# 1. Find the Helm release
helm list -A | grep cert-manager

# Expected output format:
# RELEASE_NAME    NAMESPACE           REVISION  UPDATED                   STATUS    CHART                 APP_VERSION
# cert-manager    cert-manager 1         2025-12-08 11:23:11...    deployed  cert-manager-v1.16.2  v1.16.2

# 2. Check the namespace
kubectl get ns | grep cert-manager

# 3. Verify CRDs and their namespace annotations
kubectl get crd | grep cert-manager
kubectl get crd certificaterequests.cert-manager.io -o yaml | grep -A 5 "annotations:"

# 4. Check existing Issuers
kubectl get clusterissuers,issuers -A
```

**Record these values**:
- Release name (e.g., `cert-manager`)
- Namespace (e.g., `cert-manager`)
- Chart version (e.g., `v1.16.2`)
- Issuer names and types (ClusterIssuer vs Issuer)

---

## Step 2: Configure `terraform.tfvars`

Navigate to the Terraform directory:

```bash
cd cert-manager/terraform
```

> [!IMPORTANT]
> **Critical**: You MUST set `install_cert_manager = true` to create the Terraform resource configuration before importing.

Create or update `terraform.tfvars` with values matching your cluster:

```hcl
# Enable the module (required for import)
install_cert_manager = true

# Match your existing installation
cert_manager_version       = "v1.16.2"              # From helm list
cert_manager_namespace     = "cert-manager"  # From helm list
cert_manager_release_name  = "cert-manager"         # From helm list

# Issuer configuration
letsencrypt_email = "admin@example.com"
cert_issuer_name  = "letsencrypt-prod"              # From kubectl get clusterissuers
cert_issuer_kind  = "ClusterIssuer"                 # Or "Issuer"
```

---

## Step 3: Initialize Terraform

```bash
terraform init
```

---

## Step 4: Import the Helm Release

```bash
# Format: terraform import <resource_address> <namespace>/<release_name>
terraform import 'helm_release.cert_manager[0]' cert-manager/cert-manager
```

**Expected output**:
```
helm_release.cert_manager[0]: Importing from ID "cert-manager/cert-manager"...
helm_release.cert_manager[0]: Import prepared!
  Prepared helm_release for import
helm_release.cert_manager[0]: Refreshing state... [id=cert-manager]

Import successful!
```

---

## Step 5: Verify the Import

```bash
terraform plan
```

**Expected output**: Should show **no changes** or only minor metadata updates.

If you see planned changes to the Helm release itself, **STOP** and review your `terraform.tfvars` values.

---

## Common Issues

### Error: Error: "Configuration for import target does not exist"

**Cause**: `install_cert_manager = false` in your `tfvars`.

**Fix**:
```bash
# Set install_cert_manager = true in terraform.tfvars
terraform plan  # This creates the resource config
terraform import 'helm_release.cert_manager[0]' cert-manager/cert-manager
```

---

### Error: Error: "CRD namespace annotation mismatch"

**Cause**: CRDs were installed in a different namespace (e.g., `cert-manager` vs `mstack-cert-manager`).

**Symptoms**:
```
Error: Unable to continue with update: CustomResourceDefinition "certificaterequests.cert-manager.io" 
in namespace "" exists and cannot be imported into the current release: invalid ownership metadata; 
annotation validation error: key "meta.helm.sh/release-namespace" must equal "cert-manager": 
current value is "cert-manager"
```

**Fix**: You have two options:

**Option A (Recommended)**: Don't manage CRDs via Terraform
```hcl
# In your Helm values or module, ensure:
installCRDs = false
```

**Option B**: Manually update CRD annotations (advanced)
```bash
# WARNING: This can break other installations using these CRDs
kubectl annotate crd certificaterequests.cert-manager.io \
  meta.helm.sh/release-namespace=cert-manager --overwrite
```

---

### Error: Error: "Issuer already exists"

**Cause**: Terraform is trying to create an Issuer/ClusterIssuer that already exists.

**Fix**: Import the Issuer resource:
```bash
# For ClusterIssuer
terraform import 'kubernetes_manifest.letsencrypt_issuer[0]' \
  apiVersion=cert-manager.io/v1,kind=ClusterIssuer,name=letsencrypt-prod

# For Issuer (namespaced)
terraform import 'kubernetes_manifest.letsencrypt_issuer[0]' \
  apiVersion=cert-manager.io/v1,kind=Issuer,namespace=<namespace>,name=letsencrypt-prod
```

---

## Next Steps

After successful adoption:

1. **Test**: Run `terraform plan` regularly to ensure no drift
2. **Document**: Update your team's runbook with the adopted configuration
3. **Backup**: Commit your `terraform.tfstate` to secure remote storage

