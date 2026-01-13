# Kubernetes Observability & Operations

Infrastructure-as-code repository for deploying production-grade observability and operations platforms on Kubernetes.

## Platforms

### [Observability Stack (LGTM)](lgtm-stack/README.md)
Unified monitoring, logging, and tracing powered by Grafana, Loki, Tempo, and Mimir.

### [GitOps Delivery (ArgoCD)](argocd/README.md)
Declarative continuous delivery for cluster workloads and configurations.

### [Certificate Management (cert-manager)](cert-manager/README.md)
Automated TLS certificate provisioning and renewal via Let's Encrypt.

### [Ingress Controller (NGINX)](ingress-controller/README.md)
External traffic routing and load balancing for cluster services.

## Deployment

Each platform supports both automated (Terraform) and manual (Helm) deployment. See individual component READMEs for detailed instructions.
