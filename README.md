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

## REPO STRUCTURE

```
observability/
├── README.md
│   └── USE: Project overview, quick start, and entry point for new users
│
├── argocd/
│   ├── README.md
│   │   └── USE: ArgoCD component overview and quick reference
│   └── terraform/
│       ├── locals.tf
│       │   └── USE: Local variables and computed values within ArgoCD module
│       ├── main.tf
│       │   └── USE: Deploy ArgoCD using Helm to GKE cluster
│       ├── outputs.tf
│       │   └── USE: Export ArgoCD endpoint URLs and credentials
│       ├── variables.tf
│       │   └── USE: Define input parameters for ArgoCD deployment
│       └── values/
│           ├── argocd-values.yaml
│           │   └── USE: Base Helm chart values for ArgoCD
│           ├── argocd-dev-values.yaml
│           │   └── USE: Development environment overrides (reduced resources)
│           └── argocd-prod-values.yaml
│               └── USE: Production environment overrides (HA, replicas)
│
├── cert-manager/
│   ├── README.md
│   │   └── USE: Cert-Manager component overview and reference
│   └── terraform/
│       ├── locals.tf
│       │   └── USE: Local variables and computed values
│       ├── main.tf
│       │   └── USE: Deploy Cert-Manager using Helm to manage TLS certificates
│       ├── outputs.tf
│       │   └── USE: Export Cert-Manager service account and configuration details
│       ├── variables.tf
│       │   └── USE: Define customizable parameters for Cert-Manager
│
├── docs/
│   ├── ARCHITECTURE.md
│   │   └── USE: Explain system design, component interactions, and data flow
│   ├── GETTING_STARTED.md
│   │   └── USE: Step-by-step quick start guide for new users
│   ├── README.md
│   │   └── USE: Documentation index and navigation hub
│   ├── TUTORIAL_ARGOCD.md
│   │   └── USE: Manual ArgoCD installation guide (alternative to Terraform)
│   ├── TUTORIAL_CERT_MANAGER.md
│   │   └── USE: Manual Cert-Manager installation guide
│   ├── TUTORIAL_GKE_SETUP.md
│   │   └── USE: Manual GKE cluster creation using gcloud CLI
│   ├── TUTORIAL_INGRESS.md
│   │   └── USE: Manual Ingress Controller installation guide
│   ├── TUTORIAL_LGTM.md
│   │   └── USE: Manual LGTM stack deployment guide
│   └── images/
│       ├── architecture-diagram.png
│       │   └── USE: Visual system architecture diagram
│       ├── argocd-workflow.png
│       │   └── USE: Visual GitOps deployment workflow diagram
│       └── lgtm-flow.png
│           └── USE: Visual LGTM component data flow diagram
│
├── ingress-controller/
│   ├── README.md
│   │   └── USE: Ingress Controller component overview
│   └── terraform/
│       ├── locals.tf
│       │   └── USE: Local variables for ingress module
│       ├── main.tf
│       │   └── USE: Deploy Nginx Ingress Controller for HTTP/HTTPS routing
│       ├── outputs.tf
│       │   └── USE: Export load balancer endpoint and service information
│       ├── variables.tf
│       │   └── USE: Define customizable parameters for Ingress
│       └── values.yaml
│           └── USE: Helm chart configuration for Nginx Ingress Controller
│
└── lgtm-stack/
    ├── README.md
    │   └── USE: LGTM stack component overview and architecture
    └── terraform/
        ├── locals.tf
        │   └── USE: Local variables for LGTM module
        ├── main.tf
        │   └── USE: Deploy all LGTM components (Prometheus, Loki, Mimir, Tempo, Grafana)
        ├── outputs.tf
        │   └── USE: Export endpoints and credentials for all LGTM components
        ├── variables.tf
        │   └── USE: Define customizable parameters for LGTM deployment
        └── values/
            ├── grafana-values.yaml
            │   └── USE: Helm configuration for Grafana dashboards and datasources
            ├── loki-values.yaml
            │   └── USE: Helm configuration for Loki log storage and retention
            ├── mimir-values.yaml
            │   └── USE: Helm configuration for Mimir long-term metrics storage
            ├── prometheus-values.yaml
            │   └── USE: Helm configuration for Prometheus metrics scraping
            └── tempo-values.yaml
                └── USE: Helm configuration for Tempo distributed tracing
```
