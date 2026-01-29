# Kubernetes Observability & Operations

Production-ready infrastructure-as-code for deploying enterprise observability and operational tooling on Google Kubernetes Engine (GKE). This repository provides modular, production-grade deployments where each component can be installed independently or as part of a complete observability and operations stack.

## Requirements

- [Google Kubernetes Engine (GKE)](https://cloud.google.com/kubernetes-engine/docs/quickstart) cluster
- [kubectl](https://kubernetes.io/docs/tasks/tools/) configured with cluster admin access
- [Helm 3.8+](https://helm.sh/docs/intro/install/) (for manual deployments)
- [Terraform 1.3+](https://developer.hashicorp.com/terraform/install) (for automated deployments)

## Architecture

This repository follows a modular architecture where components maintain operational independence while integrating seamlessly. Deploy individual components as needed or provision the complete stack for full observability coverage.

## Components

### [LGTM Observability Stack](lgtm-stack/README.md)
Comprehensive monitoring, logging, and distributed tracing platform built on Grafana Labs' open-source stack (Loki, Grafana, Tempo, Mimir).

### [ArgoCD GitOps Engine](argocd/README.md)
Declarative continuous delivery system for managing Kubernetes applications and configurations through Git-based workflows.

### [ArgoCD Agent (Hub-and-Spoke)](argocd-agent/README.md)
Production-grade multi-cluster GitOps with Argo CD Agent Managed Mode for centralized control plane with distributed spoke clusters.

### [cert-manager Certificate Authority](cert-manager/README.md)
Automated X.509 certificate lifecycle management with native support for ACME providers including Let's Encrypt.

### [NGINX Ingress Controller](ingress-controller/README.md)
Layer 7 load balancer and reverse proxy for routing external HTTP/HTTPS traffic to cluster services.

## Deployment & State Management

### Automated Deployment (GitHub Actions)

Components with automated workflows (cert-manager, ingress-controller):
- See individual component `DEPLOYMENT_SETUP.md` for configuration
- Workflows support GKE, EKS, and AKS
- State files managed in cloud storage buckets
- Automatic plan on PR, apply on main branch merge

### Terraform Deployment (Manual)

Components using Terraform (lgtm-stack, argocd-agent):
- Configure backend with `.github/scripts/configure-backend.sh`
- Supports GKE (GCS), EKS (S3), AKS (Azure Blob)
- Team collaboration via shared state buckets
- See individual component `DEPLOYMENT_SETUP.md`

### State Management Overview

**All components use remote state storage:**
- State files stored in cloud provider buckets (GCS/S3/Azure Blob)
- State files **NEVER deleted** between runs
- Team collaboration via shared buckets
- State locking prevents concurrent modifications
- See [Terraform State Management Guide](docs/terraform-state-management.md)

### Quick Setup Links

- **cert-manager**: [GKE](docs/deployment-cert-manager.md#gke-google-kubernetes-engine-setup) | [EKS](docs/deployment-cert-manager.md#eks-amazon-elastic-kubernetes-service-setup) | [AKS](docs/deployment-cert-manager.md#aks-azure-kubernetes-service-setup)
- **ingress-controller**: [Terraform Deployment Guide](docs/ingress-controller-terraform-deployment.md)
- **lgtm-stack**: [Terraform Deployment Guide](docs/kubernetes-observability.md)
- **argocd-agent**: [Terraform Deployment Guide](docs/argocd-agent-terraform-deployment.md)