# Adopting Existing Cert-Manager Installation

This guide walks you through adopting an existing Cert-Manager installation into Terraform management and integrating it with GitHub Actions workflows.

> **When to Use This Guide**: If you already have cert-manager deployed (via Helm, kubectl, or other means) and want to manage it with Terraform and automate future deployments with GitHub Actions.

## Overview

Adoption involves:
1. **Importing** existing Helm releases and Kubernetes resources into Terraform state
2. **Configuring** Terraform variables to match your current setup
3. **Integrating** with GitHub Actions workflows for future automated deployments

## Prerequisites

- Existing Cert-Manager installation in your cluster
- Terraform >= 1.5.0
- `kubectl` configured for your cluster
- `helm` CLI installed
- Cloud provider CLI configured (for GitHub Actions integration):
  - **GKE**: `gcloud` CLI
  - **EKS**: `aws` CLI
  - **AKS**: `az` CLI

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

> **Critical**: You MUST set `install_cert_manager = true` to create the Terraform resource configuration before importing.

Create or update `terraform.tfvars` with values matching your cluster:

```hcl
# Cloud Provider Configuration
cloud_provider = "gke"  # Options: gke, eks, aks, generic

# GKE-specific (required only for GKE)
project_id           = "your-gcp-project"
region               = "us-central1"
gke_endpoint         = ""  # Will be auto-populated by workflow, leave empty for manual
gke_ca_certificate   = ""  # Will be auto-populated by workflow, leave empty for manual

# EKS-specific (required only for EKS)
# aws_region = "us-east-1"

# AKS: No additional variables required

# Enable the module (required for import)
install_cert_manager = true

# Match your existing installation
cert_manager_version = "v1.19.2"    # From helm list
namespace            = "cert-manager"  # From helm list
release_name         = "cert-manager"  # From helm list

# Issuer configuration (match existing)
create_issuer     = true  # Set to false if managing issuer separately
letsencrypt_email = "admin@example.com"
cert_issuer_name  = "letsencrypt-prod"    # From kubectl get clusterissuers
cert_issuer_kind  = "ClusterIssuer"       # Or "Issuer"
issuer_server     = "https://acme-v02.api.letsencrypt.org/directory"
ingress_class_name = "nginx"
```

### Multi-Cloud Backend Configuration

For GitHub Actions integration, you'll need a backend for Terraform state storage.

> **New to state storage?** See the [Terraform State Management Guide](terraform-state-management.md#setting-up-state-storage) for complete bucket/storage setup instructions.

**GKE (Google Cloud Storage)**:
```bash
# Set environment variable for backend configuration
export TF_STATE_BUCKET="your-gcs-bucket-name"

# Configure backend using the provided script
bash ../../.github/scripts/configure-backend.sh gke cert-manager
```

**EKS (AWS S3)**:
```bash
export TF_STATE_BUCKET="your-s3-bucket-name"
export AWS_REGION="us-east-1"

bash ../../.github/scripts/configure-backend.sh eks cert-manager
```

**AKS (Azure Blob Storage)**:
```bash
export AZURE_STORAGE_ACCOUNT="yourstorageaccount"
export AZURE_STORAGE_CONTAINER="tfstate"

bash ../../.github/scripts/configure-backend.sh aks cert-manager
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

## Step 6: Integrate with GitHub Actions (Optional but Recommended)

After successfully adopting your cert-manager installation, you can automate future deployments with GitHub Actions.

### Configure GitHub Repository Secrets

Add these secrets to your GitHub repository (Settings → Secrets and variables → Actions):

**For GKE**:
- `GCP_PROJECT_ID` - Your GCP project ID
- `GCP_SA_KEY` - Service account key (JSON)
- `CLUSTER_NAME` - GKE cluster name
- `CLUSTER_LOCATION` - GKE cluster region/zone
- `TF_STATE_BUCKET` - GCS bucket for Terraform state
- `LETSENCRYPT_EMAIL` - Email for Let's Encrypt
- `REGION` - GCP region

**For EKS**:
- `AWS_REGION` - AWS region
- `EKS_CLUSTER_NAME` - EKS cluster name
- `TF_STATE_BUCKET` - S3 bucket for Terraform state
- `LETSENCRYPT_EMAIL` - Email for Let's Encrypt
- Plus AWS authentication (via OIDC or access keys)

**For AKS**:
- `AZURE_CREDENTIALS` - Service principal credentials (JSON)
- `AKS_CLUSTER_NAME` - AKS cluster name
- `AKS_RESOURCE_GROUP` - Azure resource group
- `AZURE_STORAGE_ACCOUNT` - Storage account for Terraform state
- `AZURE_STORAGE_CONTAINER` - Container name for Terraform state
- `LETSENCRYPT_EMAIL` - Email for Let's Encrypt

### Push Terraform State to Remote Backend

After adoption, commit your Terraform state to the remote backend:

```bash
# Verify backend is configured
cat backend-config.tf

# Re-initialize with backend
terraform init

# This will prompt to migrate local state to remote backend
# Type 'yes' when prompted

# Verify state is now remote
terraform state list
```

### Test the GitHub Actions Workflow

Create a test branch and push changes:

```bash
git checkout -b test-cert-manager-adoption
git add .
git commit -m "Adopt cert-manager into Terraform management"
git push origin test-cert-manager-adoption
```

Create a Pull Request - the workflow will:
1. Run `terraform plan`
2. Post plan output as PR comment
3. Wait for approval

After PR merge, the workflow will:
1. Run `terraform apply` automatically
2. Update cert-manager in your cluster

### Workflow Files

The following workflows are available:
- `.github/workflows/deploy-cert-manager-gke.yaml` - For GKE clusters
- `.github/workflows/deploy-cert-manager-eks.yaml` - For EKS clusters
- `.github/workflows/deploy-cert-manager-aks.yaml` - For AKS clusters
- `.github/workflows/destroy-cert-manager.yaml` - For destroying resources

---

## Next Steps

After successful adoption:

1. **Commit State**: Push Terraform state to remote backend
2. **Test Workflow**: Create a test PR to verify GitHub Actions integration
3. **Monitor**: Run `terraform plan` regularly to detect configuration drift
4. **Document**: Update team runbooks with the adopted configuration
5. **Upgrade**: Test cert-manager version upgrades in non-production first

---

## Troubleshooting GitHub Actions Integration

### Workflow fails with "backend not configured"

**Fix**: Ensure backend configuration is committed:
```bash
git add cert-manager/terraform/backend-config.tf
git commit -m "Add backend configuration"
git push
```

### Workflow fails with "state lock"

**Cause**: Another Terraform operation is in progress or a previous run didn't release the lock.

**Fix**: 
```bash
# List locks (if using GCS)
gsutil ls gs://${TF_STATE_BUCKET}/terraform/cert-manager/

# Force unlock (use with caution)
terraform force-unlock <LOCK_ID>
```

### Plan shows unexpected changes after adoption

**Cause**: GitHub Actions workflows pass additional variables (like `gke_endpoint`) that weren't in your local import.

**Fix**: This is expected for GKE. The workflow dynamically retrieves cluster info. Ensure your `terraform.tfvars` has:
```hcl
gke_endpoint = ""        # Leave empty
gke_ca_certificate = ""  # Leave empty
```

---

