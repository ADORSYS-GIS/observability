# NGINX Ingress Controller

Layer 7 load balancing and external traffic routing for Kubernetes services.

**Official**: [kubernetes.github.io/ingress-nginx](https://kubernetes.github.io/ingress-nginx/) | **GitHub**: [kubernetes/ingress-nginx](https://github.com/kubernetes/ingress-nginx)

## Features

- Multi-cloud support (GKE, EKS, AKS, generic Kubernetes)
- Cloud provider LoadBalancer integration
- Path-based and host-based routing
- SSL/TLS termination with cert-manager integration
- WebSocket support
- Rate limiting and DDoS protection

## Deployment

| Method | Guide | Use Case |
|--------|-------|----------|
| **Manual** | [Manual Deployment](../docs/ingress-controller-manual-deployment.md) | Quick setup with Helm |
| **Terraform** | [Terraform Deployment](../docs/ingress-controller-terraform-deployment.md) | IaC with remote state |
| **GitHub Actions** | See workflows in `.github/workflows/deploy-ingress-controller-*.yaml` | Automated CI/CD |

## Operations

- [Adopting Existing Installation](../docs/adopting-ingress-controller.md)
- [Troubleshooting](../docs/troubleshooting-ingress-controller.md)
