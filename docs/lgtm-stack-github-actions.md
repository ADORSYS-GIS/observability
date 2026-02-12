# LGTM Stack GitHub Actions Deployment

Automated observability stack deployment using GitHub Actions CI/CD workflows.

**Official Documentation**: [Grafana Loki](https://grafana.com/docs/loki/latest/) | [Grafana Mimir](https://grafana.com/docs/mimir/latest/) | [Grafana Tempo](https://grafana.com/docs/tempo/latest/) | [Grafana](https://grafana.com/docs/grafana/latest/)

> **Already have LGTM Stack installed?** See [Adopting Existing Installation](adopting-lgtm-stack.md).

---

## Overview

Deploy the LGTM stack (Loki, Grafana, Tempo, Mimir) to GKE, EKS, or Generic Kubernetes using GitHub Actions.

**Key Features:**
- **Automated Backend**: Configures GCS/S3/K8s state storage automatically.
- **Secure Auth**: Uses Workload Identity (GKE) or IRSA (EKS).
- **Plan & Apply**: Review `terraform plan` artifacts before deployment.
- **Zero-Downtime**: Handles upgrades and scaling seamlessly.

---

## Workflow Files

The following workflows are available in this repository:

| Provider | Workflow File | Description |
|----------|---------------|-------------|
| **GKE** | [`deploy-lgtm-gke.yaml`](../.github/workflows/deploy-lgtm-gke.yaml) | Deployment for Google Kubernetes Engine using Workload Identity. |
| **EKS** | [`deploy-lgtm-eks.yaml`](../.github/workflows/deploy-lgtm-eks.yaml) | Deployment for AWS EKS using IRSA and S3 state backend. |
| **Generic** | [`deploy-lgtm-generic.yaml`](../.github/workflows/deploy-lgtm-generic.yaml) | Deployment for Agnostic Kubernetes clusters with local/K8s backend. |
| **Destroy** | [`destroy-lgtm-stack.yaml`](../.github/workflows/destroy-lgtm-stack.yaml) |Automated teardown of the stack (preserves storage buckets by default). |

---

## Prerequisites

| Component | Requirement |
|-----------|-------------|
| Kubernetes Cluster | GKE, EKS, or Generic (≥ 1.24) |
| Cloud Credentials | Service Account (GCP), IAM User (AWS) |
| Metrics Store | GCS Bucket (GCP) or S3 Bucket (AWS) |
| Ingress Controller | NGINX installed ([Guide](ingress-controller-github-actions.md)) |
| Cert Manager | Installed ([Guide](cert-manager-github-actions.md)) |

---

## Setup

### Step 1: Configure GitHub Secrets

Navigate to **Settings → Secrets and variables → Actions → New repository secret**.

#### Common Secrets (All Providers)

| Secret Name | Description | Example |
|-------------|-------------|---------|
| `GRAFANA_ADMIN_PASSWORD` | **Required**. Secure password for Grafana admin user. | `StrictP@ssw0rd!` |
| `MONITORING_DOMAIN` | **Required**. Base domain for ingress endpoints. | `monitoring.example.com` |
| `LETSENCRYPT_EMAIL` | **Required**. Email for certificate notifications. | `ops@example.com` |
| `TF_STATE_BUCKET` | **Required**. Name of the S3/GCS bucket for state. | `my-tf-state-bucket` |

#### GKE (Google Kubernetes Engine)

| Secret Name | Description |
|-------------|-------------|
| `GCP_SA_KEY` | Base64-encoded Service Account JSON key. |
| `GCP_PROJECT_ID` | GCP Project ID. |
| `CLUSTER_NAME` | GKE Cluster Name. |
| `CLUSTER_LOCATION` | Region (e.g., `us-central1`) or Zone. |
| `REGION` | GCP Region for resources (e.g., `us-central1`). |

#### EKS (Amazon Elastic Kubernetes Service)

| Secret Name | Description |
|-------------|-------------|
| `AWS_ACCESS_KEY_ID` | IAM User Access Key. |
| `AWS_SECRET_ACCESS_KEY` | IAM User Secret Key. |
| `AWS_REGION` | AWS Region (e.g., `us-east-1`). |
| `EKS_OIDC_PROVIDER_ARN` | **Required**. OIDC Provider ARN for IRSA. |
| `CLUSTER_NAME` | EKS Cluster Name. |

---

### Step 2: Configure Repository Variables

Navigate to **Settings → Secrets and variables → Actions → Variables**. These control specific stack versions and behavior.

| Variable | Description | Default |
|----------|-------------|---------|
| `LOKI_VERSION` | Helm chart version for Loki. | `6.20.0` |
| `MIMIR_VERSION` | Helm chart version for Mimir. | `5.5.0` |
| `TEMPO_VERSION` | Helm chart version for Tempo. | `1.57.0` |
| `GRAFANA_VERSION` | Helm chart version for Grafana. | `10.3.0` |
| `PROMETHEUS_VERSION` | Helm chart version for Prometheus. | `25.27.0` |
| `INSTALL_CERT_MANAGER` | Set to `true` if you want this stack to manage Cert-Manager. | `false` |
| `INSTALL_NGINX_INGRESS`| Set to `true` if you want this stack to manage NGINX. | `false` |

---

### Step 3: Deploy LGTM Stack

**Option A: Manual Trigger**
1. Go to **Actions** tab.
2. Select **Deploy LGTM Stack (GKE/EKS/Generic)**.
3. Click **Run workflow**.
4. Select `plan` to preview or `apply` to deploy.

**Option B: Automated Trigger**
- **Push to main**: Triggers `terraform apply`.
- **Pull Request**: Triggers `terraform plan` for review.

---

## Adopting Existing Installation

The workflow includes an **automated import** feature for existing stacks.

1. Run the workflow manually.
2. Check **"Import existing resources"**.
3. Select `apply`.

**What happens:**
- Detects existing Helm releases (Loki, Mimir, etc.).
- Imports GCS buckets and Service Accounts.
- Imports Kubernetes resources into Terraform state.

---

## Verification

After deployment, verify the stack status:

```bash
# Check Pods
kubectl get pods -n lgtm

# Check Ingress
kubectl get ingress -n lgtm
```

### Access Grafana
URL: `https://grafana.MONITORING_DOMAIN`
User: `admin`
Pass: `${GRAFANA_ADMIN_PASSWORD}`

---

## DNS Configuration

Create A records pointing to your NGINX LoadBalancer IP:

| Host | Target |
|------|--------|
| `grafana.monitoring.example.com` | `LOAD_BALANCER_IP` |
| `loki.monitoring.example.com` | `LOAD_BALANCER_IP` |
| `mimir.monitoring.example.com` | `LOAD_BALANCER_IP` |
| `tempo.monitoring.example.com` | `LOAD_BALANCER_IP` |

---

## Troubleshooting

### Workflow Failures
- **Auth Errors**: Verify `GCP_SA_KEY` is base64 encoded (`cat key.json | base64 -w 0`).
- **State Lock**: If a previous run failed, clear the lock via console or specific unlock command.

### "Already Exists" Error
- Use the **"Import existing resources"** checkbox in the manual workflow trigger to resolve conflicts.

For deep-dive issues, see the [Troubleshooting Guide](troubleshooting-lgtm-stack.md).

---

## Related Documentation

- [Terraform CLI Deployment](lgtm-stack-terraform-deployment.md)
- [Manual Deployment](manual-lgtm-deployment.md)
- [Troubleshooting Guide](troubleshooting-lgtm-stack.md)
