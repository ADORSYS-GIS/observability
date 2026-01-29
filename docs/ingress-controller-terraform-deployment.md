# NGINX Ingress Controller Terraform Deployment

Layer 7 load balancing and external traffic routing using Terraform with multi-cloud support.

**Official**: [kubernetes.github.io/ingress-nginx](https://kubernetes.github.io/ingress-nginx/) | **GitHub**: [kubernetes/ingress-nginx](https://github.com/kubernetes/ingress-nginx)

## Prerequisites

| Requirement | Version | Purpose |
|-------------|---------|---------|
| Terraform | ≥ 1.5.0 | Infrastructure provisioning |
| kubectl | ≥ 1.24 | Cluster access |
| Kubernetes | ≥ 1.24 | GKE, EKS, AKS, or generic with LoadBalancer support |

## Deployment Methods

### Option A: GitHub Actions (Automated CI/CD)

Workflows automatically handle backend configuration, authentication, and LoadBalancer provisioning.

**Available Workflows:**
- `.github/workflows/deploy-ingress-controller-gke.yaml` - Google Kubernetes Engine
- `.github/workflows/deploy-ingress-controller-eks.yaml` - Amazon EKS
- `.github/workflows/deploy-ingress-controller-aks.yaml` - Azure AKS
- `.github/workflows/destroy-ingress-controller.yaml` - Cleanup

**Required GitHub Secrets:**

| Provider | Required Secrets |
|----------|------------------|
| **GKE** | `GCP_SA_KEY`, `GCP_PROJECT_ID`, `CLUSTER_NAME`, `CLUSTER_LOCATION`, `REGION`, `TF_STATE_BUCKET` |
| **EKS** | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`, `CLUSTER_NAME`, `TF_STATE_BUCKET` |
| **AKS** | `AZURE_CREDENTIALS`, `AZURE_STORAGE_ACCOUNT`, `AZURE_STORAGE_CONTAINER`, `RESOURCE_GROUP`, `CLUSTER_NAME` |

**Usage:**
1. Configure GitHub repository secrets
2. Push changes to trigger workflow
3. Review Terraform plan in PR comments
4. Merge to apply changes

### Option B: Terraform CLI (Manual)

**Step 1: Setup**

```bash
cd observability/ingress-controller/terraform

# Verify cluster connection
kubectl config current-context
kubectl cluster-info
```

**Step 2: Configure Backend**

```bash
# GKE
export TF_STATE_BUCKET="your-gcs-bucket"
bash ../../.github/scripts/configure-backend.sh gke ingress-controller

# EKS
export TF_STATE_BUCKET="your-s3-bucket"
export AWS_REGION="us-east-1"
bash ../../.github/scripts/configure-backend.sh eks ingress-controller

# AKS
export AZURE_STORAGE_ACCOUNT="your-storage-account"
export AZURE_STORAGE_CONTAINER="terraform-state"
bash ../../.github/scripts/configure-backend.sh aks ingress-controller
```

**State File Location:** `<bucket>/terraform/ingress-controller/terraform.tfstate`

**Step 3: Configure Variables**

```bash
cp terraform.tfvars.template terraform.tfvars
```

Edit `terraform.tfvars`:

| Variable | Required | Description | Example |
|----------|----------|-------------|---------|
| `cloud_provider` | Yes | Provider type | `gke`, `eks`, `aks`, `generic` |
| `install_nginx_ingress` | Yes | Install controller | `true` |
| `nginx_ingress_version` | No | Chart version | `4.14.2` (default) |
| `release_name` | No | Helm release name | `nginx-monitoring` (default) |
| `ingress_class_name` | No | IngressClass name | `nginx` (default) |
| `namespace` | No | Installation namespace | `ingress-nginx` (default) |
| `replica_count` | No | Controller replicas | `1` (default) |

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
kubectl get pods -n ingress-nginx
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=ingress-nginx -n ingress-nginx --timeout=300s

# Check LoadBalancer
kubectl get svc -n ingress-nginx
EXTERNAL_IP=$(kubectl get svc -n ingress-nginx nginx-monitoring-ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "External IP: $EXTERNAL_IP"

# Verify IngressClass
kubectl get ingressclass nginx
```

## Usage Example

Create an Ingress resource:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: example-ingress
spec:
  ingressClassName: nginx
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

With TLS (requires cert-manager):

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
| **GKE** | Google Cloud Storage | `gs://<bucket>/terraform/ingress-controller/terraform.tfstate` |
| **EKS** | S3 + DynamoDB | `s3://<bucket>/terraform/ingress-controller/terraform.tfstate` |
| **AKS** | Azure Blob | `<account>/<container>/terraform/ingress-controller/terraform.tfstate` |

**The backend configuration script (`configure-backend.sh`) creates backend-config.tf but NEVER deletes state files.**

## Upgrading

```bash
cd observability/ingress-controller/terraform

# Update version in terraform.tfvars
terraform plan
terraform apply
```

## Uninstalling

```bash
terraform destroy
```

**Note:** This removes the Ingress Controller and its LoadBalancer, affecting all Ingress resources.

## DNS Configuration

Point your domain A records to the LoadBalancer external IP:

```bash
# Get external IP
kubectl get svc -n ingress-nginx nginx-monitoring-ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

Create DNS records:
- `example.com` → `<EXTERNAL-IP>` (A record)
- `*.example.com` → `<EXTERNAL-IP>` (A record for wildcard subdomains)

## Troubleshooting

See [Troubleshooting Guide](troubleshooting-ingress-controller.md).

## Adoption

Already have NGINX Ingress Controller? See [Adoption Guide](adopting-ingress-controller.md).
