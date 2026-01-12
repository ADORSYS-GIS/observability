# Kubernetes Observability & Operations Platform

This repository provisions a comprehensive, production-grade observability and operations platform on **Google Kubernetes Engine (GKE)**. It integrates distinct, modular components to handle **deployment**, **monitoring**, **logging**, **tracing**, and **certificate management**.

## Core Components

*   **Observability (LGTM Stack)**:
    *   **Loki**: Distributed logging.
    *   **Grafana**: Visualization and dashboards.
    *   **Tempo**: Distributed tracing.
    *   **Mimir**: Scalable metrics (Prometheus storage).
*   **GitOps (ArgoCD)**:
    *   **ArgoCD**: Continuous delivery and declarative GitOps workflows.
*   **Infrastructure Essentials**:
    *   **Cert-Manager**: Automated TLS certificate issuance (Let's Encrypt).
    *   **Ingress Controller**: NGINX Ingress for external traffic management.

## Project Structure

This project is built with **Terraform** and **Helm**, designed for modularity. You can deploy the entire stack or individual components as needed.

*   **[`lgtm-stack/`](lgtm-stack/README.md)**: The core internal monitoring platform.
*   **[`argocd/`](argocd/README.md)**: The GitOps delivery engine.
*   **[`cert-manager/`](cert-manager/README.md)**: Certificate management infrastructure.
*   **[`ingress-controller/`](ingress-controller/README.md)**: Ingress routing infrastructure.

## Documentation

*   **[Kubernetes Observability Guide](docs/kubernetes-observability.md)**: Deployment and architecture of the LGTM stack.
*   **[Cert-Manager Deployment](docs/cert-manager-terraform-deployment.md)**: Terraform guide for Cert-Manager.
*   **[Ingress Controller Deployment](docs/ingress-controller-terraform-deployment.md)**: Terraform guide for NGINX Ingress.
*   **[ArgoCD Documentation](argocd/README.md)**: Setup and configuration for GitOps.

