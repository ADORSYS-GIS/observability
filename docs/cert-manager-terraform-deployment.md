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

4. **Configure `terraform.tfvars`**:
   Copy the provided template:
   ```bash
   cp terraform.tfvars.template terraform.tfvars
   ```
   Open `terraform.tfvars` and update the values to match your requirements (or existing installation).

   ```hcl
   install_cert_manager = true
   letsencrypt_email    = "admin@example.com"
   # release_name       = "cert-manager"
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
| `release_name` | Helm Release Name | `cert-manager` |
| `cert_manager_version` | Chart version | `v1.15.0` |
| `namespace` | Namespace to install into | `cert-manager` |
| `letsencrypt_email` | Email for ACME registration | **Required** |
| `cert_issuer_name` | Name of ClusterIssuer/Issuer | `letsencrypt-prod` |
| `cert_issuer_kind` | Kind of Issuer (`ClusterIssuer` or `Issuer`) | `ClusterIssuer` |
| `issuer_namespace` | Namespace for Issuer (if Kind is Issuer). Defaults to install namespace. | `null` |
| `ingress_class_name` | Ingress class for solving challenges | `nginx` |
| `issuer_server` | ACME server URL | `https://acme-v02...` |
