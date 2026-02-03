# NGINX Ingress Controller GitHub Actions Deployment

Automated Layer 7 load balancing deployment using GitHub Actions CI/CD workflows.

**Official Documentation**: [NGINX Inc. Ingress Controller](https://docs.nginx.com/nginx-ingress-controller/) | **Helm Repository**: `https://helm.nginx.com/stable` | **Chart**: `nginx-ingress` | **Version**: `2.4.2`

> **Already have NGINX Ingress Controller installed?** If you want to manage an existing ingress controller deployment with GitHub Actions, see [Adopting Existing Installation](adopting-ingress-controller.md).

---

## Overview

This deployment method uses GitHub Actions workflows to automatically deploy NGINX Ingress Controller to Kubernetes clusters via Terraform. The workflows handle backend configuration, authentication, and deployment across GKE, EKS, and AKS.

**Key Features:**
- Automated Terraform backend configuration (GCS/S3/Azure Blob)
- Cloud provider authentication via GitHub Secrets
- Terraform plan review with artifact storage
- LoadBalancer provisioning with external IP assignment
- Deployment verification (IngressClass, pod readiness, external IP)
- Zero-downtime upgrades
- Remote state management

---

## Prerequisites

| Component | Requirement |
|-----------|-------------|
| Kubernetes cluster | GKE, EKS, or AKS (≥ 1.24) |
| GitHub repository | Admin or write permissions |
| Cloud credentials | Service account (GCP), IAM user (AWS), or Service Principal (Azure) |
| Remote state storage | GCS bucket, S3 bucket, or Azure Storage Container |
| LoadBalancer support | Cloud provider native load balancing |

**Note:** Deploy ingress controller before cert-manager. cert-manager depends on the ingress controller for HTTP-01 ACME challenge validation.

---

## Setup

### Step 1: Configure GitHub Secrets

Navigate to repository **Settings → Secrets and variables → Actions → New repository secret**

#### GKE (Google Kubernetes Engine)

| Secret Name | Description |
|-------------|-------------|
| `GCP_SA_KEY` | Base64-encoded service account JSON key |
| `GCP_PROJECT_ID` | GCP project ID |
| `CLUSTER_NAME` | GKE cluster name |
| `CLUSTER_LOCATION` | Cluster zone (e.g., `us-central1-a`) or region (e.g., `us-central1`) |
| `REGION` | GCP region |
| `TF_STATE_BUCKET` | GCS bucket name for Terraform state |

**Create service account (if you don't already have one):**
```bash
# Create service account for Terraform deployments
gcloud iam service-accounts create terraform-deployer \
  --display-name="Terraform Deployment Account"

# Grant Kubernetes cluster management permissions
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:terraform-deployer@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/container.admin"

# Grant GCS bucket access for Terraform state
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:terraform-deployer@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/storage.objectAdmin"

# Create service account key
gcloud iam service-accounts keys create key.json \
  --iam-account=terraform-deployer@YOUR_PROJECT_ID.iam.gserviceaccount.com

# Encode key for GitHub Secrets
cat key.json | base64 > key-base64.txt
```

#### EKS (Amazon Elastic Kubernetes Service)

| Secret Name | Description |
|-------------|-------------|
| `AWS_ACCESS_KEY_ID` | IAM user access key |
| `AWS_SECRET_ACCESS_KEY` | IAM user secret access key |
| `AWS_REGION` | AWS region |
| `CLUSTER_NAME` | EKS cluster name |
| `TF_STATE_BUCKET` | S3 bucket name for Terraform state |

**Required IAM permissions:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "eks:DescribeCluster",
        "eks:ListClusters",
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": "*"
    }
  ]
}
```

#### AKS (Azure Kubernetes Service)

| Secret Name | Description |
|-------------|-------------|
| `AZURE_CREDENTIALS` | Service principal JSON (from `az ad sp create-for-rbac --sdk-auth`) |
| `AZURE_STORAGE_ACCOUNT` | Storage account name for Terraform state |
| `AZURE_STORAGE_CONTAINER` | Blob container name for Terraform state |
| `AZURE_RESOURCE_GROUP` | Resource group containing AKS cluster |
| `CLUSTER_NAME` | AKS cluster name |

**Create service principal (if you don't already have one):**
```bash
# Create service principal with contributor role for AKS management
az ad sp create-for-rbac --name "terraform-deployer" \
  --role contributor \
  --scopes /subscriptions/YOUR_SUBSCRIPTION_ID/resourceGroups/YOUR_RG \
  --sdk-auth
```

Copy the entire JSON output to `AZURE_CREDENTIALS` secret.

---

### Step 2: Configure Repository Variables (Optional)

The workflows support GitHub repository variables for flexible configuration. If not set, sensible defaults are used automatically.

**Navigate to:** Repository → **Settings** → **Secrets and variables** → **Actions** → **Variables** tab

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `NGINX_INGRESS_VERSION` | Helm chart version | `2.4.2` | `2.5.0` |
| `NGINX_INGRESS_NAMESPACE` | Kubernetes namespace | `ingress-nginx` | `ingress-nginx` |
| `NGINX_INGRESS_RELEASE_NAME` | Helm release name | `nginx-monitoring` | `nginx-prod` |

### Step 3: Workflow Overview

Deployment workflows are available in [`.github/workflows/`](../.github/workflows/) for each cloud provider:

| Provider | Workflow File | Backend Storage |
|----------|---------------|-----------------|
| **GKE** | [`deploy-ingress-controller-gke.yaml`](../.github/workflows/deploy-ingress-controller-gke.yaml) | Google Cloud Storage |
| **EKS** | [`deploy-ingress-controller-eks.yaml`](../.github/workflows/deploy-ingress-controller-eks.yaml) | AWS S3 + DynamoDB |
| **AKS** | [`deploy-ingress-controller-aks.yaml`](../.github/workflows/deploy-ingress-controller-aks.yaml) | Azure Blob Storage |

Each workflow handles authentication, backend configuration, Terraform execution, and deployment verification. Review the workflow files for detailed inline documentation.

---

### Step 4: Deploy Ingress Controller

**Option A: Manual Trigger**

Navigate to repository Actions tab, select the appropriate workflow for your cloud provider, click "Run workflow", and configure options:

**Workflow Options:**
- **Terraform Action**: Choose `plan` (preview changes) or `apply` (deploy)
- **Import existing resources**: Check this box to automatically import existing ingress-controller installations into Terraform state (optional, see below)

**Option B: Automatic Trigger**

Push changes to `main` branch affecting ingress-controller Terraform files to trigger automatic deployment.

---

## Adopting Existing Ingress Controller Installation

If you already have NGINX Ingress Controller installed in your cluster and want to manage it with Terraform, use the **automated import feature**.

### How It Works

1. Go to Actions → Select ingress-controller workflow
2. Click "Run workflow"
3. ☑ **Check** "Import existing resources into Terraform state"
4. Select `apply`
5. Run workflow

The workflow will:
- Detect existing NGINX Ingress Controller Helm release
- Automatically import it into Terraform state
- Continue managing it with Terraform (no recreation, no downtime)

### What Gets Imported

- Helm release: `ingress-nginx/nginx-monitoring` (or your release name)
- Existing namespace: `ingress-nginx`
- All existing resources remain untouched

### Important Notes

- **No downtime**: Import does not recreate resources
- **Safe operation**: Gracefully handles resources already in state
- **Optional**: Fresh deployments don't need this (leave unchecked)
- **One-time**: Only needed for initial adoption

For manual adoption steps, see [Adopting ingress-controller guide](adopting-ingress-controller.md).

---

## Verification

After successful workflow completion, verify the deployment:

```bash
# Check pod status (expect 2 running pods)
kubectl get pods -n ingress-nginx
```

![NGINX Ingress Controller pods running](img/ingress-nginx-pods.png)

```bash
# Get LoadBalancer external IP
kubectl get svc -n ingress-nginx
```

![NGINX Ingress Controller LoadBalancer service](img/ingress-nginx-loadbalancer.png)

```bash
# Verify IngressClass
kubectl get ingressclass nginx
```

![NGINX IngressClass created](img/ingress-nginx-ingressclass.png)

---

## Usage

For usage examples and Ingress configuration, see [NGINX Ingress Controller README](../ingress-controller/README.md#usage-examples).

---

## Upgrading Ingress Controller

### Option 1: Using GitHub Variables (Recommended)

1. Navigate to: Repository → **Settings** → **Secrets and variables** → **Actions** → **Variables**
2. Update `NGINX_INGRESS_VERSION` to new version (e.g., `2.5.0`)
3. Run the deployment workflow (manually trigger or push to main)

The workflow automatically detects the version change and performs an in-place Helm upgrade with zero downtime.

### Option 2: Edit Workflow File (Legacy Method)

1. Edit workflow file (e.g., `.github/workflows/deploy-ingress-controller-gke.yaml`)
2. Locate the environment variables section at the top:
   ```yaml
   env:
     NGINX_INGRESS_VERSION: ${{ vars.NGINX_INGRESS_VERSION || '2.4.2' }}
   ```
3. Update the default value:
   ```yaml
   env:
     NGINX_INGRESS_VERSION: ${{ vars.NGINX_INGRESS_VERSION || '2.5.0' }}
   ```
4. Commit and push:
   ```bash
   git add .github/workflows/deploy-ingress-controller-gke.yaml
   git commit -m "Upgrade ingress-nginx to v2.5.0"
   git push origin main
   ```

Workflow executes automatically, performing an in-place Helm upgrade with zero downtime.

---

## Uninstalling

Navigate to repository Actions tab, select the [`destroy-ingress-controller.yaml`](../.github/workflows/destroy-ingress-controller.yaml) workflow, select your cloud provider, and type `DESTROY` to confirm removal.

---

## Troubleshooting

### Workflow Failures

**Cannot connect to cluster:**
- Verify GitHub Secrets: Settings → Secrets and variables → Actions
- GKE: `GCP_SA_KEY`, `CLUSTER_NAME`, `CLUSTER_LOCATION`
- EKS: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `CLUSTER_NAME`, `AWS_REGION`
- AKS: `AZURE_CREDENTIALS`, `CLUSTER_NAME`, `AZURE_RESOURCE_GROUP`

**Terraform backend error:**
- Verify state bucket exists and is accessible
- Confirm service account has storage permissions
- Check `TF_STATE_BUCKET` secret is correctly set

For ingress-specific issues, see [Troubleshooting Guide](troubleshooting-ingress-controller.md).

---

## State Management

Terraform state storage locations:

| Provider | Backend | State File Path |
|----------|---------|-----------------|
| **GKE** | Google Cloud Storage | `gs://<TF_STATE_BUCKET>/terraform/ingress-controller/terraform.tfstate` |
| **EKS** | S3 + DynamoDB Lock | `s3://<TF_STATE_BUCKET>/terraform/ingress-controller/terraform.tfstate` |
| **AKS** | Azure Blob Storage | `https://<STORAGE_ACCOUNT>.blob.core.windows.net/<CONTAINER>/terraform/ingress-controller/terraform.tfstate` |

Backend configuration files regenerate on each workflow run, but state files persist across deployments.

**Inspect state manually:**

```bash
cd ingress-controller/terraform

# Configure backend (same process as workflow)
export TF_STATE_BUCKET="your-bucket"
bash ../../.github/scripts/configure-backend.sh gke ingress-controller

# Initialize and view state
terraform init
terraform show
terraform state list
```

---

## Advanced Configuration

To customize deployment parameters, edit the `terraform.tfvars` generation section in the workflow file (approximately lines 148-160):

```yaml
- name: Create terraform.tfvars
  working-directory: ${{ env.WORKING_DIR }}
  run: |
    cat > terraform.tfvars <<EOF
    cloud_provider        = "${{ env.CLOUD_PROVIDER }}"
    install_ingress_nginx = true
    release_name          = "nginx-monitoring"
    ingress_nginx_version = "2.4.2"
    namespace             = "ingress-nginx"
    ingress_class_name    = "nginx"
    replica_count         = 2
    EOF
```

**Common customizations:**
- `replica_count = 3` - Increase replicas for high availability
- `namespace = "custom-ingress"` - Use custom namespace
- `ingress_class_name = "nginx-prod"` - Define alternative IngressClass name
- `release_name = "my-ingress"` - Specify custom Helm release name

For advanced Helm values, modify the Terraform module inputs in `ingress-controller/terraform/main.tf`.

---

## Related Documentation

- [Manual Deployment Guide](ingress-controller-manual-deployment.md) - Helm CLI deployment
- [Terraform CLI Deployment](ingress-controller-terraform-deployment.md) - Infrastructure as Code deployment
- [cert-manager Setup](cert-manager-github-actions.md) - TLS automation
- [Troubleshooting Guide](troubleshooting-ingress-controller.md) - Detailed debugging

---

**Official Documentation**: [NGINX Inc. Ingress Controller](https://docs.nginx.com/nginx-ingress-controller/) | **Helm Repository**: `https://helm.nginx.com/stable`
