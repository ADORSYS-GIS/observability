# Kubernetes Observability & Operations

Production-ready infrastructure-as-code for enterprise observability and operational tooling on Kubernetes. Modular components deployable independently or as a complete stack.

## Features

- **Multi-Cloud Deployment**: Seamless deployment across GKE, EKS, AKS, or any Kubernetes cluster
- **Flexible Automation**: Manual Helm, Terraform CLI, or GitHub Actions CI/CD workflows
- **Remote State Management**: Team collaboration with cloud-native backends (GCS, S3, Azure Blob)
- **Zero-Downtime Upgrades**: Production-ready deployments with rollback capabilities
- **Complete Documentation**: Comprehensive guides for all deployment methods and components

## Prerequisites

| Tool | Version | Required For |
|------|---------|-------------|
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | ≥ 1.24 | All deployments |
| [Helm](https://helm.sh/docs/intro/install/) | ≥ 3.12 | Manual deployments |
| [Terraform](https://developer.hashicorp.com/terraform/install) | ≥ 1.5.0 | Terraform deployments |
| Kubernetes Cluster | ≥ 1.24 | GKE, EKS, AKS, or generic |

## Deployment Methods

Choose the deployment approach that fits your workflow:

**Manual Deployment (Helm + kubectl)**

Direct command-line deployment for hands-on control and step-by-step visibility. Ideal for learning environments and quick setups.

**Terraform CLI**

Infrastructure-as-code with version control and remote state management. Best for reproducible multi-environment deployments and IaC workflows.

**GitHub Actions Automation**

Fully automated CI/CD pipelines with PR-based reviews and production approvals. Currently available for cert-manager and ingress-controller.

> **Note**: State management is handled automatically in GitHub Actions workflows. For Terraform CLI deployments, backends can be configured using provided templates. See [Terraform State Management Guide](docs/terraform-state-management.md) for details.

## Infrastructure Stack

| Component | Purpose | Documentation |
|-----------|---------|---------------|
| **[LGTM Stack](lgtm-stack/)** | Complete observability with Loki (logs), Grafana (dashboards), Tempo (traces), and Mimir (metrics) | [README](lgtm-stack/README.md) |
| **[ArgoCD](argocd/)** | GitOps continuous delivery for declarative Kubernetes deployments | [README](argocd/README.md) |
| **[ArgoCD Agent](argocd-agent/)** | Multi-cluster hub-and-spoke architecture for centralized GitOps | [README](argocd-agent/README.md) |
| **[cert-manager](cert-manager/)** | Automated TLS certificate provisioning and renewal with Let's Encrypt | [README](cert-manager/README.md) |
| **[Ingress Controller](ingress-controller/)** | NGINX-based Layer 7 load balancing and HTTP/HTTPS routing | [README](ingress-controller/README.md) |