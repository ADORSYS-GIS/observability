# ArgoCD GitOps Platform

Declarative GitOps continuous delivery for Kubernetes applications and configurations.

**Official Documentation**: [argo-cd.readthedocs.io](https://argo-cd.readthedocs.io/)  
**GitHub Repository**: [argoproj/argo-cd](https://github.com/argoproj/argo-cd)

## Features

- **GitOps Workflow**: Application deployment from Git as single source of truth
- **Automated Sync**: Continuous reconciliation of desired state with cluster state
- **Multi-Cluster Management**: Deploy and manage applications across multiple clusters
- **RBAC & SSO**: Keycloak integration for authentication and role-based access control
- **Application Health**: Real-time monitoring of deployment status and resource health

## Deployment

### Automated (Terraform)
Recommended approach with infrastructure-as-code management.

See [Terraform deployment guide](../docs/argocd-terraform-deployment.md)

### Manual (Helm)
Uses production-ready values at [`manual/argocd-prod-values.yaml`](manual/argocd-prod-values.yaml)

See [Manual deployment guide](../docs/manual-argocd-deployment.md)

## Operations

- **Adopting Existing Installation**: [Adoption guide](../docs/adopting-argocd.md)
- **Troubleshooting**: [Troubleshooting guide](../docs/troubleshooting-argocd.md)

## Access

After deployment, ArgoCD UI is available at the configured ingress hostname with SSO authentication via Keycloak.