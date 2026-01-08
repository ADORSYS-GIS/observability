# Observability Stack with GKE, LGTM, and ArgoCD

Complete infrastructure and application stack for observability on Google Kubernetes Engine (GKE).

## Components

- **GKE**: Google Kubernetes Engine cluster
- **LGTM Stack**: 
  - Loki (logs)
  - Grafana (visualization)
  - Tempo (traces)
  - Mimir (metrics)
- **ArgoCD**: GitOps continuous deployment
- **Cert-Manager**: Automated certificate management
- **Ingress Controller**: Nginx ingress controller

## Quick Start

```bash
# Setup
make setup
make pre-commit-install

# View all commands
make help
