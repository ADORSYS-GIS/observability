# cert-manager GitHub Actions Deployment

Automated TLS certificate management deployment using GitHub Actions CI/CD workflows.

**Official Documentation**: [cert-manager.io](https://cert-manager.io/docs/) | **Helm Chart**: [artifacthub.io/packages/helm/cert-manager/cert-manager](https://artifacthub.io/packages/helm/cert-manager/cert-manager) | **Version**: `v1.19.2`

---

## Overview

This deployment method uses GitHub Actions workflows to automatically deploy cert-manager to Kubernetes clusters via Terraform. The workflows handle backend configuration, authentication, and deployment across GKE, EKS, and AKS.

**Key Features:**
- Automated Terraform backend configuration (GCS/S3/Azure Blob)
- Cloud provider authentication via GitHub Secrets
- Pull request-based plan review with automated comments
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

**Create service account:**
```bash
gcloud iam service-accounts create terraform-deployer \
  --display-name="Terraform Deployment Account"

gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:terraform-deployer@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/container.admin"

gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:terraform-deployer@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/storage.objectAdmin"

gcloud iam service-accounts keys create key.json \
  --iam-account=terraform-deployer@YOUR_PROJECT_ID.iam.gserviceaccount.com

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

### Step 2: Workflow Overview

Three workflows are available in `.github/workflows/`:

#### deploy-cert-manager-gke.yaml

**Triggers:**
- Manual: Actions tab → Deploy cert-manager (GKE) → Run workflow
- Automatic: Push to `main` when cert-manager files change
- Pull requests: Runs plan and comments result

**Workflow Steps:**
1. Authenticates to GKE cluster
2. Configures GCS backend for Terraform state
3. Runs `terraform plan` to preview changes
4. On `main` push or manual apply: deploys cert-manager v1.19.2
5. Verifies pod readiness and ClusterIssuer configuration

#### deploy-cert-manager-eks.yaml

Same workflow for AWS EKS with S3 backend.

#### deploy-cert-manager-aks.yaml

Same workflow for Azure AKS with Blob Storage backend.

---

### Step 3: Deploy cert-manager

#### Option A: Manual Trigger

1. Navigate to **Actions** tab in GitHub repository
2. Select workflow: `Deploy cert-manager (GKE/EKS/AKS)`
3. Click **Run workflow**
4. Select action:
   - `plan` - Preview changes without applying
   - `apply` - Deploy cert-manager
5. Click **Run workflow** button

**Typical execution time:** 3-4 minutes

#### Option B: Automatic Trigger

Commit and push changes to cert-manager Terraform files:

```bash
git add cert-manager/terraform/
git commit -m "Configure cert-manager deployment"
git push origin main
```

Workflow executes automatically. For pull requests, plan results appear as PR comments.

---

## Verification

After successful workflow completion, verify the deployment:

```bash
# Verify namespace
kubectl get namespace cert-manager

# Check pod status (expect 3 running pods)
kubectl get pods -n cert-manager

# Expected output:
# NAME                                       READY   STATUS    RESTARTS   AGE
# cert-manager-7d4c5d8f9c-xxxxx             1/1     Running   0          2m
# cert-manager-cainjector-6d8f7b9c8-xxxxx   1/1     Running   0          2m
# cert-manager-webhook-5f5d6b8c9d-xxxxx     1/1     Running   0          2m

# Verify ClusterIssuer
kubectl get clusterissuer letsencrypt-prod

# Expected output:
# NAME               READY   AGE
# letsencrypt-prod   True    2m

# Detailed ClusterIssuer information
kubectl describe clusterissuer letsencrypt-prod
```

---

## Usage

### Request TLS Certificate

Add cert-manager annotation to Ingress resources:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: example-app
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - app.example.com
      secretName: app-tls  # cert-manager creates this Secret
  rules:
    - host: app.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: app-service
                port:
                  number: 80
```

Apply the Ingress:
```bash
kubectl apply -f app-ingress.yaml
```

### Monitor Certificate Issuance

```bash
# Check certificate status
kubectl get certificate -n default

# Expected progression:
# NAME      READY   SECRET    AGE
# app-tls   False   app-tls   10s   (Requesting)
# app-tls   False   app-tls   30s   (Challenge in progress)
# app-tls   True    app-tls   90s   (Issued)

# View challenges
kubectl get challenges -A

# Certificate details
kubectl describe certificate app-tls
```

Certificates automatically renew 30 days before expiration.

---

## Upgrading cert-manager

### Update Version

1. Edit workflow file (e.g., `.github/workflows/deploy-cert-manager-gke.yaml`)
2. Locate version definition (approximately line 156):
   ```yaml
   cert_manager_version = "v1.19.2"
   ```
3. Update to new version:
   ```yaml
   cert_manager_version = "v1.20.0"
   ```
4. Commit and push:
   ```bash
   git add .github/workflows/deploy-cert-manager-gke.yaml
   git commit -m "Upgrade cert-manager to v1.20.0"
   git push origin main
   ```

Workflow executes automatically, performing an in-place Helm upgrade with zero downtime.

---

## Uninstalling

### Using Destroy Workflow

1. Navigate to **Actions** tab
2. Select `Destroy cert-manager` workflow
3. Click **Run workflow**
4. Select cloud provider (GKE/EKS/AKS)
5. Enter confirmation: `DESTROY`
6. Confirm execution

**Resources Removed:**
- cert-manager Helm release
- cert-manager namespace
- ClusterIssuer resources
- cert-manager Custom Resource Definitions
- All Certificate resources

**Resources Preserved:**
- Terraform state file (for potential recreation)

---

## Troubleshooting

### Workflow Fails: Setup Environment

**Issue:** Cannot connect to cluster

**Resolution:**
- Verify GitHub Secrets configuration
- GKE: Check `GCP_SA_KEY`, `CLUSTER_NAME`, `CLUSTER_LOCATION`
- EKS: Check AWS credentials, `CLUSTER_NAME`, `AWS_REGION`
- AKS: Check `AZURE_CREDENTIALS`, `CLUSTER_NAME`, `RESOURCE_GROUP`

### Workflow Fails: Terraform Init

**Issue:** Backend configuration error

**Resolution:**
- Verify state bucket exists and is accessible
- Confirm service account has storage permissions
- GKE: Verify GCS bucket in `TF_STATE_BUCKET`
- EKS: Verify S3 bucket in `TF_STATE_BUCKET`
- AKS: Verify `AZURE_STORAGE_ACCOUNT` and `AZURE_STORAGE_CONTAINER`

### Pods Not Ready

**Issue:** Deployment verification fails

**Diagnosis:**
```bash
kubectl logs -n cert-manager deploy/cert-manager
kubectl describe pod -n cert-manager <pod-name>
```

**Common Causes:**
- Insufficient cluster resources (CPU/memory)
- Image pull errors
- Network policies blocking webhook

### Certificate Not Issuing

**Issue:** Certificate remains in non-ready state

**Diagnosis:**
```bash
kubectl describe certificate <cert-name> -n <namespace>
kubectl get challenges -A
kubectl describe challenge -n <namespace> <challenge-name>
```

**Common Causes:**
- DNS not pointing to ingress LoadBalancer IP
- Ingress not publicly accessible
- Let's Encrypt rate limits (use staging issuer for testing)

**Use Staging Issuer:**
```yaml
# Update in workflow or terraform.tfvars:
issuer_server = "https://acme-staging-v02.api.letsencrypt.org/directory"
```

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
