# Argo CD Deployment Guide

Argo CD is a declarative, GitOps continuous delivery tool for Kubernetes. It automates the deployment of applications by continuously monitoring Git repositories and synchronizing the desired application state with the live state in your Kubernetes cluster.

## Deployment Options

We provide two ways to deploy Argo CD to your Kubernetes cluster:

### 1. Manual Deployment

Deploy Argo CD manually using Helm with customizable values files. This approach gives you full control over the configuration and is ideal for:

- Learning how Argo CD works
- Custom configurations not covered by automation
- Environments where Terraform is not available

**[Manual Deployment Guide](../docs/manual-argocd-deployment.md)**

The manual deployment uses the production-ready values file located at [`argocd/manual/argocd-prod-values.yaml`](manual/argocd-prod-values.yaml), which includes:

- High availability configuration with Redis HA
- Autoscaling for repo-server and API server
- HTTPS ingress with cert-manager integration
- OIDC authentication setup (Keycloak example)
- RBAC policies for multi-tenancy

### 2. Automated Deployment (Terraform)

Deploy Argo CD automatically using Terraform for infrastructure-as-code management. This approach is ideal for:

- Production environments
- Repeatable deployments across multiple clusters
- Integration with existing Terraform infrastructure
- Team collaboration with version-controlled infrastructure

**[Automated Deployment Guide](#)** *(Coming soon)*

The automated deployment is located in the [`argocd/terraform/`](terraform) directory and provides:

- Declarative infrastructure-as-code
- Automated dependency management (cert-manager, ingress controller)
- Environment-specific configurations (dev, prod)
- Integration with GCP/GKE infrastructure

