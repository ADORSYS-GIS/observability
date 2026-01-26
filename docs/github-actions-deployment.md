# GitHub Actions Deployment for LGTM Stack

Automated deployment of the LGTM observability stack to Kubernetes clusters using GitHub Actions workflows with Terraform.

## Overview

This guide explains how to deploy the LGTM stack (Loki, Grafana, Tempo, Mimir, Prometheus) to any Kubernetes cluster using GitHub Actions. The workflows are cloud-agnostic and support:

- **GKE** (Google Kubernetes Engine)
- **EKS** (Amazon Elastic Kubernetes Service)
- **AKS** (Azure Kubernetes Service)
- **Generic Kubernetes** (minikube, kind, on-premise, etc.)

## Architecture

The deployment uses a modular Terraform architecture:

```
lgtm-stack/terraform/
├── main.tf                    # Core LGTM Helm releases
├── variables.tf               # Variables with cloud_provider support
├── modules/
│   ├── cloud-gke/            # GCS buckets + Workload Identity
│   ├── cloud-eks/            # S3 buckets + IRSA
│   ├── cloud-aks/            # Azure Blob + Managed Identity
│   └── cloud-generic/        # PersistentVolumes

.github/
├── workflows/
│   ├── deploy-lgtm-stack.yaml    # Main deployment workflow
│   └── destroy-lgtm-stack.yaml   # Teardown workflow
└── scripts/
    ├── configure-backend.sh       # Dynamic Terraform backend config
    ├── detect-cloud-provider.sh   # Auto-detect cloud from kubeconfig
    ├── import-existing-resources.sh # Import existing K8s resources
    ├── verify-deployment.sh       # Post-deployment validation
    └── smoke-tests.sh            # Comprehensive component testing
```

## Prerequisites

### 1. Kubernetes Cluster

You need an existing Kubernetes cluster with:
- `kubectl` access configured
- Cluster admin permissions
- Sufficient resources for LGTM stack

> [!IMPORTANT]
> The workflows assume an **existing cluster**. They do not create clusters.

### 2. GitHub Repository Secrets

Configure the following secrets in your repository settings (`Settings → Secrets and variables → Actions`):

#### Common Secrets (All Cloud Providers)

| Secret | Description | Example |
|--------|-------------|---------|
| `KUBECONFIG` | Base64-encoded kubeconfig file | `cat ~/.kube/config \| base64 -w 0` |
| `GRAFANA_ADMIN_PASSWORD` | Admin password for Grafana | `MySecurePassword123!` |
| `LETSENCRYPT_EMAIL` | Email for Let's Encrypt notifications | `admin@example.com` |
| `MONITORING_DOMAIN` | Base domain for monitoring services | `monitoring.example.com` |
| `ENVIRONMENT` | Environment name | `production` |

#### Cloud-Specific Secrets

**For GKE:**
```
CLOUD_PROVIDER=gke
GCP_PROJECT_ID=my-gcp-project
GCP_SA_KEY=<service-account-json-key>
TF_STATE_BUCKET=my-terraform-state-bucket
CLUSTER_NAME=my-gke-cluster
CLUSTER_LOCATION=us-central1
REGION=us-central1
```

**For EKS:**
```
CLOUD_PROVIDER=eks
AWS_ACCESS_KEY_ID=AKIA...
AWS_SECRET_ACCESS_KEY=...
AWS_REGION=us-east-1
TF_STATE_BUCKET=my-terraform-state-bucket
CLUSTER_NAME=my-eks-cluster
```

**For AKS:**
```
CLOUD_PROVIDER=aks
AZURE_CREDENTIALS=<service-principal-json>
AZURE_STORAGE_ACCOUNT=mystorageaccount
AZURE_STORAGE_CONTAINER=terraform-state
CLUSTER_NAME=my-aks-cluster
```

**For Generic Kubernetes:**
```
CLOUD_PROVIDER=generic
CLUSTER_NAME=my-cluster
# No additional cloud secrets required
```

### 3. Cloud Provider Setup

#### GKE Setup

1. **Create State Storage Bucket:**
   ```bash
   export PROJECT_ID="my-gcp-project"
   export BUCKET_NAME="${PROJECT_ID}-terraform-state"
   
   gsutil mb -p $PROJECT_ID -l us-central1 gs://$BUCKET_NAME
   gsutil versioning set on gs://$BUCKET_NAME
   ```

2. **Create Service Account:**
   ```bash
   gcloud iam service-accounts create github-actions \
     --display-name "GitHub Actions Service Account"
   
   # Grant permissions
   gcloud projects add-iam-policy-binding $PROJECT_ID \
     --member="serviceAccount:github-actions@${PROJECT_ID}.iam.gserviceaccount.com" \
     --role="roles/container.admin"
   
   gcloud projects add-iam-policy-binding $PROJECT_ID \
     --member="serviceAccount:github-actions@${PROJECT_ID}.iam.gserviceaccount.com" \
     --role="roles/storage.admin"
   
   # Create key
   gcloud iam service-accounts keys create key.json \
     --iam-account=github-actions@${PROJECT_ID}.iam.gserviceaccount.com
   ```

3. **Set GitHub Secret:**
   ```bash
   # Copy the contents of key.json to GCP_SA_KEY secret
   cat key.json
   ```

#### EKS Setup

1. **Create State Storage Bucket:**
   ```bash
   export BUCKET_NAME="my-terraform-state-bucket"
   export AWS_REGION="us-east-1"
   
   aws s3api create-bucket \
     --bucket $BUCKET_NAME \
     --region $AWS_REGION
   
   aws s3api put-bucket-versioning \
     --bucket $BUCKET_NAME \
     --versioning-configuration Status=Enabled
   ```

2. **Get OIDC Provider ARN:**
   ```bash
   export CLUSTER_NAME="my-eks-cluster"
   
   aws eks describe-cluster --name $CLUSTER_NAME \
     --query "cluster.identity.oidc.issuer" --output text
   
   # Find the provider ARN in IAM console or use:
   aws iam list-open-id-connect-providers
   ```

3. **Create IAM User for GitHub Actions:**
   ```bash
   aws iam create-user --user-name github-actions
   
   # Attach policies
   aws iam attach-user-policy --user-name github-actions \
     --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy
   
   # Create access key
   aws iam create-access-key --user-name github-actions
   ```

#### Generic Kubernetes Setup

No cloud-specific setup required. Just ensure:
- `kubectl` can access your cluster
- You have a valid kubeconfig file

## Usage

### Deploy LGTM Stack

#### Manual Deployment

1. Go to `Actions` tab in GitHub
2. Select `Deploy LGTM Stack` workflow
3. Click `Run workflow`
4. Select your cloud provider (gke/eks/aks/generic)
5. Choose action: `apply` (to deploy)
6. Click `Run workflow`

#### Automatic Deployment

Push changes to `main` branch:
```bash
git push origin main
```

The workflow will automatically:
1. Detect your cloud provider (from `CLOUD_PROVIDER` secret)
2. Import existing resources to avoid conflicts
3. Run Terraform plan
4. Apply changes (on main branch only)
5. Verify deployment
6. Run smoke tests

### Verify Deployment

After deployment completes:

1. **Check workflow artifacts:**
   - Download `verification-report.html` to see deployment status
   - Download `smoke-test-results.json` for test results

2. **Access Grafana:**
   ```bash
   # If using domain:
   https://grafana.${MONITORING_DOMAIN}
   
   # Or port-forward:
   kubectl port-forward -n observability svc/monitoring-grafana 3000:80
   # Then open: http://localhost:3000
   ```
   
   Login: `admin` / `${GRAFANA_ADMIN_PASSWORD}`

3. **Check component health:**
   ```bash
   kubectl get pods -n observability
   kubectl get svc -n observability
   kubectl get ingress -n observability
   ```

### Destroy Stack

> [!CAUTION]
> This will remove all LGTM stack components. Data in storage buckets can be preserved.

1. Go to `Actions` tab
2. Select `Destroy LGTM Stack` workflow
3. Click `Run workflow`
4. Select cloud provider
5. Choose whether to delete storage buckets/volumes
6. Type `DESTROY` to confirm
7. Click `Run workflow`

## Workflow Details

### Deploy Workflow Jobs

1. **setup-environment**
   - Configures cloud credentials
   - Sets up kubectl access
   - Validates cluster connectivity

2. **import-existing-resources**
   - Scans for existing resources (cert-manager, nginx-ingress, namespaces)
   - Imports them into Terraform state
   - Prevents resource conflicts

3. **terraform-plan**
   - Generates Terraform execution plan
   - Posts plan to PR (if applicable)
   - Creates plan artifact

4. **terraform-apply**
   - Applies Terraform changes
   - Deploys LGTM stack components
   - Configures cloud storage and IAM

5. **verify-deployment**
   - Waits for all pods to be ready
   - Runs comprehensive smoke tests
   - Generates HTML verification report

### Smoke Tests

Tests performed on each component:

**Loki:**
- ✅ Push log entries via API
- ✅ Query logs using LogQL
- ✅ Verify label filtering

**Mimir:**
- ✅ Push metrics via remote write
- ✅ Query metrics using PromQL
- ✅ Validate metric ingestion

**Prometheus:**
- ✅ Check scrape targets health
- ✅ Query metrics via API
- ✅ Test alerting rules

**Tempo:**
- ✅ Send test traces via OTLP
- ✅ Query trace by ID
- ✅ Verify trace search

**Grafana:**
- ✅ API authentication
- ✅ Datasource configuration
- ✅ Dashboard creation
- ✅ Query each datasource

**Integration:**
- ✅ Correlated logs/metrics/traces
- ✅ Trace ID linking

## Troubleshooting

### Workflow Fails at Import Step

**Problem:** Import job fails with resource not found

**Solution:** This is expected if resources don't exist. The workflow continues anyway.

### Terraform Apply Fails with "Already Exists"

**Problem:** Resource already exists in cluster

**Solution:**
1. Check `import-report.json` artifact
2. Manually import missing resources:
   ```bash
   cd lgtm-stack/terraform
   terraform import kubernetes_namespace.observability observability
   ```

### Pods Not Starting

**Problem:** Pods in `Pending` or `CrashLoopBackOff`

**Solution:**
```bash
# Check pod status
kubectl describe pod -n observability <pod-name>

# Check logs
kubectl logs -n observability <pod-name>

# Common issues:
# - Insufficient resources
# - Storage class not available (generic k8s)
# - Cloud IAM permissions (GKE/EKS/AKS)
```

### Storage Bucket Access Denied

**GKE:**
```bash
# Verify Workload Identity binding
kubectl get sa -n observability observability-sa -o yaml | grep iam.gke.io

# Check GCP IAM permissions
gcloud projects get-iam-policy $PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:gke-observability-sa@*"
```

**EKS:**
```bash
# Verify IRSA annotation
kubectl get sa -n observability observability-sa -o yaml | grep eks.amazonaws.com

# Check IAM role
aws iam get-role --role-name my-eks-cluster-lgtm-irsa
```

### Smoke Tests Fail

**Problem:** Some smoke tests fail

**Solution:**
1. Wait a few minutes for components to fully initialize
2. Check individual component logs
3. Verify ingress/service configurations
4. Re-run smoke tests manually:
   ```bash
   export KUBECONFIG=~/.kube/config
   export GRAFANA_ADMIN_PASSWORD="your-password"
   bash .github/scripts/smoke-tests.sh
   ```

## Related Documentation

- [Manual LGTM Deployment](manual-lgtm-deployment.md)
- [Testing Monitoring Stack](testing-monitoring-stack-deployment.md)
- [Troubleshooting LGTM Stack](troubleshooting-lgtm-stack.md)
- [Adopting LGTM Stack](adopting-lgtm-stack.md)

## Support

For issues or questions:
1. Check workflow logs in GitHub Actions tab
2. Review artifact reports (verification-report.html, import-report.json)
3. Consult troubleshooting guides
4. Check component-specific documentation
