# Cert-Manager Deployment

This directory contains infrastructure-as-code and configuration for deploying **Cert-Manager** to automate the management and issuance of TLS certificates for the Kubernetes cluster.

Cert-Manager provides:
*   **Automated Issuance**: Obtaining certificates from Let's Encrypt and other issuers.
*   **Renewal**: Automatically renewing certificates before expiry.
*   **Integration**: Working seamlessly with Ingress resources to secure external access for any application.

## Deployment Options

### 1. Automated Deployment
This method uses the Terraform configuration located in the `terraform/` directory. It is the recommended approach for automation.

For detailed instructions, see the [Terraform deployment guide](../docs/cert-manager-terraform-deployment.md).

### 2. Manual (Helm & Kubectl)
If you prefer to deploy manually using CLI tools, you can follow the [manual deployment guide](../docs/cert-manager-manual-deployment.md).

## Troubleshooting

### Deployment Flags
Ensure variables are set correctly in `terraform.tfvars`:
```hcl
install_cert_manager = true
```

### Common Issues

**Webhook Pod Not Ready**
```bash
# Check pod status (look for CrashLoopBackOff)
kubectl get pods -n cert-manager

# Fix: Ensure installCRDs=true is set in Helm release
```

**Certificate Stuck in "False" State**
```bash
# Check certificate events for challenge failures
kubectl describe certificate <name> -n <namespace>
```

**Issuer Not Ready**
```bash
# Check issuer status and ACME server URL
kubectl describe clusterissuer letsencrypt-prod
```
