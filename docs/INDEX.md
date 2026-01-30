# Documentation Index

Complete documentation for production-ready Kubernetes observability and operations infrastructure.

---

## Overview

This repository provides modular, infrastructure-as-code deployments for enterprise observability and GitOps tooling on Google Kubernetes Engine. Each component can be deployed independently or as part of a complete stack.

**Project Repository**: [kubernetes-observability](../README.md)

---

## Components

### [LGTM Observability Stack](../lgtm-stack/README.md)
Correlated metrics, logs, and traces with Grafana Labs' open-source platform (Loki, Grafana, Tempo, Mimir, Alloy).

| Guide | Purpose |
|-------|---------|
| [Terraform Deployment](kubernetes-observability.md) | Automated LGTM deployment |
| [Manual Deployment](manual-lgtm-deployment.md) | Helm-based deployment |
| [Alloy Configuration](alloy-config.md) | Telemetry pipeline setup |
| [Testing & Verification](testing-monitoring-stack-deployment.md) | Validation procedures |
| [Adoption Guide](adopting-lgtm-stack.md) | Import existing stack |
| [Troubleshooting](troubleshooting-lgtm-stack.md) | Common LGTM issues |

### [ArgoCD GitOps Engine](../argocd/README.md)
Declarative continuous delivery for Kubernetes applications and configurations.

| Guide | Purpose |
|-------|---------|
| [Terraform Deployment](argocd-terraform-deployment.md) | Automated ArgoCD deployment |
| [Manual Deployment](manual-argocd-deployment.md) | kubectl-based setup |
| [Adoption Guide](adopting-argocd.md) | Team adoption strategies |
| [Troubleshooting](troubleshooting-argocd.md) | Standard ArgoCD issues |

### [ArgoCD Agent (Hub-and-Spoke)](../argocd-agent/README.md)
Multi-cluster GitOps with centralized control plane and distributed spoke clusters.

| Guide | Purpose |
|-------|---------|
| [Architecture](argocd-agent-architecture.md) | Hub-spoke design and components |
| [Terraform Deployment](argocd-agent-terraform-deployment.md) | Automated hub-spoke deployment |
| [Configuration Reference](argocd-agent-configuration.md) | All Terraform variables |
| [Operations Guide](argocd-agent-operations.md) | Day-2 ops, scaling, certificates, teardown |
| [RBAC & SSO](argocd-agent-rbac.md) | Keycloak integration and permissions |
| [Adoption Guide](adopting-argocd-agent.md) | Migration from standard ArgoCD |
| [Troubleshooting](argocd-agent-troubleshooting.md) | Hub-spoke specific issues |

### [cert-manager Certificate Authority](../cert-manager/README.md)
Automated X.509 certificate lifecycle management with ACME support (Let's Encrypt).

| Guide | Purpose |
|-------|---------|
| [Terraform Deployment](cert-manager-terraform-deployment.md) | Automated cert-manager deployment |
| [Manual Deployment](cert-manager-manual-deployment.md) | kubectl/Helm setup |
| [Adoption Guide](adopting-cert-manager.md) | Import existing installation |
| [Troubleshooting](troubleshooting-cert-manager.md) | Certificate issues |

### [NGINX Ingress Controller](../ingress-controller/README.md)
Layer 7 load balancer and reverse proxy for HTTP/HTTPS traffic routing.

| Guide | Purpose |
|-------|---------|
| [Terraform Deployment](ingress-controller-terraform-deployment.md) | Automated ingress deployment |
| [Manual Deployment](ingress-controller-manual-deployment.md) | kubectl/Helm setup |
| [Adoption Guide](adopting-ingress-controller.md) | Import existing controller |
| [Troubleshooting](troubleshooting-ingress-controller.md) | Ingress routing issues |

---

## Quick Start by Use Case

### Building Full Observability Platform
1. Deploy [LGTM Stack](kubernetes-observability.md) for metrics, logs, traces
2. Deploy [ArgoCD](argocd-terraform-deployment.md) for GitOps delivery
3. Deploy [cert-manager](cert-manager-terraform-deployment.md) for TLS automation
4. Deploy [Ingress Controller](ingress-controller-terraform-deployment.md) for external access
5. Configure [Alloy](alloy-config.md) for application telemetry collection

### Managing Multiple Kubernetes Clusters
1. Understand [Hub-Spoke Architecture](argocd-agent-architecture.md)
2. Review [Configuration Options](argocd-agent-configuration.md)
3. Deploy with [Terraform](argocd-agent-terraform-deployment.md)
4. Set up [RBAC & SSO](argocd-agent-rbac.md)
5. Monitor [Operations](argocd-agent-operations.md)

### Adopting Existing Infrastructure
1. Review adoption guides for your components:
   - [LGTM Stack Adoption](adopting-lgtm-stack.md)
   - [ArgoCD Adoption](adopting-argocd.md)
   - [ArgoCD Agent Adoption](adopting-argocd-agent.md)
   - [cert-manager Adoption](adopting-cert-manager.md)
   - [Ingress Controller Adoption](adopting-ingress-controller.md)
2. Import resources into Terraform state
3. Apply Terraform configurations

---

## Common Tasks

### Deployment
| Task | Documentation |
|------|---------------|
| Deploy observability stack | [LGTM Terraform Guide](kubernetes-observability.md) |
| Deploy single-cluster GitOps | [ArgoCD Terraform Guide](argocd-terraform-deployment.md) |
| Deploy multi-cluster GitOps | [ArgoCD Agent Guide](argocd-agent-terraform-deployment.md) |
| Set up TLS certificates | [cert-manager Guide](cert-manager-terraform-deployment.md) |
| Configure ingress routing | [Ingress Controller Guide](ingress-controller-terraform-deployment.md) |

### Operations
| Task | Documentation |
|------|---------------|
| Add spoke cluster | [Operations: Scaling](argocd-agent-operations.md#adding-a-new-spoke-cluster) |
| Rotate certificates (ArgoCD Agent) | [Operations: Certificate Rotation](argocd-agent-operations.md#certificate-rotation) |
| Configure SSO (ArgoCD) | [RBAC & SSO Guide](argocd-agent-rbac.md) |
| Monitor telemetry pipeline | [Alloy Configuration](alloy-config.md) |
| Teardown infrastructure | [Operations: Teardown](argocd-agent-operations.md#teardown-procedures) |

### Troubleshooting
| Issue | Documentation |
|-------|---------------|
| Apps stuck "Unknown/Unknown" (Agent) | [Agent Troubleshooting](argocd-agent-troubleshooting.md#applications-stuck-in-unknownunknown-status) |
| Certificate not issued | [cert-manager Troubleshooting](troubleshooting-cert-manager.md) |
| Ingress 502/503 errors | [Ingress Troubleshooting](troubleshooting-ingress-controller.md) |
| Missing metrics/logs | [LGTM Troubleshooting](troubleshooting-lgtm-stack.md) |
| ArgoCD sync failures | [ArgoCD Troubleshooting](troubleshooting-argocd.md) |

---

## Terraform Modules

All components use Terraform for infrastructure-as-code:

| Component | Location | Version |
|-----------|----------|---------|
| LGTM Stack | `lgtm-stack/terraform/` | Terraform ≥ 1.3 |
| ArgoCD | `argocd/terraform/` | Terraform ≥ 1.0 |
| ArgoCD Agent | `argocd-agent/terraform/` | Terraform ≥ 1.0 |
| cert-manager | `cert-manager/terraform/` | Terraform ≥ 1.0 |
| Ingress Controller | `ingress-controller/terraform/` | Terraform ≥ 1.0 |

---

## External Resources

### Observability Stack
- **Grafana**: [grafana.com/docs/grafana](https://grafana.com/docs/grafana/latest/)
- **Loki**: [grafana.com/docs/loki](https://grafana.com/docs/loki/latest/)
- **Tempo**: [grafana.com/docs/tempo](https://grafana.com/docs/tempo/latest/)
- **Mimir**: [grafana.com/docs/mimir](https://grafana.com/docs/mimir/latest/)
- **Alloy**: [grafana.com/docs/alloy](https://grafana.com/docs/alloy/latest/)

### GitOps
- **ArgoCD**: [argo-cd.readthedocs.io](https://argo-cd.readthedocs.io/)
- **ArgoCD Agent**: [argocd-agent.readthedocs.io](https://argocd-agent.readthedocs.io/)
- **ArgoCD GitHub**: [github.com/argoproj/argo-cd](https://github.com/argoproj/argo-cd)
- **ArgoCD Agent GitHub**: [github.com/argoproj-labs/argocd-agent](https://github.com/argoproj-labs/argocd-agent)

### Infrastructure
- **cert-manager**: [cert-manager.io/docs](https://cert-manager.io/docs/)
- **NGINX Ingress**: [NGINX Inc. Ingress Controller](https://docs.nginx.com/nginx-ingress-controller/) | [Helm Repo](https://helm.nginx.com/stable)
- **Kubernetes**: [kubernetes.io/docs](https://kubernetes.io/docs/home/)

### Terraform
- **Kubernetes Provider**: [registry.terraform.io/providers/hashicorp/kubernetes](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs)
- **Helm Provider**: [registry.terraform.io/providers/hashicorp/helm](https://registry.terraform.io/providers/hashicorp/helm/latest/docs)
- **Keycloak Provider**: [registry.terraform.io/providers/mrparkers/keycloak](https://registry.terraform.io/providers/mrparkers/keycloak/latest/docs)

### Community
- **ArgoCD Slack**: `#argo-cd` on [CNCF Slack](https://cloud-native.slack.com)
- **cert-manager Slack**: `#cert-manager` on [Kubernetes Slack](https://kubernetes.slack.com)
- **Grafana Community**: [community.grafana.com](https://community.grafana.com/)
