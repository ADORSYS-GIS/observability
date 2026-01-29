# NGINX Ingress Controller GitHub Actions Deployment

Automated Layer 7 load balancing deployment using GitHub Actions CI/CD workflows.

**Official Documentation**: [kubernetes.github.io/ingress-nginx](https://kubernetes.github.io/ingress-nginx/) | **Helm Chart**: [artifacthub.io/packages/helm/ingress-nginx/ingress-nginx](https://artifacthub.io/packages/helm/ingress-nginx/ingress-nginx) | **Version**: `4.14.2`

---

## Overview

This deployment method uses GitHub Actions workflows to automatically deploy NGINX Ingress Controller to Kubernetes clusters via Terraform. The workflows handle backend configuration, authentication, and deployment across GKE, EKS, and AKS.

**Key Features:**
- Automated Terraform backend configuration (GCS/S3/Azure Blob)
- Cloud provider authentication via GitHub Secrets
- Pull request-based plan review with automated comments
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

#### deploy-ingress-controller-gke.yaml

**Triggers:**
- Manual: Actions tab → Deploy Ingress Controller (GKE) → Run workflow
- Automatic: Push to `main` when ingress-controller files change
- Pull requests: Runs plan and comments result

**Workflow Steps:**
1. Authenticates to GKE cluster
2. Configures GCS backend for Terraform state
3. Runs `terraform plan` to preview changes
4. On `main` push or manual apply: deploys NGINX Ingress v4.14.2
5. Provisions cloud LoadBalancer with external IP
6. Verifies IngressClass creation and pod readiness

#### deploy-ingress-controller-eks.yaml

Same workflow for AWS EKS with S3 backend and Network Load Balancer.

#### deploy-ingress-controller-aks.yaml

Same workflow for Azure AKS with Blob Storage backend and Azure Load Balancer.

---

### Step 3: Deploy Ingress Controller

#### Option A: Manual Deployment

1. Navigate to **Actions** tab in GitHub repository
2. Select workflow: `Deploy Ingress Controller (GKE/EKS/AKS)`
3. Click **Run workflow**
4. Choose action:
   - `plan` - Preview changes without applying
   - `apply` - Deploy ingress controller
5. Click **Run workflow** button
6. Monitor workflow progress (approximately 3-4 minutes)

**Workflow execution phases:**

**Setup Environment (30 seconds):**
- Checkout repository code
- Authenticate to cloud provider
- Configure kubectl and cluster context
- Verify cluster connectivity

**Terraform Plan (45 seconds):**
- Install Terraform CLI
- Generate backend configuration for state storage
- Initialize Terraform (fetch providers, configure backend)
- Validate Terraform configuration syntax
- Create terraform.tfvars with deployment parameters
- Execute `terraform plan` to show infrastructure changes
- Upload plan artifact for apply job

**Terraform Apply (90 seconds, only on apply action or main push):**
- Download plan artifact
- Execute `terraform apply -auto-approve`
- Save Terraform outputs

**Verify Deployment (60 seconds):**
- Check ingress-nginx namespace creation
- Wait for controller pod readiness (2 replicas by default)
- Verify LoadBalancer service has external IP
- Confirm IngressClass "nginx" exists

**Total execution time:** 3-4 minutes

#### Option B: Automatic Deployment (Push to main)

Commit and push changes to trigger automated deployment:

```bash
git add ingress-controller/terraform/
git commit -m "Update ingress controller configuration"
git push origin main
```

Workflow automatically triggers. Pull requests run plan and comment results. Merges to `main` execute apply.

---

## Verify Deployment

After workflow completes successfully:

```bash
# Check namespace
kubectl get namespace ingress-nginx

# Check pods (2 replicas by default)
kubectl get pods -n ingress-nginx

# Expected output:
# NAME                                        READY   STATUS    RESTARTS   AGE
# nginx-monitoring-...-controller-xxxxx       1/1     Running   0          2m
# nginx-monitoring-...-controller-yyyyy       1/1     Running   0          2m

# Get LoadBalancer external IP
kubectl get svc -n ingress-nginx

# Expected output:
# NAME                                          TYPE           CLUSTER-IP      EXTERNAL-IP       PORT(S)
# nginx-monitoring-ingress-nginx-controller     LoadBalancer   10.x.x.x        34.123.45.67      80:xxxxx/TCP,443:yyyyy/TCP

# Verify IngressClass
kubectl get ingressclass nginx

# Expected output:
# NAME    CONTROLLER                      PARAMETERS   AGE
# nginx   k8s.io/ingress-nginx            <none>       2m
```

The `EXTERNAL-IP` field contains the public IP address for routing external traffic.

---

## Usage

Create an Ingress resource to route traffic to your services:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app-ingress
  namespace: default
spec:
  ingressClassName: nginx
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

Configure DNS:
```bash
# Get the LoadBalancer IP
EXTERNAL_IP=$(kubectl get svc -n ingress-nginx \
  nginx-monitoring-ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

echo "Point myapp.example.com to $EXTERNAL_IP"
```

Create DNS A record:
- `myapp.example.com` → `<EXTERNAL_IP>`

Test the configuration:
```bash
curl http://myapp.example.com
```

### TLS Configuration

For automatic TLS certificate management, deploy cert-manager ([deployment guide](cert-manager-github-actions.md)) and configure the Ingress:

```yaml
metadata:
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  tls:
    - hosts:
        - myapp.example.com
      secretName: myapp-tls
```

---

## Updating Ingress Controller

To upgrade the ingress controller version:

**Step 1: Edit workflow file**
```bash
vim .github/workflows/deploy-ingress-controller-gke.yaml
```

**Step 2: Update version parameter**
```yaml
# Locate this line (approximately line 154):
ingress_nginx_version = "4.14.2"

# Update to newer version:
ingress_nginx_version = "4.15.0"
```

Check [Artifact Hub](https://artifacthub.io/packages/helm/ingress-nginx/ingress-nginx) for the latest version.

**Step 3: Commit and push**
```bash
git add .github/workflows/deploy-ingress-controller-gke.yaml
git commit -m "Update ingress-nginx to 4.15.0"
git push origin main
```

Terraform detects the version change and Helm performs a rolling update with zero downtime.

---

## Cleanup

To remove the ingress controller:

1. Navigate to **Actions** tab
2. Select workflow: `Destroy Ingress Controller`
3. Run workflow and choose provider (GKE/EKS/AKS)
4. Type confirmation: `DESTROY` (uppercase required)
5. Confirm and monitor teardown

**Resources removed:**
- NGINX Ingress Helm release
- ingress-nginx namespace
- LoadBalancer service (external IP released)
- IngressClass resource
- All Ingress resources become non-functional

**Resources preserved:**
- Terraform state file (for recovery)

**Warning:** Removing the ingress controller breaks external access for all applications using Ingress resources.

---

## Troubleshooting

### Workflow Fails at Setup Environment

**Symptom:** Cannot connect to cluster

**Resolution:**

Verify GitHub Secrets are configured correctly:
- **GKE:** Check `GCP_SA_KEY`, `CLUSTER_NAME`, `CLUSTER_LOCATION`
- **EKS:** Check `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `CLUSTER_NAME`, `AWS_REGION`
- **AKS:** Check `AZURE_CREDENTIALS`, `CLUSTER_NAME`, `AZURE_RESOURCE_GROUP`

Test cluster access manually:

```bash
# GKE
gcloud container clusters get-credentials CLUSTER_NAME --zone ZONE --project PROJECT

# EKS
aws eks update-kubeconfig --name CLUSTER_NAME --region REGION

# AKS
az aks get-credentials --name CLUSTER_NAME --resource-group RG

kubectl cluster-info
```

---

### Workflow Fails at Terraform Init

**Symptom:** Backend configuration error

**Resolution:**

Verify state storage bucket exists:

```bash
# GKE
gsutil ls gs://TF_STATE_BUCKET

# EKS
aws s3 ls s3://TF_STATE_BUCKET

# AKS
az storage container show --name CONTAINER --account-name ACCOUNT
```

Confirm service account has storage permissions.

---

### External IP Stuck in Pending

**Symptom:** LoadBalancer service shows `<pending>` indefinitely

**Check cloud provider quotas:**

```bash
# GKE
gcloud compute project-info describe --project=PROJECT_ID

# EKS
# Check AWS service quotas for Elastic IPs in console

# AKS
az vm list-usage --location REGION
```

**Common causes:**
- Exceeded cloud provider IP quota
- Insufficient IAM permissions to create load balancer
- Network firewall rules blocking load balancer provisioning

---

### Ingress Returns 404 Not Found

**Symptom:** External IP accessible but all requests return 404

**Diagnostic commands:**

```bash
# Check Ingress exists
kubectl get ingress -A

# Verify Ingress configuration
kubectl describe ingress <name> -n <namespace>

# Confirm backend service exists
kubectl get svc <backend-service> -n <namespace>

# Check service endpoints (pod IPs)
kubectl get endpoints <backend-service> -n <namespace>

# Review ingress controller logs
kubectl logs -n ingress-nginx deploy/nginx-monitoring-ingress-nginx-controller
```

**Common causes:**
- IngressClass mismatch (verify `ingressClassName: nginx`)
- Backend service missing or has no endpoints
- DNS points to incorrect IP address

---

### Ingress Returns 503 Service Unavailable

**Symptom:** Ingress routes traffic but backend is unavailable

**Resolution:**

```bash
# Check backend pod status
kubectl get pods -n <namespace>

# Verify service endpoints
kubectl get endpoints <service> -n <namespace>
```

**Common cause:** No healthy backend pods

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
    ingress_nginx_version = "4.14.2"
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

**Official Documentation**: [kubernetes.github.io/ingress-nginx](https://kubernetes.github.io/ingress-nginx/)
