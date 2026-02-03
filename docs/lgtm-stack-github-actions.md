# LGTM Stack GitHub Actions Deployment

Automated observability stack deployment using GitHub Actions CI/CD workflows.

**Official Documentation**: [Grafana Loki](https://grafana.com/docs/loki/latest/) | [Grafana Mimir](https://grafana.com/docs/mimir/latest/) | [Grafana Tempo](https://grafana.com/docs/tempo/latest/) | [Grafana](https://grafana.com/docs/grafana/latest/)

> **Already have LGTM Stack installed?** If you want to manage an existing observability stack deployment with GitHub Actions, see [Adopting Existing Installation](adopting-lgtm-stack.md).

---

## Overview

This deployment method uses GitHub Actions workflows to automatically deploy the LGTM observability stack to Kubernetes clusters via Terraform. The workflows handle backend configuration, authentication, and deployment across GKE, EKS, and Generic Kubernetes.

**Key Features:**
- Automated Terraform backend configuration (GCS/S3/Kubernetes)
- Cloud provider authentication via GitHub Secrets
- Terraform plan review with artifact storage
- Storage bucket provisioning (GCS/S3) or PersistentVolumes
- Deployment verification (pods, services, ingress endpoints)
- Zero-downtime upgrades
- Remote state management

---

## Workflows

| Workflow | Purpose | Cloud Provider |
|----------|---------|----------------|
| `deploy-lgtm-gke.yaml` | Deploy to GKE with Workload Identity | GKE |
| `deploy-lgtm-eks.yaml` | Deploy to EKS with IRSA | EKS |
| `deploy-lgtm-generic.yaml` | Deploy to any Kubernetes cluster | Generic |
| `destroy-lgtm-stack.yaml` | Teardown deployment | All |

---

## Prerequisites

An existing Kubernetes cluster is required:

| Requirement | Description |
|-------------|-------------|
| **Cluster Access** | kubectl configured with admin permissions |
| **Resources** | Minimum: 8 vCPUs, 16GB RAM, 100GB storage |
| **Ingress** | NGINX Ingress Controller (can be installed by workflow) |
| **TLS** | cert-manager (can be installed by workflow) |

> **Important:** Workflows deploy to existing clusters. Cluster provisioning must be done separately.

---

## Setup

### Step 1: Configure GitHub Secrets

Navigate to `Settings → Secrets and variables → Actions → New repository secret`

#### Common Secrets (All Platforms)

| Secret Name | Description |
|-------------|-------------|
| `KUBECONFIG` | Base64-encoded kubeconfig file |
| `GRAFANA_ADMIN_PASSWORD` | Grafana admin password |
| `LETSENCRYPT_EMAIL` | Email for Let's Encrypt certificate notifications |
| `MONITORING_DOMAIN` | Base domain for monitoring services |
| `ENVIRONMENT` | Environment name (production, staging, etc.) |

**Generate KUBECONFIG secret:**
```bash
cat ~/.kube/config | base64 -w 0
```

#### GKE (Google Kubernetes Engine)

| Secret Name | Description |
|-------------|-------------|
| `CLOUD_PROVIDER` | Set to `gke` |
| `GCP_PROJECT_ID` | GCP project ID |
| `GCP_SA_KEY` | Service account JSON key (base64-encoded) |
| `TF_STATE_BUCKET` | GCS bucket name for Terraform state |
| `CLUSTER_NAME` | GKE cluster name |
| `CLUSTER_LOCATION` | GKE cluster location/region |
| `REGION` | GCP region for resources |

**Create service account and encode key:**
```bash
gcloud iam service-accounts create github-actions \
  --display-name "GitHub Actions Service Account"

gcloud iam service-accounts keys create key.json \
  --iam-account=github-actions@PROJECT_ID.iam.gserviceaccount.com

# Encode key for GitHub Secrets
cat key.json | base64 -w 0
```

#### EKS (Amazon Elastic Kubernetes Service)

| Secret Name | Description |
|-------------|-------------|
| `CLOUD_PROVIDER` | Set to `eks` |
| `AWS_ACCESS_KEY_ID` | IAM user access key |
| `AWS_SECRET_ACCESS_KEY` | IAM user secret access key |
| `AWS_REGION` | AWS region |
| `CLUSTER_NAME` | EKS cluster name |
| `TF_STATE_BUCKET` | S3 bucket name for Terraform state |

#### Generic Kubernetes

| Secret Name | Description |
|-------------|-------------|
| `CLOUD_PROVIDER` | Set to `generic` |
| `CLUSTER_NAME` | Kubernetes cluster name |

---

### Step 2: Configure Repository Variables (Optional)

Navigate to `Settings → Secrets and variables → Actions → Variables`

| Variable Name | Description | Default |
|---------------|-------------|---------|
| `TERRAFORM_VERSION` | Terraform version to use | `1.5.0` |
| `INSTALL_CERT_MANAGER` | Install cert-manager | `false` |
| `INSTALL_NGINX_INGRESS` | Install NGINX Ingress | `false` |

---

### Step 3: Deploy LGTM Stack

**Via GitHub UI:**
1. Navigate to `Actions` tab
2. Select `Deploy LGTM Stack (GKE/EKS/Generic)` workflow
3. Click `Run workflow`
4. Select branch and terraform action (`plan` or `apply`)
5. Click `Run workflow`

**Via Pull Request:**
Workflows automatically run `terraform plan` on PR when changes are made to:
- `lgtm-stack/terraform/**`
- `.github/workflows/deploy-lgtm-*.yaml`

**Via Push to Main:**
Automatic `terraform apply` on merge to `main` branch.

---

## Adopting Existing LGTM Stack Installation

If you already have an LGTM stack deployed, the workflow automatically imports existing resources to avoid conflicts.

### How It Works

The workflow runs an import script before `terraform apply`:
1. Detects existing Helm releases (loki, mimir, tempo, grafana, prometheus)
2. Imports them into Terraform state
3. Continues with deployment without recreating resources

### What Gets Imported

- Helm releases (loki, mimir, tempo, grafana, prometheus, alloy)
- Kubernetes namespaces
- Storage buckets (GCS/S3)
- Service accounts and IAM bindings

### Important Notes

- Existing data in storage buckets is preserved
- Configuration may be updated to match Terraform definitions
- Review Terraform plan artifact before approving apply

---

## Verification

After successful workflow completion, verify the deployment:

```bash
# Check pod status
kubectl get pods -n lgtm
```

All pods should be in `Running` status.

```bash
# Verify services
kubectl get svc -n lgtm
```

```bash
# Check ingress endpoints
kubectl get ingress -n lgtm
```

### Access Grafana

Navigate to `https://grafana.MONITORING_DOMAIN` and login with:
- **Username**: `admin`
- **Password**: Value from `GRAFANA_ADMIN_PASSWORD` secret

---

## DNS Configuration

Configure DNS records to point to your LoadBalancer IP:

1. **Get LoadBalancer IP:**
   ```bash
   kubectl get svc -n ingress-nginx ingress-nginx-controller \
     -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
   ```

2. **Create DNS A records:**
   - `grafana.monitoring.example.com` → `LOAD_BALANCER_IP`
   - `loki.monitoring.example.com` → `LOAD_BALANCER_IP`
   - `mimir.monitoring.example.com` → `LOAD_BALANCER_IP`
   - `tempo.monitoring.example.com` → `LOAD_BALANCER_IP`
   - `prometheus.monitoring.example.com` → `LOAD_BALANCER_IP`

   Or use wildcard:
   - `*.monitoring.example.com` → `LOAD_BALANCER_IP`

---

## Uninstalling

To remove the LGTM stack deployment:

1. Navigate to `Actions` tab
2. Select `Destroy LGTM Stack` workflow
3. Click `Run workflow`
4. Confirm destruction

**Warning:** This removes all LGTM components. Storage buckets with `force_destroy = false` will be preserved with data intact.

---

## Troubleshooting

### Workflow Failures

**Check workflow logs:**
1. Navigate to `Actions` tab
2. Click on failed workflow run
3. Review job logs for specific errors

**Download artifacts:**
- `terraform-plan.txt` - Terraform execution plan
- `verification-report.html` - Deployment validation results

### Terraform Apply Fails with "Already Exists"

The import script runs automatically before apply. If resources still conflict:

```bash
# Manually import resources locally
cd lgtm-stack/terraform
terraform import helm_release.loki lgtm/loki
terraform import helm_release.mimir lgtm/mimir
terraform import helm_release.tempo lgtm/tempo
terraform import helm_release.grafana lgtm/grafana
terraform import helm_release.prometheus lgtm/prometheus
```

### Authentication Errors

**GKE:**
```bash
# Verify service account key is valid and base64-encoded
echo $GCP_SA_KEY | base64 -d | jq .
```

**EKS:**
```bash
# Verify AWS credentials
aws sts get-caller-identity
```

### Pod Failures

```bash
# Check pod logs
kubectl logs -n lgtm <pod-name>

# Describe pod for events
kubectl describe pod -n lgtm <pod-name>
```

---

## State Management

Terraform state is stored remotely for collaboration:

| Platform | Backend | Location |
|----------|---------|----------|
| GKE | GCS | `gs://<bucket>/terraform/lgtm-stack/` |
| EKS | S3 | `s3://<bucket>/terraform/lgtm-stack/` |
| Generic | Kubernetes | Secret in `kube-system` namespace |

State files persist across workflow runs and are never deleted by workflows.

---

## Advanced Configuration

### Custom Component Versions

Edit repository variables to override component versions:
- `LOKI_VERSION`
- `MIMIR_VERSION`
- `TEMPO_VERSION`
- `GRAFANA_VERSION`
- `PROMETHEUS_VERSION`

### Manual Smoke Tests

Run smoke tests locally:

```bash
export MONITORING_DOMAIN="monitoring.example.com"
export GRAFANA_ADMIN_PASSWORD="your-password"
bash .github/scripts/smoke-tests.sh
```

---

## Related Documentation

- [Terraform CLI Deployment](lgtm-stack-terraform-deployment.md) - Local Terraform execution
- [Manual Docker Compose Deployment](manual-lgtm-deployment.md) - Local development deployment
- [Terraform State Management](terraform-state-management.md) - Remote state configuration
- [Troubleshooting Guide](troubleshooting-lgtm-stack.md) - Common issues and resolutions
- [Adopting Existing Installation](adopting-lgtm-stack.md) - Migration guide
- [Testing & Verification](testing-monitoring-stack-deployment.md) - Validation procedures
- [Workflows Guide](workflows-guide.md) - GitHub Actions workflow reference

---

**Official Documentation**: [Grafana Loki](https://grafana.com/docs/loki/latest/) | [Grafana Mimir](https://grafana.com/docs/mimir/latest/) | [Grafana Tempo](https://grafana.com/docs/tempo/latest/) | [Grafana](https://grafana.com/docs/grafana/latest/)
