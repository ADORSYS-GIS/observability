# cert-manager Terraform CLI Deployment

Infrastructure as Code deployment using Terraform for reproducible, version-controlled deployments.

Recommended for teams using infrastructure as code workflows, multi-environment deployments, or requiring reproducible configurations. This method provides full control over Terraform execution from your local machine or CI/CD pipeline.

**Official Documentation**: [cert-manager.io](https://cert-manager.io/docs/) | **GitHub**: [cert-manager/cert-manager](https://github.com/cert-manager/cert-manager) | **Version**: `v1.19.2`

---

## Prerequisites

Required tools and versions:

| Tool | Version | Verification Command |
|------|---------|---------------------|
| Terraform | ≥ 1.0 | `terraform version` |
| kubectl | ≥ 1.24 | `kubectl version --client` |
| Kubernetes cluster | ≥ 1.24 | `kubectl version --short` |

**Cloud Provider Requirements:**
- GKE: gcloud CLI authenticated (`gcloud auth login`)
- EKS: AWS CLI authenticated (`aws configure`)
- AKS: Azure CLI authenticated (`az login`)
- Generic: kubectl configured with cluster access

**Dependencies:**
- NGINX Ingress Controller must be deployed first ([deployment guide](ingress-controller-terraform-deployment.md))
- Cluster access configured (`kubectl cluster-info`)

---

## Terraform State Management

This deployment uses remote state backends for collaboration and state persistence.

**Backend Configuration:**

| Provider | Backend | State Path |
|----------|---------|-----------|
| GKE | Google Cloud Storage (GCS) | `gs://<bucket>/terraform/cert-manager/terraform.tfstate` |
| EKS | AWS S3 + DynamoDB locking | `s3://<bucket>/terraform/cert-manager/terraform.tfstate` |
| AKS | Azure Blob Storage | `azurerm://<container>/terraform/cert-manager/terraform.tfstate` |
| Generic | Local or custom remote backend | `./terraform.tfstate` (local) |

The backend configuration is generated automatically by the `configure-backend.sh` script or manually created.

For detailed state management documentation, see [Terraform State Management Guide](terraform-state-management.md).

---

## Installation

### Step 1: Navigate to Terraform Directory

```bash
cd cert-manager/terraform
```

---

### Step 2: Configure Backend (Required for Remote State)

**Option A: Using the configuration script (recommended)**

For GKE:
```bash
../../.github/scripts/configure-backend.sh gke cert-manager
```

For EKS:
```bash
export TF_STATE_BUCKET="your-s3-bucket"
export AWS_REGION="us-east-1"
export TF_STATE_LOCK_TABLE="terraform-state-lock"  # Optional
../../.github/scripts/configure-backend.sh eks cert-manager
```

For AKS:
```bash
export AZURE_STORAGE_ACCOUNT="yourstorageaccount"
export AZURE_STORAGE_CONTAINER="terraform-state"
../../.github/scripts/configure-backend.sh aks cert-manager
```

For generic Kubernetes (local state):
```bash
../../.github/scripts/configure-backend.sh generic cert-manager
```

This creates `backend-config.tf` with the appropriate backend configuration.

**Option B: Manual backend configuration**

Create `backend-config.tf`:

For GKE (GCS backend):
```hcl
terraform {
  backend "gcs" {
    bucket = "your-gcs-bucket"
    prefix = "terraform/cert-manager"
  }
}
```

For EKS (S3 backend):
```hcl
terraform {
  backend "s3" {
    bucket         = "your-s3-bucket"
    key            = "terraform/cert-manager/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock"  # Optional, for state locking
  }
}
```

For AKS (Azure Blob backend):
```hcl
terraform {
  backend "azurerm" {
    storage_account_name = "yourstorageaccount"
    container_name       = "terraform-state"
    key                  = "terraform/cert-manager/terraform.tfstate"
  }
}
```

---

### Step 3: Create Configuration File

Copy the template and customize:

```bash
cp terraform.tfvars.template terraform.tfvars
```

Edit `terraform.tfvars`:

**Minimal configuration:**
```hcl
# Cloud Provider (gke, eks, aks, or generic)
cloud_provider = "gke"

# Installation Control
install_cert_manager = true
create_issuer        = true

# Let's Encrypt Configuration
letsencrypt_email = "admin@yourcompany.com"

# Optional: Version override
cert_manager_version = "v1.19.2"
```

**Full configuration options:**

```hcl
# ==============================================================================
# Cert-Manager Terraform Configuration
# ==============================================================================

# Cloud Provider
cloud_provider = "gke"  # Options: gke, eks, aks, generic

# GKE-specific (required for GKE)
project_id = "your-gcp-project-id"
region     = "us-central1"

# EKS-specific (required for EKS)
aws_region = "us-east-1"

# Installation Control
install_cert_manager = true   # Set false to manage existing installation
create_issuer        = true   # Set false to create issuer separately

# Helm Release
release_name         = "cert-manager"
namespace            = "cert-manager"
cert_manager_version = "v1.19.2"

# Certificate Issuer Configuration
letsencrypt_email  = "admin@yourcompany.com"
cert_issuer_kind   = "ClusterIssuer"  # or "Issuer" for namespace-scoped
cert_issuer_name   = "letsencrypt-prod"
issuer_namespace   = ""               # Required if cert_issuer_kind = "Issuer"

# ACME Configuration
ingress_class_name = "nginx"
issuer_server      = "https://acme-v02.api.letsencrypt.org/directory"

# For testing, use staging server to avoid rate limits:
# issuer_server = "https://acme-staging-v02.api.letsencrypt.org/directory"
```

**Configuration Variables:**

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `cloud_provider` | Target platform (gke/eks/aks/generic) | `gke` | Yes |
| `install_cert_manager` | Install cert-manager or manage existing | `false` | Yes |
| `letsencrypt_email` | Email for Let's Encrypt notifications | - | Yes |
| `cert_manager_version` | Chart version to install | `v1.19.2` | No |
| `create_issuer` | Create ClusterIssuer/Issuer | `true` | No |
| `cert_issuer_kind` | ClusterIssuer or Issuer | `ClusterIssuer` | No |
| `cert_issuer_name` | Name of issuer resource | `letsencrypt-prod` | No |
| `ingress_class_name` | Ingress class for HTTP-01 challenges | `nginx` | No |
| `issuer_server` | ACME server URL | Let's Encrypt prod | No |

---

### Step 4: Authenticate to Kubernetes Cluster

**For GKE:**
```bash
gcloud auth login
gcloud config set project YOUR_PROJECT_ID
gcloud container clusters get-credentials CLUSTER_NAME --region REGION
```

**For EKS:**
```bash
aws configure
aws eks update-kubeconfig --name CLUSTER_NAME --region REGION
```

**For AKS:**
```bash
az login
az account set --subscription SUBSCRIPTION_ID
az aks get-credentials --resource-group RESOURCE_GROUP --name CLUSTER_NAME
```

**Verify access:**
```bash
kubectl cluster-info
kubectl get nodes
```

---

### Step 5: Initialize Terraform

```bash
terraform init
```

Expected output:
```
Initializing the backend...
Successfully configured the backend "gcs"!

Initializing provider plugins...
- Installing hashicorp/helm v2.12.x...
- Installing hashicorp/kubernetes v2.x...
- Installing hashicorp/google v5.x...

Terraform has been successfully initialized!
```

---

### Step 6: Plan Deployment

Review changes before applying:

```bash
terraform plan
```

**Review the plan output:**
- Helm release `cert-manager` will be created
- Namespace `cert-manager` will be created
- ClusterIssuer `letsencrypt-prod` will be created

Example output:
```
Terraform will perform the following actions:

  # helm_release.cert_manager[0] will be created
  + resource "helm_release" "cert_manager" {
      + chart            = "cert-manager"
      + namespace        = "cert-manager"
      + version          = "v1.19.2"
      ...
    }

  # null_resource.letsencrypt_issuer[0] will be created
  + resource "null_resource" "letsencrypt_issuer" {
      + triggers = {
          + cert_issuer_name = "letsencrypt-prod"
          ...
        }
    }

Plan: 3 to add, 0 to change, 0 to destroy.
```

---

### Step 7: Apply Configuration

Deploy cert-manager:

```bash
terraform apply
```

Review the plan and type `yes` when prompted.

Installation typically completes in 2-3 minutes.

**To skip confirmation prompt:**
```bash
terraform apply -auto-approve
```

---

### Step 8: Verify Deployment

Check cert-manager pods:

```bash
kubectl get pods -n cert-manager
```

Expected output:
```
NAME                                      READY   STATUS    RESTARTS   AGE
cert-manager-7d4c5d8f9c-xxxxx            1/1     Running   0          90s
cert-manager-cainjector-6d8f7b9c8-xxxxx  1/1     Running   0          90s
cert-manager-webhook-5f5d6b8c9d-xxxxx    1/1     Running   0          90s
```

Verify ClusterIssuer:

```bash
kubectl get clusterissuer letsencrypt-prod
```

Expected output:
```
NAME               READY   AGE
letsencrypt-prod   True    60s
```

Check detailed status:
```bash
kubectl describe clusterissuer letsencrypt-prod
```

---

## Usage

Configure automatic TLS for Ingress resources using the cert-manager annotation:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - myapp.example.com
      secretName: myapp-tls
  rules:
    - host: myapp.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: myapp-service
                port:
                  number: 80
```

Apply the Ingress:
```bash
kubectl apply -f myapp-ingress.yaml
```

Monitor certificate provisioning:
```bash
kubectl get certificate -A
kubectl describe certificate myapp-tls -n default
```

---

## Upgrading cert-manager

Update the version in `terraform.tfvars`:

```hcl
cert_manager_version = "v1.20.0"
```

Plan and apply the upgrade:

```bash
terraform plan
terraform apply
```

Terraform performs a rolling update with zero downtime.

---

## Managing Existing Installation

If cert-manager is already installed and you want Terraform to manage it:

1. Set `install_cert_manager = true` in `terraform.tfvars`
2. Import the existing Helm release:

```bash
terraform import 'helm_release.cert_manager[0]' cert-manager/cert-manager
```

3. Run `terraform plan` to verify no changes are detected

For detailed adoption procedures, see [Adopting Existing cert-manager Installation](adopting-cert-manager.md).

---

## Uninstalling

**Warning:** Uninstalling deletes all certificates. Applications will lose TLS functionality.

```bash
terraform destroy
```

Review the destruction plan and type `yes` when prompted.

This removes:
- Helm release `cert-manager`
- ClusterIssuer `letsencrypt-prod`
- Namespace `cert-manager`
- Custom Resource Definitions (CRDs)

---

## Multi-Environment Deployments

Use Terraform workspaces or separate tfvars files for multiple environments:

**Option A: Workspaces**
```bash
# Create and switch to production workspace
terraform workspace new production
terraform workspace select production
terraform apply -var-file="production.tfvars"

# Create and switch to staging workspace
terraform workspace new staging
terraform workspace select staging
terraform apply -var-file="staging.tfvars"
```

**Option B: Separate directories**
```
cert-manager/
├── terraform/
│   ├── environments/
│   │   ├── production/
│   │   │   └── terraform.tfvars
│   │   ├── staging/
│   │   │   └── terraform.tfvars
│   │   └── development/
│   │       └── terraform.tfvars
│   ├── main.tf
│   └── variables.tf
```

Deploy to specific environment:
```bash
cd cert-manager/terraform
terraform apply -var-file="environments/production/terraform.tfvars"
```

---

## Troubleshooting

### Backend Initialization Fails

**Error:** `Error configuring the backend "gcs"`

**Cause:** Missing credentials or incorrect bucket configuration

**Solution:**
```bash
# For GKE
gcloud auth application-default login
export GOOGLE_PROJECT=your-project-id

# For EKS
aws configure
export AWS_PROFILE=your-profile

# For AKS
az login
```

Verify backend configuration in `backend-config.tf`.

---

### Pods Not Starting

Check pod status and logs:
```bash
kubectl describe pod <pod-name> -n cert-manager
kubectl logs <pod-name> -n cert-manager
```

**Common causes:**
- CRDs not installed: Verify `installCRDs = true` in Terraform
- Insufficient cluster resources
- Image pull issues

---

### ClusterIssuer Not Ready

Check issuer status:
```bash
kubectl describe clusterissuer letsencrypt-prod
```

**Common issues:**

| Symptom | Cause | Resolution |
|---------|-------|-----------|
| Email validation pending | ACME registration in progress | Wait 30-60 seconds |
| Invalid email format | Incorrect email in tfvars | Update `letsencrypt_email` and reapply |
| HTTP-01 solver error | Ingress controller not installed | Deploy NGINX Ingress Controller first |

---

### Certificate Not Issuing

Monitor certificate creation:
```bash
kubectl get certificate -A
kubectl describe certificate <cert-name> -n <namespace>
kubectl get challenges -A
```

Review [Troubleshooting Guide](troubleshooting-cert-manager.md) for detailed debugging steps.

---

## Terraform Output Values

View deployment information:

```bash
terraform output
```

No outputs are currently defined. To add outputs, create `outputs.tf`:

```hcl
output "namespace" {
  description = "Namespace where cert-manager is installed"
  value       = var.namespace
}

output "release_name" {
  description = "Helm release name"
  value       = var.release_name
}

output "cert_manager_version" {
  description = "cert-manager version installed"
  value       = var.cert_manager_version
}

output "cluster_issuer_name" {
  description = "ClusterIssuer name"
  value       = var.cert_issuer_name
}
```

---

## Related Documentation

- [Manual Helm Deployment](cert-manager-manual-deployment.md) - Direct Helm command-line deployment
- [GitHub Actions Deployment](cert-manager-github-actions.md) - Automated CI/CD workflow
- [Terraform State Management](terraform-state-management.md) - Remote state configuration
- [Troubleshooting Guide](troubleshooting-cert-manager.md) - Common issues and resolutions
- [Adopting Existing Installation](adopting-cert-manager.md) - Migration guide

---

**Official Documentation**: [cert-manager.io/docs](https://cert-manager.io/docs/)
