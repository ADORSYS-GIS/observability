# Modular ArgoCD Deployment with Keycloak OIDC & RBAC

This Terraform module deploys **ArgoCD** into a Kubernetes cluster using the official Helm chart. It is designed to be modular, supporting deployment to different clusters (Control Plane vs. Workload) with toggleable features for **Keycloak (OIDC) integration** and **RBAC (Role-Based Access Control)**.

---

##  Directory Structure

```text
.
├── modules/
│   └── argocd/               # Core Logic (Don't touch unless modifying the blueprint)
└── environments/
    └── control-plane/        # Deployment configuration for your specific cluster
        ├── main.tf
        ├── variables.tf      # Define your cluster context and secrets here
        ├── terraform.tfvars  # (Optional) Store non-sensitive values here
        └── providers.tf      # Configures connection to the specific K8s cluster