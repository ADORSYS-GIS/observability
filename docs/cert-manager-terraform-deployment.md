# Cert-Manager Deployment (Terraform)

This guide explains how to deploy **Cert-Manager** using the standalone Terraform configuration.

## Prerequisites

- **Terraform** >= 1.0
- **Kubernetes Cluster** (GKE, etc.)
- **kubectl** configured to context

## Deployment Steps

Make sure you've cloned the repository before running Terraform.

```bash
git clone https://github.com/Adorsys-gis/observability.git
cd observability
```

1. **Verify Context** :
   Ensure you are pointing to the correct cluster before running Terraform.
   ```bash
   kubectl config current-context
   ```

2. **Navigate to the directory**:
   From the project root:
   ```bash
   cd cert-manager/terraform
   ```

3. **Initialize Terraform**:
   ```bash
   terraform init
   ```

4. **Create a `terraform.tfvars` file**:
   Create a file named `terraform.tfvars` with your specific configuration:
   ```hcl
   letsencrypt_email = "your-email@example.com"
   cert_issuer_name  = "letsencrypt-prod"
   install_cert_manager = true  # Must be set to true explicitly
   
   # Optional:
   # cert_issuer_kind = "ClusterIssuer" # or "Issuer"
   # namespace = "cert-manager"
   ```

5. **Review the Plan**:
   ```bash
   terraform plan
   ```

6. **Apply**:
   ```bash
   terraform apply
   ```

## Variables

| Name | Description | Default |
|------|-------------|---------|
| `install_cert_manager` | Install Cert-Manager via Helm | `false` |
| `cert_manager_version` | Chart version | `v1.15.0` |
| `namespace` | Namespace to install into | `cert-manager` |
| `letsencrypt_email` | Email for ACME registration | **Required** |
| `cert_issuer_name` | Name of ClusterIssuer/Issuer | `letsencrypt-prod` |
| `cert_issuer_kind` | Kind of Issuer (`ClusterIssuer` or `Issuer`) | `ClusterIssuer` |
| `issuer_namespace` | Namespace for Issuer (if Kind is Issuer). Defaults to install namespace. | `null` |
| `ingress_class_name` | Ingress class for solving challenges | `nginx` |
| `issuer_server` | ACME server URL | `https://acme-v02...` |
