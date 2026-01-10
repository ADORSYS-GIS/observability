# ArgoCD Deployment

This directory contains infrastructure-as-code and configuration for deploying **ArgoCD** to enable GitOps-based continuous delivery for the platform.

ArgoCD provides:
*   **Declarative GitOps**: Synchronizing cluster state with Git repositories.
*   **Continuous Deployment**: Automated application updates and rollbacks.
*   **Drift Detection**: Alerting on manual changes to the cluster configuration.

## Deployment Options

### Automated Deployment
This component is deployed using Terraform. The configuration is located in the `terraform/` directory.

#### Prerequisites
*   Terraform >= 1.0
*   Kubernetes Cluster (GKE)
*   kubectl configured

#### Quick Start
1.  Navigate to the directory:
    ```bash
    cd terraform
    ```
2.  Initialize Terraform:
    ```bash
    terraform init
    ```
3.  Configure Variables:
    Copy the template and adjust values:
    ```bash
    cp terraform.tfvars.template terraform.tfvars
    ```
4.  Apply configuration:
    ```bash
    terraform apply
    ```

## Troubleshooting

### Common Issues

**ArgoCD Server Pod CrashLoopBackOff**
```bash
# Check logs for permission/resource errors
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server
```

**Login Failure**
```bash
# Retrieve initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

**"Unknown" Application Status**
```bash
# Verify repo accessibility
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server

# Fix: Check network policies allowing Git access
```
