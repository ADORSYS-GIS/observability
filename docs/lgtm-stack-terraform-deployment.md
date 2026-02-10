# LGTM Stack Terraform CLI Deployment

Infrastructure-as-Code deployment using Terraform for reproducible, version-controlled observability.

**Official Documentation**: [Grafana Loki](https://grafana.com/docs/loki/latest/) | [Grafana Mimir](https://grafana.com/docs/mimir/latest/) | [Grafana Tempo](https://grafana.com/docs/tempo/latest/) | [Grafana](https://grafana.com/docs/grafana/latest/)

> **Already have LGTM Stack installed?** See [Adopting Existing Installation](adopting-lgtm-stack.md).

---

## Prerequisites

| Tool | Version | Verification |
|------|---------|--------------|
| Terraform | ≥ 1.5.0 | `terraform version` |
| kubectl | ≥ 1.24 | `kubectl version --client` |
| Cloud CLI | Authenticated | `gcloud`, `aws`, or `az` |
| Cluster | ≥ 1.24 | `kubectl cluster-info` |

**Dependencies:**
- **Storage**: Cloud bucket creation permissions (GCS/S3) or PersistentVolumes.
- **Ingress**: NGINX Ingress (controlled via `install_nginx_ingress` var).
- **TLS**: Cert-Manager (controlled via `install_cert_manager` var).

---

## Important: Multi-Cluster Environments

For deployments with multiple clusters, explicit targeting in `terraform.tfvars` is recommended.

**GKE Example:**
```bash
# Get endpoint and CA cert
gcloud container clusters describe CLUSTER --region REGION --format='value(endpoint)'
gcloud container clusters describe CLUSTER --region REGION --format='value(masterAuth.clusterCaCertificate)'
```

---

## Terraform State Management

**Recommended**: Use remote state backends for team collaboration.

| Provider | Backend | State Path |
|----------|---------|-----------|
| GKE | GCS | `gs://<bucket>/terraform/lgtm-stack/terraform.tfstate` |
| EKS | S3 | `s3://<bucket>/terraform/lgtm-stack/terraform.tfstate` |
| Generic | Local | `./terraform.tfstate` |

See [Terraform State Management Guide](terraform-state-management.md) for setup details.

---

## Installation

### Step 1: Navigate to Directory
```bash
cd lgtm-stack/terraform
```

### Step 2: Configure Backend
Use the helper script to generate `backend-config.tf`:

```bash
# GKE Example
export TF_STATE_BUCKET="your-gcs-bucket"
../../.github/scripts/configure-backend.sh gke lgtm-stack
```

### Step 3: Configure Variables
Copy template and edit:
```bash
cp terraform.tfvars.template terraform.tfvars
```

**Minimal Configuration (GKE):**
```hcl
cloud_provider = "gke"
project_id     = "your-project-id"
region         = "us-central1"
cluster_name   = "your-cluster"

monitoring_domain = "monitoring.example.com"
letsencrypt_email = "admin@example.com"
grafana_password  = "your-secure-password"

# Set to false if using shared/existing infrastructure
install_cert_manager  = false
install_nginx_ingress = false
```

### Step 4: Verify Configuration
```bash
grep -E "cloud_provider|project_id" terraform.tfvars
```

### Step 5: Initialize
```bash
terraform init
```

### Step 6: Plan
```bash
terraform plan
```

### Step 7: Apply
```bash
terraform apply
```

### Step 8: Verify Deployment
```bash
kubectl get pods -n lgtm
# All pods should be Running
```

---

## Verification

### Service Endpoints

| Service | Endpoint |
|---------|----------|
| **Grafana** | `https://grafana.monitoring.example.com` |
| **Loki** | `https://loki.monitoring.example.com/loki/api/v1/push` |
| **Mimir** | `https://mimir.monitoring.example.com/prometheus/api/v1/push` |
| **Tempo** | `https://tempo-push.monitoring.example.com/v1/traces` |

### Test Connectivity

**Grafana Login**:
- User: `admin`
- Password: (value from `terraform.tfvars`)

**Test Log Query (Loki)**:
Explore -> Source "Loki" -> Run query `{namespace="lgtm"}`

---

## Operations

### Upgrading Components
Update versions in `terraform.tfvars` and run `terraform apply`.

```hcl
loki_version = "6.21.0"
```

### Uninstalling
```bash
terraform destroy
```
> **Note**: Storage buckets are NOT deleted by default to prevent data loss.

---

## Troubleshooting

### State Lock Error
```bash
terraform force-unlock <LOCK_ID>
```

### Pods Pending
Check PVCs and storage permissions:
```bash
kubectl describe pod <pod-name> -n lgtm
gcloud storage ls gs://<bucket-name>
```

For detailed solutions, see [Troubleshooting Guide](troubleshooting-lgtm-stack.md).