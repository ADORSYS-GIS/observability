# NGINX Ingress Controller Terraform CLI Deployment

Infrastructure as Code deployment using Terraform for reproducible, version-controlled deployments.

Recommended for teams using infrastructure as code workflows, multi-environment deployments, or requiring reproducible configurations. This method provides full control over Terraform execution from your local machine or CI/CD pipeline.

**Official Documentation**: [kubernetes.github.io/ingress-nginx](https://kubernetes.github.io/ingress-nginx/) | **GitHub**: [kubernetes/ingress-nginx](https://github.com/kubernetes/ingress-nginx) | **Version**: `4.14.2`

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

**Infrastructure Requirements:**
- LoadBalancer support: Cluster must provision external IPs (GKE, EKS, AKS, or MetalLB for on-premise)
- Cluster access: `kubectl cluster-info` returns valid information

---

## Terraform State Management

This deployment uses remote state backends for collaboration and state persistence.

**Backend Configuration:**

| Provider | Backend | State Path |
|----------|---------|-----------|
| GKE | Google Cloud Storage (GCS) | `gs://<bucket>/terraform/ingress-controller/terraform.tfstate` |
| EKS | AWS S3 + DynamoDB locking | `s3://<bucket>/terraform/ingress-controller/terraform.tfstate` |
| AKS | Azure Blob Storage | `azurerm://<container>/terraform/ingress-controller/terraform.tfstate` |
| Generic | Local or custom remote backend | `./terraform.tfstate` (local) |

The backend configuration is generated automatically by the `configure-backend.sh` script or manually created.

For detailed state management documentation, see [Terraform State Management Guide](terraform-state-management.md).

---

## Installation

### Step 1: Navigate to Terraform Directory

```bash
cd ingress-controller/terraform
```

---

### Step 2: Configure Backend (Required for Remote State)

**Option A: Using the configuration script (recommended)**

For GKE:
```bash
../../.github/scripts/configure-backend.sh gke ingress-controller
```

For EKS:
```bash
export TF_STATE_BUCKET="your-s3-bucket"
export AWS_REGION="us-east-1"
export TF_STATE_LOCK_TABLE="terraform-state-lock"  # Optional
../../.github/scripts/configure-backend.sh eks ingress-controller
```

For AKS:
```bash
export AZURE_STORAGE_ACCOUNT="yourstorageaccount"
export AZURE_STORAGE_CONTAINER="terraform-state"
../../.github/scripts/configure-backend.sh aks ingress-controller
```

For generic Kubernetes (local state):
```bash
../../.github/scripts/configure-backend.sh generic ingress-controller
```

This creates `backend-config.tf` with the appropriate backend configuration.

**Option B: Manual backend configuration**

Create `backend-config.tf`:

For GKE (GCS backend):
```hcl
terraform {
  backend "gcs" {
    bucket = "your-gcs-bucket"
    prefix = "terraform/ingress-controller"
  }
}
```

For EKS (S3 backend):
```hcl
terraform {
  backend "s3" {
    bucket         = "your-s3-bucket"
    key            = "terraform/ingress-controller/terraform.tfstate"
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
    key                  = "terraform/ingress-controller/terraform.tfstate"
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
install_nginx_ingress = true

# Optional: Version override
nginx_ingress_version = "4.14.2"
```

**Full configuration options:**

```hcl
# ==============================================================================
# NGINX Ingress Controller Terraform Configuration
# ==============================================================================

# Cloud Provider
cloud_provider = "gke"  # Options: gke, eks, aks, generic

# GKE-specific (required for GKE)
project_id = "your-gcp-project-id"
region     = "us-central1"

# EKS-specific (required for EKS)
aws_region = "us-east-1"

# Installation Control
install_nginx_ingress = true  # Set false to manage existing installation

# Helm Release
release_name          = "nginx-monitoring"
namespace             = "ingress-nginx"
nginx_ingress_version = "4.14.2"

# Controller Configuration
replica_count      = 2  # Number of controller replicas for high availability
ingress_class_name = "nginx"
```

**Configuration Variables:**

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `cloud_provider` | Target platform (gke/eks/aks/generic) | `gke` | Yes |
| `install_nginx_ingress` | Install ingress controller or manage existing | `false` | Yes |
| `nginx_ingress_version` | Chart version to install | `4.14.2` | No |
| `replica_count` | Number of controller replicas | `1` | No |
| `ingress_class_name` | IngressClass name for routing | `nginx` | No |
| `release_name` | Helm release name | `nginx-monitoring` | No |
| `namespace` | Kubernetes namespace | `ingress-nginx` | No |

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
- Helm release `nginx-monitoring` will be created
- Namespace `ingress-nginx` will be created
- LoadBalancer service will be provisioned

Example output:
```
Terraform will perform the following actions:

  # helm_release.nginx_ingress[0] will be created
  + resource "helm_release" "nginx_ingress" {
      + chart            = "ingress-nginx"
      + namespace        = "ingress-nginx"
      + version          = "4.14.2"
      ...
    }

Plan: 2 to add, 0 to change, 0 to destroy.
```

---

### Step 7: Apply Configuration

Deploy NGINX Ingress Controller:

```bash
terraform apply
```

Review the plan and type `yes` when prompted.

Installation typically completes in 2-5 minutes (includes LoadBalancer provisioning time).

**To skip confirmation prompt:**
```bash
terraform apply -auto-approve
```

---

### Step 8: Verify Deployment

Check ingress controller pods:

```bash
kubectl get pods -n ingress-nginx
```

Expected output:
```
NAME                                                READY   STATUS    RESTARTS   AGE
nginx-monitoring-ingress-nginx-controller-xxxxx     1/1     Running   0          2m
nginx-monitoring-ingress-nginx-controller-yyyyy     1/1     Running   0          2m
```

Verify LoadBalancer service and external IP:

```bash
kubectl get svc -n ingress-nginx
```

Expected output:
```
NAME                                          TYPE           CLUSTER-IP      EXTERNAL-IP       PORT(S)
nginx-monitoring-ingress-nginx-controller     LoadBalancer   10.52.x.x       34.123.45.67      80:xxxxx/TCP,443:yyyyy/TCP
```

**The `EXTERNAL-IP` should show a public IP address** (not `<pending>`).

Save the external IP:
```bash
EXTERNAL_IP=$(kubectl get svc -n ingress-nginx \
  nginx-monitoring-ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
  
echo "External IP: $EXTERNAL_IP"
```

Verify IngressClass:

```bash
kubectl get ingressclass nginx
```

Expected output:
```
NAME    CONTROLLER                      PARAMETERS   AGE
nginx   k8s.io/ingress-nginx            <none>       3m
```

---

## DNS Configuration

Point your domain to the LoadBalancer external IP.

**Step 1: Get external IP**
```bash
kubectl get svc -n ingress-nginx \
  nginx-monitoring-ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

**Step 2: Create DNS A records**

Configure DNS records in your DNS provider:

| Type | Name | Value |
|------|------|-------|
| A | `myapp.example.com` | `<EXTERNAL-IP>` |
| A | `*.example.com` | `<EXTERNAL-IP>` (wildcard for subdomains) |

**Step 3: Wait for DNS propagation** (typically 5-30 minutes)

Test DNS resolution:
```bash
dig myapp.example.com
nslookup myapp.example.com
```

---

## Usage

Create Ingress resources to route traffic to your services.

### Basic HTTP Routing

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp-ingress
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

### HTTPS with Automatic TLS

Configure TLS with cert-manager annotation:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp-ingress
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

**Requires:** cert-manager deployed ([deployment guide](cert-manager-terraform-deployment.md))

---

## Upgrading NGINX Ingress Controller

Update the version in `terraform.tfvars`:

```hcl
nginx_ingress_version = "4.15.0"
```

Plan and apply the upgrade:

```bash
terraform plan
terraform apply
```

Terraform performs a rolling update with zero downtime.

---

## Scaling Replicas

Update replica count in `terraform.tfvars`:

```hcl
replica_count = 3
```

Apply the change:

```bash
terraform apply
```

Verify scaling:
```bash
kubectl get pods -n ingress-nginx
```

---

## Managing Existing Installation

If NGINX Ingress Controller is already installed and you want Terraform to manage it:

1. Set `install_nginx_ingress = true` in `terraform.tfvars`
2. Import the existing Helm release:

```bash
terraform import 'helm_release.nginx_ingress[0]' ingress-nginx/nginx-monitoring
```

3. Run `terraform plan` to verify no changes are detected

For detailed adoption procedures, see [Adopting Existing NGINX Ingress Installation](adopting-ingress-controller.md).

---

## Uninstalling

**Warning:** Uninstalling removes the LoadBalancer and breaks all Ingress-based routing.

```bash
terraform destroy
```

Review the destruction plan and type `yes` when prompted.

This removes:
- Helm release `nginx-monitoring`
- LoadBalancer service (releases external IP)
- Namespace `ingress-nginx`
- IngressClass `nginx`

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
ingress-controller/
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
cd ingress-controller/terraform
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

### External IP Stuck in Pending

Check service events:
```bash
kubectl describe svc -n ingress-nginx nginx-monitoring-ingress-nginx-controller
```

**Common causes:**

| Cause | Resolution |
|-------|-----------|
| Cloud provider quota exceeded | Check external IP quota in cloud console |
| Insufficient IAM permissions | Verify service account has LoadBalancer creation permission |
| No LoadBalancer support | Install MetalLB for on-premise clusters |

**For on-premise clusters**, install MetalLB:
```bash
helm repo add metallb https://metallb.github.io/metallb
helm install metallb metallb/metallb --namespace metallb-system --create-namespace
```

---

### Pods Not Starting

Check pod status and logs:
```bash
kubectl describe pod <pod-name> -n ingress-nginx
kubectl logs <pod-name> -n ingress-nginx
```

**Common causes:**
- Insufficient cluster resources
- Image pull issues
- Port conflicts

---

### Ingress Returns 404 Not Found

Check Ingress configuration:
```bash
kubectl get ingress -A
kubectl describe ingress <ingress-name> -n <namespace>
```

**Common issues:**

| Symptom | Cause | Resolution |
|---------|-------|-----------|
| No Ingress Address | Not associated with controller | Verify `ingressClassName: nginx` |
| Backend service missing | Service doesn't exist | Check `kubectl get svc <service>` |
| No endpoints | Pods not running | Check `kubectl get endpoints <service>` |

Review [Troubleshooting Guide](troubleshooting-ingress-controller.md) for detailed debugging steps.

---

## Terraform Output Values

View deployment information:

```bash
terraform output
```

No outputs are currently defined. To add outputs, create `outputs.tf`:

```hcl
output "namespace" {
  description = "Namespace where ingress controller is installed"
  value       = var.namespace
}

output "release_name" {
  description = "Helm release name"
  value       = var.release_name
}

output "nginx_ingress_version" {
  description = "NGINX Ingress Controller version installed"
  value       = var.nginx_ingress_version
}

output "ingress_class_name" {
  description = "IngressClass name"
  value       = var.ingress_class_name
}

output "loadbalancer_ip" {
  description = "LoadBalancer external IP address"
  value       = var.install_nginx_ingress ? data.kubernetes_service.nginx_ingress[0].status[0].load_balancer[0].ingress[0].ip : null
}
```

To enable LoadBalancer IP output, add data source to `main.tf`:
```hcl
data "kubernetes_service" "nginx_ingress" {
  count = var.install_nginx_ingress ? 1 : 0

  metadata {
    name      = "${var.release_name}-ingress-nginx-controller"
    namespace = var.namespace
  }

  depends_on = [helm_release.nginx_ingress]
}
```

---

## Related Documentation

- [Manual Helm Deployment](ingress-controller-manual-deployment.md) - Direct Helm command-line deployment
- [GitHub Actions Deployment](ingress-controller-github-actions.md) - Automated CI/CD workflow
- [Terraform State Management](terraform-state-management.md) - Remote state configuration
- [Troubleshooting Guide](troubleshooting-ingress-controller.md) - Common issues and resolutions
- [Adopting Existing Installation](adopting-ingress-controller.md) - Migration guide

---

**Official Documentation**: [kubernetes.github.io/ingress-nginx](https://kubernetes.github.io/ingress-nginx/)
