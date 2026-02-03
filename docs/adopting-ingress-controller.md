# Adopting Existing NGINX Ingress Controller Installation

This guide walks you through adopting an existing NGINX Ingress Controller installation into Terraform management and integrating it with GitHub Actions workflows.

> **Automated Option Available**: If you're using GitHub Actions workflows, there's now an **automated import feature** that handles adoption automatically. See [ingress-controller GitHub Actions guide](ingress-controller-github-actions.md#adopting-existing-ingress-controller-installation) for the one-click approach. This guide covers manual adoption steps.

> **When to Use This Guide**: If you already have NGINX Ingress Controller deployed (via Helm, kubectl, or other means) and want to manage it with Terraform and automate future deployments with GitHub Actions.

## Overview

Adoption involves:
1. **Importing** existing Helm releases and Kubernetes resources into Terraform state
2. **Configuring** Terraform variables to match your current setup
3. **Integrating** with GitHub Actions workflows for future automated deployments

## Prerequisites

- Existing NGINX Ingress Controller installation in your cluster
- Terraform >= 1.5.0
- `kubectl` configured for your cluster
- `helm` CLI installed
- Cloud provider CLI configured (for GitHub Actions integration):
  - **GKE**: `gcloud` CLI
  - **EKS**: `aws` CLI
  - **AKS**: `az` CLI

## Step 1: Discover Existing Installation

Run these commands to gather information about your current NGINX Ingress Controller setup:

```bash
# 1. Find the Helm release
helm list -A | grep ingress

# Expected output format:
# RELEASE_NAME         NAMESPACE       REVISION  UPDATED                   STATUS    CHART                    APP_VERSION
# nginx-monitoring     ingress-nginx   1         2025-12-08 11:23:11...    deployed  nginx-ingress-2.4.2      5.3.2

# 2. Check the namespace
kubectl get ns | grep ingress

# 3. Verify IngressClass
kubectl get ingressclass

# Expected output:
# NAME    CONTROLLER             PARAMETERS   AGE
# nginx   k8s.io/ingress-nginx   <none>       30d

# 4. Check LoadBalancer service
kubectl get svc -n ingress-nginx
```

**Record these values**:
- Release name (e.g., `nginx-monitoring`)
- Namespace (e.g., `ingress-nginx`)
- Chart version (e.g., `2.4.2`)
- IngressClass name (e.g., `nginx`)
- Number of controller replicas

---

## Step 2: Configure `terraform.tfvars`

Navigate to the Terraform directory:

```bash
cd ingress-controller/terraform
```

> **Critical**: You MUST set `install_nginx_ingress = true` to create the Terraform resource configuration before importing.

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
install_nginx_ingress = true

# Match your existing installation
nginx_ingress_version = "2.4.2"         # From helm list
namespace             = "ingress-nginx"  # From helm list
release_name          = "nginx-monitoring"  # From helm list (adjust if different)

# IngressClass configuration
ingress_class_name = "nginx"             # From kubectl get ingressclass

# Match current replica count
replica_count = 1  # Adjust based on your deployment
```

### Multi-Cloud Backend Configuration

For GitHub Actions integration, you'll need a backend for Terraform state storage.

> **New to state storage?** See the [Terraform State Management Guide](terraform-state-management.md#setting-up-state-storage) for complete bucket/storage setup instructions.

**GKE (Google Cloud Storage)**:
```bash
# Set environment variable for backend configuration
export TF_STATE_BUCKET="your-gcs-bucket-name"

# Configure backend using the provided script
bash ../../.github/scripts/configure-backend.sh gke ingress-controller
```

**EKS (AWS S3)**:
```bash
export TF_STATE_BUCKET="your-s3-bucket-name"
export AWS_REGION="us-east-1"

bash ../../.github/scripts/configure-backend.sh eks ingress-controller
```

**AKS (Azure Blob Storage)**:
```bash
export AZURE_STORAGE_ACCOUNT="yourstorageaccount"
export AZURE_STORAGE_CONTAINER="tfstate"

bash ../../.github/scripts/configure-backend.sh aks ingress-controller
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
terraform import 'helm_release.nginx_ingress[0]' ingress-nginx/nginx-monitoring
```

**Expected output**:
```
helm_release.nginx_ingress[0]: Importing from ID "ingress-nginx/nginx-monitoring"...
helm_release.nginx_ingress[0]: Import prepared!
  Prepared helm_release for import
helm_release.nginx_ingress[0]: Refreshing state... [id=nginx-monitoring]

Import successful!
```

### Troubleshooting Import

**Error: "Kubernetes cluster unreachable"**

**Fix**: Export kubeconfig path:
```bash
export KUBE_CONFIG_PATH=~/.kube/config
terraform import 'helm_release.nginx_ingress[0]' ingress-nginx/nginx-monitoring
```

**Error: "Configuration for import target does not exist"**

**Fix**: Ensure `install_nginx_ingress = true` in `terraform.tfvars`:
```bash
# Set install_nginx_ingress = true
terraform plan  # Creates resource config
terraform import 'helm_release.nginx_ingress[0]' ingress-nginx/nginx-monitoring
```

---

## Step 5: Verify the Import

```bash
terraform plan
```

**Expected output**: Should show **no changes** or only minor metadata updates.

**Acceptable changes**:
- Addition of Terraform-managed labels/annotations
- Default values being set explicitly

**Red flags** (review carefully):
- Changes to replica count
- Changes to IngressClass name
- Changes to LoadBalancer service type
- Resource requests/limits modifications

If you see major changes, **STOP** and review your `terraform.tfvars` values against the current deployment.

---

## Common Issues

### Error: "Release already exists"

**Cause**: The Helm release name conflicts with an existing release.

**Fix**: Import the existing release (Step 4) or use a different release name.

---

### Error: "IngressClass conflicts"

**Symptoms**: Terraform wants to modify or recreate the IngressClass.

**Diagnosis**:
```bash
# Check current IngressClass
kubectl get ingressclass -o yaml

# Verify IngressClass name matches
kubectl get ingressclass nginx -o jsonpath='{.metadata.name}'
```

**Fix**: Ensure `ingress_class_name` in `terraform.tfvars` matches exactly:
```hcl
ingress_class_name = "nginx"  # Must match existing IngressClass
```

---

### Error: "Namespace annotation mismatch"

**Symptoms**: Terraform detects namespace ownership conflicts.

**Diagnosis**:
```bash
# Check namespace annotations
kubectl get namespace ingress-nginx -o yaml | grep -A 5 "annotations:"
```

**Fix**: Usually safe to ignore if only Helm metadata annotations differ. If Terraform wants to recreate the namespace, consider managing it separately.

---

### Drift Detection After Import

**Issue**: `terraform plan` shows changes after successful import.

**Common causes**:

1. **Replica count mismatch**:
```bash
# Check current replicas
kubectl get deployment -n ingress-nginx

# Update terraform.tfvars
replica_count = <current_count>
```

2. **Chart version mismatch**:
```bash
# Verify chart version
helm list -n ingress-nginx

# Update terraform.tfvars
nginx_ingress_version = "<actual_version>"
```

3. **Resource limits not set**:
If your current deployment has custom resource limits, add them to a custom values file or variables.

---

## Advanced: Importing Multiple Resources

If you have multiple Ingress Controllers (e.g., internal and external):

```bash
# Import first controller
terraform import 'helm_release.nginx_ingress[0]' ingress-nginx/nginx-monitoring

# Import second controller (requires module modification)
terraform import 'helm_release.nginx_ingress_internal[0]' ingress-nginx-internal/nginx-internal
```

**Note**: This requires modifying your Terraform configuration to support multiple instances.

---

## Post-Import Best Practices

### 1. Test in Non-Production First

Before adopting production Ingress Controllers:
- Test the adoption process in staging/dev
- Verify `terraform plan` shows no destructive changes
- Ensure DNS and traffic routing remain functional

### 2. Backup Current Configuration

```bash
# Backup Helm values
helm get values nginx-monitoring -n ingress-nginx > backup-helm-values.yaml

# Backup Kubernetes resources
kubectl get all,ingress,ingressclass -n ingress-nginx -o yaml > backup-k8s-resources.yaml
```

### 3. Monitor After Adoption

```bash
# Watch pod status
kubectl get pods -n ingress-nginx -w

# Monitor LoadBalancer service
kubectl get svc -n ingress-nginx -w

# Check ingress resources
kubectl get ingress -A
```

---

## Rollback Plan

If adoption causes issues:

1. **Remove from Terraform state**:
```bash
terraform state rm 'helm_release.nginx_ingress[0]'
```

2. **Restore Helm management** (if needed):
```bash
# Helm will detect existing release and resume management
helm upgrade nginx-monitoring ingress-nginx/ingress-nginx -n ingress-nginx
```

---

## Import Script

For convenience, here's a complete import script:

```bash
#!/bin/bash
set -e

NAMESPACE="ingress-nginx"
RELEASE_NAME="nginx-monitoring"

echo "Verifying existing installation..."
helm list -n ${NAMESPACE} | grep ${RELEASE_NAME}

echo "Importing Helm release into Terraform..."
terraform import "helm_release.nginx_ingress[0]" "${NAMESPACE}/${RELEASE_NAME}"

echo "Verifying import..."
terraform plan

echo "Success! Review the plan above before applying changes."
```

Save as `import-ingress.sh`, make executable (`chmod +x import-ingress.sh`), and run.

---

## Step 6: Integrate with GitHub Actions (Optional)

After successfully adopting your NGINX Ingress Controller installation, you can optionally automate future deployments with GitHub Actions.

For complete GitHub Actions setup instructions, see [Ingress Controller GitHub Actions Deployment Guide](ingress-controller-github-actions.md).

---

## Next Steps

After successful adoption:

1. **Commit State**: Push Terraform state to remote backend if using remote state
2. **Monitor**: Run `terraform plan` regularly to detect configuration drift
3. **Document**: Update team runbooks with the adopted configuration
4. **Upgrade**: Test ingress controller version upgrades in non-production first

---