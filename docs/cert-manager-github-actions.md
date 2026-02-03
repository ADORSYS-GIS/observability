# cert-manager GitHub Actions Deployment

Automated TLS certificate management deployment using GitHub Actions CI/CD workflows.

**Official Documentation**: [cert-manager.io](https://cert-manager.io/docs/) | **Helm Chart**: [artifacthub.io/packages/helm/cert-manager/cert-manager](https://artifacthub.io/packages/helm/cert-manager/cert-manager) | **Version**: `v1.19.2`

> **Already have cert-manager installed?** If you want to manage an existing cert-manager deployment with GitHub Actions, see [Adopting Existing Installation](adopting-cert-manager.md).

---

## Overview

This deployment method uses GitHub Actions workflows to automatically deploy cert-manager to Kubernetes clusters via Terraform. The workflows handle backend configuration, authentication, and deployment across GKE, EKS, and AKS.

**Key Features:**
- Automated Terraform backend configuration (GCS/S3/Azure Blob)
- Cloud provider authentication via GitHub Secrets
- Terraform plan review with artifact storage
- Deployment verification (pod readiness, ClusterIssuer configuration)
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
| NGINX Ingress Controller | Must be deployed first ([deployment guide](ingress-controller-github-actions.md)) |
| Let's Encrypt email | Valid email address for certificate notifications |

**Note:** NGINX Ingress Controller must be deployed before cert-manager for HTTP-01 ACME challenge validation.

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
| `LETSENCRYPT_EMAIL` | Email for Let's Encrypt notifications |

**Create service account (if you don't already have one):**
```bash
# Create service account for Terraform deployments
gcloud iam service-accounts create terraform-deployer \
  --display-name="Terraform Deployment Account"

# Grant Kubernetes admin permissions
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:terraform-deployer@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/container.admin"

# Grant cloud storage permissions for Terraform state
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:terraform-deployer@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/storage.objectAdmin"

# Create and download service account key
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
| `LETSENCRYPT_EMAIL` | Email for Let's Encrypt notifications |

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
| `LETSENCRYPT_EMAIL` | Email for Let's Encrypt notifications |

**Create service principal:**
```bash
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
| `CERT_MANAGER_VERSION` | Helm chart version | `v1.19.2` | `v1.20.0` |
| `CERT_MANAGER_NAMESPACE` | Kubernetes namespace | `cert-manager` | `cert-manager` |
| `CERT_MANAGER_RELEASE_NAME` | Helm release name | `cert-manager` | `cert-manager-prod` |

### Step 3: Workflow Overview

Deployment workflows are available in [`.github/workflows/`](../.github/workflows/) for each cloud provider:

| Provider | Workflow File | Backend Storage |
|----------|---------------|-----------------|
| **GKE** | [`deploy-cert-manager-gke.yaml`](../.github/workflows/deploy-cert-manager-gke.yaml) | Google Cloud Storage |
| **EKS** | [`deploy-cert-manager-eks.yaml`](../.github/workflows/deploy-cert-manager-eks.yaml) | AWS S3 + DynamoDB |
| **AKS** | [`deploy-cert-manager-aks.yaml`](../.github/workflows/deploy-cert-manager-aks.yaml) | Azure Blob Storage |

Each workflow handles authentication, backend configuration, Terraform execution, and deployment verification. Review the workflow files for detailed inline documentation.

---

### Step 4: Deploy cert-manager

**Option A: Manual Trigger**

Navigate to repository Actions tab, select the appropriate workflow for your cloud provider, click "Run workflow", and configure options:

**Workflow Options:**
- **Terraform Action**: Choose `plan` (preview changes) or `apply` (deploy)
- **Import existing resources**: Check this box to automatically import existing cert-manager installations into Terraform state (optional, see below)

**Option B: Automatic Trigger**

Push changes to `main` branch affecting cert-manager Terraform files to trigger automatic deployment.

---

## Adopting Existing cert-manager Installation

If you already have cert-manager installed in your cluster and want to manage it with Terraform, use the **automated import feature**.

### How It Works

1. Go to Actions → Select cert-manager workflow
2. Click "Run workflow"
3. ☑ **Check** "Import existing resources into Terraform state"
4. Select `apply`
5. Run workflow

The workflow will:
- Detect existing cert-manager Helm release
- Automatically import it into Terraform state
- Continue managing it with Terraform (no recreation, no downtime)

### What Gets Imported

- Helm release: `cert-manager/cert-manager`
- Existing namespace: `cert-manager`
- All existing resources remain untouched

### Important Notes

- **No downtime**: Import does not recreate resources
- **Safe operation**: Gracefully handles resources already in state
- **Optional**: Fresh deployments don't need this (leave unchecked)
- **One-time**: Only needed for initial adoption

For manual adoption steps, see [Adopting cert-manager guide](adopting-cert-manager.md).

---

## Verification

After successful workflow completion, verify the deployment:

```bash
# Check pod status (expect 3 running pods)
kubectl get pods -n cert-manager
```

![cert-manager pods running](img/cert-manager-pods.png)

```bash
# Verify ClusterIssuer
kubectl get clusterissuer letsencrypt-prod
```

![ClusterIssuer ready status](img/cert-manager-clusterissuer.png)

```bash
# Detailed ClusterIssuer information
kubectl describe clusterissuer letsencrypt-prod
```

---

## Usage

For usage examples and configuring automatic TLS certificates, see [cert-manager README](../cert-manager/README.md#usage-example).

---

## Upgrading cert-manager

### Option 1: Using GitHub Variables (Recommended)

1. Navigate to: Repository → **Settings** → **Secrets and variables** → **Actions** → **Variables**
2. Update `CERT_MANAGER_VERSION` to new version (e.g., `v1.20.0`)
3. Run the deployment workflow (manually trigger or push to main)

The workflow automatically detects the version change and performs an in-place Helm upgrade with zero downtime.

### Option 2: Edit Workflow File (Legacy Method)

1. Edit workflow file (e.g., `.github/workflows/deploy-cert-manager-gke.yaml`)
2. Locate the environment variables section at the top:
   ```yaml
   env:
     CERT_MANAGER_VERSION: ${{ vars.CERT_MANAGER_VERSION || 'v1.19.2' }}
   ```
3. Change the default value:
   ```yaml
   env:
     CERT_MANAGER_VERSION: ${{ vars.CERT_MANAGER_VERSION || 'v1.20.0' }}
   ```
4. Commit and push changes

**Note:** Using GitHub Variables (Option 1) is recommended as it doesn't require workflow file changes.

---

## Uninstalling

Navigate to repository Actions tab, select the [`destroy-cert-manager.yaml`](../.github/workflows/destroy-cert-manager.yaml) workflow, select your cloud provider, and type `DESTROY` to confirm removal.

---

## Troubleshooting

### Workflow Failures

**Cannot connect to cluster:**
- Verify GitHub Secrets: Settings → Secrets and variables → Actions
- GKE: `GCP_SA_KEY`, `CLUSTER_NAME`, `CLUSTER_LOCATION`
- EKS: AWS credentials, `CLUSTER_NAME`, `AWS_REGION`
- AKS: `AZURE_CREDENTIALS`, `CLUSTER_NAME`, `RESOURCE_GROUP`

**Terraform backend error:**
- Verify state bucket exists and is accessible
- Confirm service account has storage permissions
- Check `TF_STATE_BUCKET` secret is correctly set

For cert-manager-specific issues, see [Troubleshooting Guide](troubleshooting-cert-manager.md).

---

## State Management

Terraform state files are stored in cloud storage:

| Provider | Backend Type | State File Path |
|----------|--------------|-----------------|
| GKE | Google Cloud Storage | `gs://<TF_STATE_BUCKET>/terraform/cert-manager/terraform.tfstate` |
| EKS | S3 + DynamoDB Lock | `s3://<TF_STATE_BUCKET>/terraform/cert-manager/terraform.tfstate` |
| AKS | Azure Blob Storage | `https://<STORAGE_ACCOUNT>.blob.core.windows.net/<CONTAINER>/terraform/cert-manager/terraform.tfstate` |

The backend configuration script creates `backend-config.tf` for each workflow run but preserves existing state files.

**Manual State Inspection:**
```bash
cd cert-manager/terraform

export TF_STATE_BUCKET="your-bucket"
bash ../../.github/scripts/configure-backend.sh gke cert-manager

terraform init
terraform show
```

---

## Advanced Configuration

### Customize Deployment Settings

Edit the workflow's `terraform.tfvars` generation section (approximately line 148-162):

```yaml
- name: Create terraform.tfvars
  working-directory: ${{ env.WORKING_DIR }}
  run: |
    cat > terraform.tfvars <<EOF
    cloud_provider       = "${{ env.CLOUD_PROVIDER }}"
    install_cert_manager = true
    create_issuer        = true
    release_name         = "cert-manager"
    cert_manager_version = "v1.19.2"
    namespace            = "cert-manager"
    letsencrypt_email    = "${{ secrets.LETSENCRYPT_EMAIL }}"
    cert_issuer_name     = "letsencrypt-prod"
    cert_issuer_kind     = "ClusterIssuer"
    issuer_server        = "https://acme-v02.api.letsencrypt.org/directory"
    ingress_class_name   = "nginx"
    EOF
```

**Available Customizations:**
- `namespace`: Deployment namespace (default: `cert-manager`)
- `cert_issuer_name`: ClusterIssuer name (default: `letsencrypt-prod`)
- `issuer_server`: ACME server URL (production or staging)
- `release_name`: Helm release name (default: `cert-manager`)

---

## Related Documentation

- [Manual Deployment Guide](cert-manager-manual-deployment.md) - Helm CLI installation
- [Terraform CLI Deployment](cert-manager-terraform-deployment.md) - Infrastructure as Code deployment
- [Ingress Controller Deployment](ingress-controller-github-actions.md) - Required dependency
- [Troubleshooting Guide](troubleshooting-cert-manager.md) - Detailed debugging procedures
- [Official cert-manager Documentation](https://cert-manager.io/docs/) - Upstream reference
