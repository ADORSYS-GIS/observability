# Cert-Manager Component

This directory contains the necessary configurations for **Cert-Manager**, which handles certificate management and issuance for the observability stack.

## Deployment Options

You can deploy Cert-Manager using one of the following methods:

### 1. Automated Deployment
This method uses the Terraform configuration located in the `terraform/` directory. It is the recommended approach for automation.

For detailed instructions, see the [Terraform deployment guide](../docs/cert-manager-terraform-deployment.md).

### 2. Manual (Helm & Kubectl)
If you prefer to deploy manually using CLI tools, you can follow the [manual deployment guide](../docs/cert-manager-manual-deployment.md).
