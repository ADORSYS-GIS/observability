# cert-manager

Automated TLS certificate management for Kubernetes clusters.

cert-manager automates the complete certificate lifecycle: request, validation, issuance, renewal, and rotation of TLS certificates from Let's Encrypt and other certificate authorities.

**Official Documentation**: [cert-manager.io](https://cert-manager.io/docs/) | **GitHub**: [cert-manager/cert-manager](https://github.com/cert-manager/cert-manager) | **Version**: `v1.19.2`

---

## Features

- **Automated Provisioning**: Let's Encrypt certificate issuance and renewal
- **Multi-Cloud Ready**: Deploy on GKE, EKS, AKS, or any Kubernetes cluster
- **HTTP-01 Validation**: ACME challenge validation via NGINX Ingress Controller
- **Lifecycle Management**: Automatic renewal before expiration with 30-day window

---

## Deployment Options

Choose your preferred deployment approach:

| Method | Guide | Description |
|--------|-------|-------------|
| **Manual Helm** | [Manual Deployment](../docs/cert-manager-manual-deployment.md) | Direct command-line deployment with step-by-step control |
| **Terraform CLI** | [Terraform Deployment](../docs/cert-manager-terraform-deployment.md) | Infrastructure-as-code with version control and remote state |
| **GitHub Actions** | [Automated CI/CD](../docs/cert-manager-github-actions.md) | Fully automated deployment pipelines with PR-based workflows |

All methods deploy identical cert-manager configurations with Let's Encrypt ClusterIssuer integration.

---

## Operations

- [Adopting Existing Installation](../docs/adopting-cert-manager.md) - Migrate existing cert-manager deployment
  - **New**: Automated import via GitHub Actions checkbox (see [GitHub Actions guide](../docs/cert-manager-github-actions.md#adopting-existing-cert-manager-installation))
- [Troubleshooting Guide](../docs/troubleshooting-cert-manager.md) - Common issues and resolutions

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

- [Official Documentation](https://cert-manager.io/docs/) - Comprehensive cert-manager documentation
