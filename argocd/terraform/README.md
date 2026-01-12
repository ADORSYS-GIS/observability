# Modular ArgoCD Deployment with Keycloak OIDC & RBAC

This Terraform module deploys **ArgoCD** into a Kubernetes cluster using the official Helm chart. It is designed to be modular, supporting deployment to different clusters (Control Plane vs. Workload) with toggleable features for **Keycloak (OIDC) integration** and **RBAC (Role-Based Access Control)**.

---

##  Directory Structure

```text
.
├── main.tf
├── provider.tf
├── README.md
├── terraform.tfvars # Create this file to include you variables as in the terraform.tfvars.template file
└── variables.tf