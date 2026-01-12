# Argo CD Deployment Guide

Argo CD is a declarative, GitOps continuous delivery tool for Kubernetes. It automates the deployment of applications by continuously monitoring Git repositories and synchronizing the desired application state with the live state in your Kubernetes cluster.

## Deployment Options

We provide two ways to deploy Argo CD to your Kubernetes cluster:

### 1. Manual Deployment

Deploy Argo CD manually using Helm with customizable values files. This approach gives you full control over the configurations.

**[Manual Deployment Guide](../docs/manual-argocd-deployment.md)**

The manual deployment uses the production-ready values file located at [`argocd/manual/argocd-prod-values.yaml`](manual/argocd-prod-values.yaml),

### 2. Automated Deployment (Terraform)

Deploy Argo CD automatically using Terraform for infrastructure-as-code management

**[Automated Deployment Guide](#)** *(Coming soon)*

The automated deployment is located in the [`argocd/terraform/`](terraform)

