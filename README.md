# Kubernetes Observability & Operations

Production-ready infrastructure-as-code for deploying enterprise observability and operational tooling on **any Kubernetes cluster**. This repository provides modular, production-grade deployments for GKE, EKS, AKS, and generic Kubernetes clusters where each component can be installed independently or as part of a complete observability and operations stack.

## Requirements

- [Kubernetes](https://kubernetes.io/docs/setup/) cluster (GKE, EKS, AKS, minikube, kind, or on-premise)
- [kubectl](https://kubernetes.io/docs/tasks/tools/) configured with cluster admin access
- [Helm 3.8+](https://helm.sh/docs/intro/install/) (for manual deployments)
- [Terraform 1.3+](https://developer.hashicorp.com/terraform/install) (for automated deployments)
- GitHub repository (for GitHub Actions deployments)

## Architecture

This repository follows a modular architecture where components maintain operational independence while integrating seamlessly. Deploy individual components as needed or provision the complete stack for full observability coverage.

## Deployment Methods

### [GitHub Actions (Recommended)](docs/github-actions-deployment.md)
**Automated CI/CD deployment** using GitHub Actions workflows with Terraform. Supports all cloud providers (GKE, EKS, AKS, generic K8s) with automated testing and verification.

**Features:**
- ✅ Cloud-agnostic (GKE/EKS/AKS/Generic)
- ✅ Automated resource import (no conflicts)
- ✅ Comprehensive smoke tests
- ✅ Post-deployment verification
- ✅ Safe teardown workflows

**Quick Start:**
1. Configure GitHub secrets
2. Trigger workflow from Actions tab
3. Verify deployment with automatic tests

[→ GitHub Actions Deployment Guide](docs/github-actions-deployment.md)

### Manual Terraform
For direct infrastructure management and customization.

### Helm Charts
For granular component control and manual deployments.

## Components

### [LGTM Observability Stack](lgtm-stack/README.md)
Comprehensive monitoring, logging, and distributed tracing platform built on Grafana Labs' open-source stack (Loki, Grafana, Tempo, Mimir).

### [ArgoCD GitOps Engine](argocd/README.md)
Declarative continuous delivery system for managing Kubernetes applications and configurations through Git-based workflows.

### [cert-manager Certificate Authority](cert-manager/README.md)
Automated X.509 certificate lifecycle management with native support for ACME providers including Let's Encrypt.

### [NGINX Ingress Controller](ingress-controller/README.md)
Layer 7 load balancer and reverse proxy for routing external HTTP/HTTPS traffic to cluster services.