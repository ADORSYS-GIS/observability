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
| **Manual Helm** | [Manual Deployment](../docs/cert-manager-manual-deployment.md) | Learning, local development, direct control |
| **Terraform CLI** | [Terraform Deployment](../docs/cert-manager-terraform-deployment.md) | Infrastructure as Code, reproducible deployments |
| **GitHub Actions** | [Automated CI/CD](../docs/cert-manager-github-actions.md) | Production environments, team workflows |

**Choosing a Method:**
- **Manual Helm**: Best for learning, quick setups, local development
- **Terraform CLI**: Best for infrastructure as code workflows, version control, multi-environment deployments
- **GitHub Actions**: Best for production, automated deployments, team collaboration with PR-based reviews

---

## Operations

- [Adopting Existing Installation](../docs/adopting-cert-manager.md) - Migrate existing cert-manager deployment
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

- [Troubleshooting Guide](../docs/troubleshooting-cert-manager.md) - Debugging and issue resolution
- [Official Documentation](https://cert-manager.io/docs/) - Comprehensive cert-manager documentation
