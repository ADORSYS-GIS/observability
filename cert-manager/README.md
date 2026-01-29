# cert-manager

Automated TLS certificate management for Kubernetes with ACME provider support (Let's Encrypt).

**Official**: [cert-manager.io/docs](https://cert-manager.io/docs/) | **GitHub**: [cert-manager/cert-manager](https://github.com/cert-manager/cert-manager)

## Features

- Multi-cloud support (GKE, EKS, AKS, generic Kubernetes)
- Automated certificate provisioning and renewal
- ACME protocol (Let's Encrypt production and staging)
- Ingress TLS termination
- Certificate lifecycle management via Custom Resource Definitions

## Deployment

| Method | Guide | Use Case |
|--------|-------|----------|
| **Manual** | [Manual Deployment](../docs/cert-manager-manual-deployment.md) | Quick setup with Helm/kubectl |
| **Terraform** | [Terraform Deployment](../docs/cert-manager-terraform-deployment.md) | IaC with remote state |
| **GitHub Actions** | See workflows in `.github/workflows/deploy-cert-manager-*.yaml` | Automated CI/CD |

## Operations

- [Adopting Existing Installation](../docs/adopting-cert-manager.md)
- [Troubleshooting](../docs/troubleshooting-cert-manager.md)
