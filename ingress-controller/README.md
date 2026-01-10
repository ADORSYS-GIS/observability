# NGINX Ingress Deployment

This directory contains infrastructure-as-code and configuration for deploying the **NGINX Ingress Controller** to manage external access for services running on the cluster.

The Ingress Controller provides:
*   **Load Balancing**: Routing external traffic to internal Kubernetes services.
*   **SSL Termination**: Handling HTTPS connections (integrated with Cert-Manager).
*   **Path-based Routing**: Directing traffic to applications based on hostnames or paths.

## Deployment Options

### 1. Automated Deployment
This method uses the Terraform configuration located in the `terraform/` directory.

For detailed instructions, see the [Terraform deployment guide](../docs/ingress-controller-terraform-deployment.md).

### 2. Manual (Helm)
If you prefer to deploy manually using Helm, you can follow the [manual deployment guide](../docs/ingress-controller-manual-deployment.md).

## Troubleshooting

### Deployment Flags
Ensure variables are set correctly in `terraform.tfvars`:
```hcl
install_nginx_ingress = true
```

### Common Issues

**LoadBalancer External IP Pending**
```bash
# Check service status for EXTERNAL-IP
kubectl get svc -n ingress-nginx

# Fix: Verify GCP LoadBalancer quota or cloud-controller logs
```

**404 Not Found**
```bash
# Verify Ingress resource points to valid Service/Port
kubectl describe ingress <name> -n <namespace>

# Fix: Ensure Ingress Class is set to 'nginx'
```

**SSL Certificate Issues**
```bash
# Check secret name in TLS section matches Cert-Manager secret
kubectl describe ingress <name> -n <namespace>
```
