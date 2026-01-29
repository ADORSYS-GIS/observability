# cert-manager Terraform Deployment

Automated TLS certificate management using Terraform with multi-cloud support.

**Official**: [cert-manager.io/docs](https://cert-manager.io/docs/) | **GitHub**: [cert-manager/cert-manager](https://github.com/cert-manager/cert-manager)

## Prerequisites

| Requirement | Version | Purpose |
|-------------|---------|---------|
| Terraform | ≥ 1.5.0 | Infrastructure provisioning |
| kubectl | ≥ 1.24 | Cluster access |
| Kubernetes | ≥ 1.24 | GKE, EKS, AKS, or generic |

**Dependencies**: Requires NGINX Ingress Controller for HTTP-01 challenges. See [Ingress Controller Setup](ingress-controller-terraform-deployment.md).

## Deployment Methods

### Option A: GitHub Actions (Automated CI/CD)

Workflows automatically handle backend configuration, authentication, and deployment.

**Available Workflows:**
- `.github/workflows/deploy-cert-manager-gke.yaml` - Google Kubernetes Engine
- `.github/workflows/deploy-cert-manager-eks.yaml` - Amazon EKS
- `.github/workflows/deploy-cert-manager-aks.yaml` - Azure AKS
- `.github/workflows/destroy-cert-manager.yaml` - Cleanup

**Required GitHub Secrets:**

| Provider | Required Secrets |
|----------|------------------|
| **GKE** | `GCP_SA_KEY`, `GCP_PROJECT_ID`, `CLUSTER_NAME`, `CLUSTER_LOCATION`, `REGION`, `TF_STATE_BUCKET`, `LETSENCRYPT_EMAIL` |
| **EKS** | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`, `CLUSTER_NAME`, `TF_STATE_BUCKET`, `LETSENCRYPT_EMAIL` |
| **AKS** | `AZURE_CREDENTIALS`, `AZURE_STORAGE_ACCOUNT`, `AZURE_STORAGE_CONTAINER`, `RESOURCE_GROUP`, `CLUSTER_NAME`, `LETSENCRYPT_EMAIL` |

**Usage:**
1. Configure GitHub repository secrets
2. Push changes to trigger workflow
3. Review Terraform plan in PR comments
4. Merge to apply changes

### Option B: Terraform CLI (Manual)

**Step 1: Setup**

```bash
cd observability/cert-manager/terraform

# Verify cluster connection
kubectl config current-context
kubectl cluster-info
```

**Step 2: Configure Backend**

```bash
# GKE
export TF_STATE_BUCKET="your-gcs-bucket"
bash ../../.github/scripts/configure-backend.sh gke cert-manager

# EKS
export TF_STATE_BUCKET="your-s3-bucket"
export AWS_REGION="us-east-1"
bash ../../.github/scripts/configure-backend.sh eks cert-manager

# AKS
export AZURE_STORAGE_ACCOUNT="your-storage-account"
export AZURE_STORAGE_CONTAINER="terraform-state"
bash ../../.github/scripts/configure-backend.sh aks cert-manager
```

**State File Location:** `<bucket>/terraform/cert-manager/terraform.tfstate`

**Step 3: Configure Variables**

```bash
cp terraform.tfvars.template terraform.tfvars
```

Edit `terraform.tfvars`:

| Variable | Required | Description | Example |
|----------|----------|-------------|---------|
| `cloud_provider` | Yes | Provider type | `gke`, `eks`, `aks`, `generic` |
| `install_cert_manager` | Yes | Install cert-manager | `true` |
| `create_issuer` | Yes | Create ClusterIssuer | `true` |
| `letsencrypt_email` | Yes | Let's Encrypt email | `admin@example.com` |
| `cert_manager_version` | No | Chart version | `v1.19.2` (default) |
| `cert_issuer_name` | No | Issuer name | `letsencrypt-prod` (default) |
| `cert_issuer_kind` | No | Issuer type | `ClusterIssuer` (default) |
| `issuer_server` | No | ACME server | Production (default) or staging |
| `ingress_class_name` | No | Ingress class | `nginx` (default) |

**GKE-Specific:**
- `project_id` - GCP project ID
- `region` - GCP region
- `gke_endpoint` - Auto-populated by workflows (leave empty for CLI)
- `gke_ca_certificate` - Auto-populated by workflows (leave empty for CLI)

**EKS-Specific:**
- `aws_region` - AWS region

**Step 4: Deploy**

```bash
terraform init
terraform validate
terraform plan
terraform apply
```

**Step 5: Verify**

```bash
# Check pods
kubectl get pods -n cert-manager
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=300s

# Verify ClusterIssuer
kubectl get clusterissuer letsencrypt-prod
kubectl describe clusterissuer letsencrypt-prod
```

## Usage Example

Create an Ingress with automatic TLS:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: example-ingress
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - example.com
      secretName: example-tls
  rules:
    - host: example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: example-service
                port:
                  number: 80
```

## State Management

State files are stored remotely and persist across deployments:

| Provider | Backend | State File Path |
|----------|---------|-----------------|
| **GKE** | Google Cloud Storage | `gs://<bucket>/terraform/cert-manager/terraform.tfstate` |
| **EKS** | S3 + DynamoDB | `s3://<bucket>/terraform/cert-manager/terraform.tfstate` |
| **AKS** | Azure Blob | `<account>/<container>/terraform/cert-manager/terraform.tfstate` |

**The backend configuration script (`configure-backend.sh`) creates backend-config.tf but NEVER deletes state files.**

## Upgrading

```bash
cd observability/cert-manager/terraform

# Update version in terraform.tfvars
terraform plan
terraform apply
```

## Uninstalling

```bash
terraform destroy
```

**Note:** This removes cert-manager, CRDs, and all Certificate resources.

## Troubleshooting

See [Troubleshooting Guide](troubleshooting-cert-manager.md).

## Adoption

Already have cert-manager? See [Adoption Guide](adopting-cert-manager.md).
