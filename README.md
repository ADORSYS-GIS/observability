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

### [cert-manager Certificate Authority](cert-manager/README.md)
Automated X.509 certificate lifecycle management with native support for ACME providers including Let's Encrypt.

### [NGINX Ingress Controller](ingress-controller/README.md)
Layer 7 load balancer and reverse proxy for routing external HTTP/HTTPS traffic to cluster services.