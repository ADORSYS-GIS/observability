# Kubernetes Observability & Operations

Production-ready infrastructure-as-code for deploying enterprise observability and operational tooling on Kubernetes. This repository provides modular, production-grade deployments for GKE, EKS, and generic Kubernetes clusters.

## Supported Providers

- **GKE** (Google Kubernetes Engine) - Fully tested with Workload Identity and GCS.
- **EKS** (Amazon Elastic Kubernetes Service) - Fully tested with IRSA and S3.
- **Generic Kubernetes** (minikube, kind, on-premise) - Supports persistent volumes.

**Note:** AKS (Azure Kubernetes Service) is currently not supported.

## Requirements

- [Kubernetes](https://kubernetes.io/docs/setup/) cluster
- [kubectl](https://kubernetes.io/docs/tasks/tools/) configured with cluster admin access
- [Terraform 1.6+](https://developer.hashicorp.com/terraform/install)
- GitHub repository with configured secrets

## Quick Start (GKE)

1. **Configure Secrets:** Add `GCP_PROJECT_ID`, `GCP_SA_KEY`, `CLUSTER_NAME`, `CLUSTER_LOCATION`, `REGION`, `TF_STATE_BUCKET`, `MONITORING_DOMAIN`, `LETSENCRYPT_EMAIL`, and `GRAFANA_ADMIN_PASSWORD` to GitHub Secrets.
2. **Deploy:** Go to `Actions` → `Deploy LGTM Stack (GKE)` → `Run workflow`.
3. **Verify:** Check the `verification-report.html` artifact after the workflow completes.

## Required Secrets for CI/CD

| Secret | Provider | Description |
|--------|----------|-------------|
| `GCP_PROJECT_ID` | GKE | Your Google Cloud Project ID |
| `GCP_SA_KEY` | GKE | JSON key for deployment Service Account |
| `AWS_ACCESS_KEY_ID` | EKS | AWS Access Key |
| `AWS_SECRET_ACCESS_KEY` | EKS | AWS Secret Key |
| `KUBECONFIG` | Generic | Base64-encoded kubeconfig file |
| `TF_STATE_BUCKET` | GKE/EKS | Bucket name for Terraform state |
| `MONITORING_DOMAIN` | All | Domain for observability (e.g., monitor.example.com) |
| `GRAFANA_ADMIN_PASSWORD` | All | Admin password for Grafana UI |

## Deployment Order & Dependencies

The LGTM stack deployment follows this order:
1. **Namespace & Service Account:** Created first to provide identity.
2. **Cloud Storage & IAM:** Modules configure S3/GCS buckets and IAM bindings.
3. **Core Infrastructure:** cert-manager and ingress-nginx (if enabled).
4. **LGTM Components:** Loki, Mimir, Tempo, and Prometheus.
5. **Grafana:** Deployed last to integrate all data sources.

## Documentation Index

- [GitHub Actions Deployment Guide](docs/github-actions-deployment.md)
- [GKE Testing Workflow](docs/TESTING_GKE_WORKFLOW.md)
- [Workflow Guide](docs/WORKFLOWS_GUIDE.md)
- [LGTM Stack Details](lgtm-stack/README.md)