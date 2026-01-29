# Kubernetes Observability & Operations

Production-ready infrastructure-as-code for enterprise observability and operational tooling on Kubernetes. Modular components deployable independently or as a complete stack.

## Requirements

| Tool | Version | Required For |
|------|---------|-------------|
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | ≥ 1.24 | All deployments |
| [Helm](https://helm.sh/docs/intro/install/) | ≥ 3.12 | Manual deployments |
| [Terraform](https://developer.hashicorp.com/terraform/install) | ≥ 1.5.0 | Terraform deployments |
| Kubernetes Cluster | ≥ 1.24 | GKE, EKS, AKS, or generic |

## Components

| Component | Description | Deployment Guides |
|-----------|-------------|-------------------|
| **[LGTM Stack](lgtm-stack/README.md)** | Monitoring, logging, tracing (Loki, Grafana, Tempo, Mimir) | [Terraform](docs/kubernetes-observability.md) |
| **[ArgoCD](argocd/README.md)** | GitOps continuous delivery | [Manual](docs/manual-argocd-deployment.md) \| [Terraform](docs/argocd-terraform-deployment.md) |
| **[ArgoCD Agent](argocd-agent/README.md)** | Multi-cluster GitOps (hub-and-spoke) | [Terraform](docs/argocd-agent-terraform-deployment.md) |
| **[cert-manager](cert-manager/README.md)** | Automated TLS certificate management | [Manual](docs/cert-manager-manual-deployment.md) \| [Terraform](docs/cert-manager-terraform-deployment.md) |
| **[Ingress Controller](ingress-controller/README.md)** | NGINX Layer 7 load balancing | [Manual](docs/ingress-controller-manual-deployment.md) \| [Terraform](docs/ingress-controller-terraform-deployment.md) |

## Deployment Methods

### Method 1: Manual (Helm + kubectl)
Direct deployment using command-line tools. See component-specific manual deployment guides.

### Method 2: Terraform CLI
Infrastructure-as-code deployment with remote state storage.

```bash
cd observability/<component>/terraform

export TF_STATE_BUCKET="your-bucket-name"
bash ../../.github/scripts/configure-backend.sh gke <component>

terraform init
terraform plan
terraform apply
```

### Method 3: Terraform + GitHub Actions
Automated CI/CD deployment (cert-manager, ingress-controller only).

- **Plan**: Triggered on PR
- **Apply**: Triggered on merge to `main`
- **State**: Managed in cloud storage (GCS/S3/Azure Blob)

## State Management

All Terraform deployments use remote state storage for team collaboration:

| Provider | Backend | State Location |
|----------|---------|----------------|
| **GKE** | Google Cloud Storage | `gs://<bucket>/terraform/<component>/terraform.tfstate` |
| **EKS** | AWS S3 + DynamoDB | `s3://<bucket>/terraform/<component>/terraform.tfstate` |
| **AKS** | Azure Blob Storage | `<account>/<container>/terraform/<component>/terraform.tfstate` |

**State files persist across all deployments and are never deleted.**

See [Terraform State Management Guide](docs/terraform-state-management.md) for bucket setup.