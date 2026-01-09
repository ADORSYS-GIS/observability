# NGINX Ingress Controller Deployment (Terraform)

This guide explains how to deploy the **NGINX Ingress Controller** using the standalone Terraform configuration.

## Prerequisites

- **Terraform** >= 1.0
- **Kubernetes Cluster**
- **kubectl** configured

## Deployment Steps

Make sure you've cloned the repository before running Terraform.

```bash
git clone https://github.com/Adorsys-gis/observability.git
cd observability
```

1. **Verify Context**:
   Ensure you are pointing to the correct cluster.
   ```bash
   kubectl config current-context
   ```

2. **Navigate to the directory**:
   From the project root:
   ```bash
   cd ingress-controller/terraform
   ```

3. **Initialize Terraform**:
   ```bash
   terraform init
   ```

4. **Create a `terraform.tfvars` file**:
   ```hcl
   ingress_class_name = "nginx"
   install_nginx_ingress = true # Must be set to true explicitly
   
   # Optional
   # replica_count = 2
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
| `install_nginx_ingress` | Install NGINX Ingress | `false` |
| `nginx_ingress_version` | Chart version | `4.10.1` |
| `namespace` | Namespace to install into | `ingress-nginx` |
| `ingress_class_name` | Ingress Class Name | `nginx` |
| `replica_count` | Controller Replicas | `1` |
