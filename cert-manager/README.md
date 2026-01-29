# cert-manager

Automated TLS certificate management for Kubernetes clusters.

cert-manager automates the complete certificate lifecycle: request, validation, issuance, renewal, and rotation of TLS certificates from Let's Encrypt and other certificate authorities.

**Official Documentation**: [cert-manager.io](https://cert-manager.io/docs/) | **GitHub**: [cert-manager/cert-manager](https://github.com/cert-manager/cert-manager) | **Version**: `v1.19.2`

---

## Features

- Automatic certificate provisioning from Let's Encrypt
- Auto-renewal before expiration (30-day window)
- Multi-cloud support (GKE, EKS, AKS, generic Kubernetes)
- HTTP-01 ACME challenge validation via NGINX Ingress Controller
- Automated Ingress TLS termination

---

## Deployment Guides

Select a deployment method based on your requirements:

| Method | Guide | Use Case |
|--------|-------|----------|
| **Overview** | [Deployment Guide](../docs/cert-manager-terraform-deployment.md) | Method comparison and decision guidance |
| **Automated** | [GitHub Actions Deployment](../docs/cert-manager-github-actions.md) | Production environments, CI/CD pipelines |
| **Manual** | [Manual Helm Deployment](../docs/cert-manager-manual-deployment.md) | Learning, local development, direct control |

For deployment method selection guidance, see the [Deployment Guide](../docs/cert-manager-terraform-deployment.md).

---

## Operations

- [Adopting Existing Installation](../docs/adopting-cert-manager.md) - Migrate existing cert-manager deployment
- [Troubleshooting Guide](../docs/troubleshooting-cert-manager.md) - Common issues and resolutions

---

## Directory Structure

```
cert-manager/
├── terraform/              # Terraform modules and configuration
│   ├── main.tf            # Main Terraform configuration
│   ├── variables.tf       # Input variables
│   ├── outputs.tf         # Output values
│   └── terraform.tfvars.template  # Template for variables
└── README.md              # This file
```

---

## Quick Start

**Prerequisites:** NGINX Ingress Controller must be deployed before cert-manager. See [Ingress Controller Deployment Guide](../ingress-controller/README.md).

### GitHub Actions Deployment

1. Configure GitHub Secrets ([configuration guide](../docs/cert-manager-github-actions.md#step-1-configure-github-secrets))
2. Push to repository to trigger workflow
3. Verify deployment: `kubectl get pods -n cert-manager`

### Manual Deployment

1. Follow the [Manual Deployment Guide](../docs/cert-manager-manual-deployment.md)
2. Verify ClusterIssuer: `kubectl get clusterissuer letsencrypt-prod`

---

## Usage Example

After deployment, configure automatic TLS for Ingress resources using the cert-manager annotation:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - myapp.example.com
      secretName: myapp-tls
  rules:
    - host: myapp.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: myapp-service
                port:
                  number: 80
```

cert-manager automatically provisions a valid Let's Encrypt certificate (typically within 2 minutes) and renews it every 60 days.

---

## Additional Resources

- [Troubleshooting Guide](../docs/troubleshooting-cert-manager.md) - Debugging and issue resolution
- [Official Documentation](https://cert-manager.io/docs/) - Comprehensive cert-manager documentation
