# NGINX Ingress Controller

Layer 7 load balancing and external traffic routing for Kubernetes clusters.

NGINX Ingress Controller provisions cloud LoadBalancers, routes HTTP/HTTPS traffic based on domain and path rules, and handles TLS termination for internet-facing applications.

**Official Documentation**: [kubernetes.github.io/ingress-nginx](https://kubernetes.github.io/ingress-nginx/) | **GitHub**: [kubernetes/ingress-nginx](https://github.com/kubernetes/ingress-nginx) | **Version**: `4.14.2`

---

## Features

- Cloud LoadBalancer provisioning with external IP assignment (GKE, EKS, AKS)
- Host-based routing (`app1.example.com`, `app2.example.com`)
- Path-based routing (`example.com/api`, `example.com/web`)
- TLS termination with cert-manager integration
- WebSocket support, rate limiting, DDoS protection

---

## Deployment Guides

Select a deployment method based on your requirements:

| Method | Guide | Use Case |
|--------|-------|----------|
| **Overview** | [Deployment Guide](../docs/ingress-controller-terraform-deployment.md) | Method comparison and decision guidance |
| **Automated** | [GitHub Actions Deployment](../docs/ingress-controller-github-actions.md) | Production environments, CI/CD pipelines |
| **Manual** | [Manual Helm Deployment](../docs/ingress-controller-manual-deployment.md) | Learning, local development, direct control |

For deployment method selection guidance, see the [Deployment Guide](../docs/ingress-controller-terraform-deployment.md).

---

## Operations

- [Adopting Existing Installation](../docs/adopting-ingress-controller.md) - Migrate existing NGINX Ingress deployment
- [Troubleshooting Guide](../docs/troubleshooting-ingress-controller.md) - LoadBalancer issues, DNS problems, routing failures

---

## Directory Structure

```
ingress-controller/
├── terraform/              # Terraform modules and configuration
│   ├── main.tf            # Main Terraform configuration
│   ├── variables.tf       # Input variables
│   ├── outputs.tf         # Output values (includes LoadBalancer IP)
│   └── terraform.tfvars.template  # Template for variables
└── README.md              # This file
```

---

## Quick Start

**Deployment Order:** Install ingress controller before cert-manager. cert-manager depends on the ingress controller for ACME HTTP-01 challenges.

### GitHub Actions Deployment

1. Configure GitHub Secrets ([configuration guide](../docs/ingress-controller-github-actions.md#step-1-configure-github-secrets))
2. Push to repository to trigger workflow
3. Verify deployment: `kubectl get svc -n ingress-nginx` (check for external IP)

### Manual Deployment

1. Follow the [Manual Deployment Guide](../docs/ingress-controller-manual-deployment.md)
2. Verify LoadBalancer: `kubectl get svc -n ingress-nginx nginx-monitoring-ingress-nginx-controller`

---

## Usage Examples

After deployment, create Ingress resources to route traffic to your services.

### Basic HTTP Routing

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp-ingress
spec:
  ingressClassName: nginx
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

### HTTPS with Automatic TLS

Configure automatic TLS certificate management with cert-manager:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp-ingress
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

Traffic to `myapp.example.com` routes to your service via the LoadBalancer with automatic HTTPS.

---

## DNS Configuration

After deployment:

1. **Get LoadBalancer IP:**
   ```bash
   kubectl get svc -n ingress-nginx nginx-monitoring-ingress-nginx-controller \
     -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
   ```

2. **Create DNS A records** pointing to the external IP in your DNS provider

3. **Wait for DNS propagation** (typically 5-60 minutes)

---

## Next Steps

After deploying the ingress controller:

1. Verify LoadBalancer has an external IP assigned
2. Configure DNS A records pointing to the LoadBalancer IP
3. Deploy cert-manager for automatic TLS certificates ([cert-manager Guide](../cert-manager/README.md))
4. Create Ingress resources to route traffic to your services

---

## Additional Resources

- [Troubleshooting Guide](../docs/troubleshooting-ingress-controller.md) - Debugging and issue resolution
- [Official Documentation](https://kubernetes.github.io/ingress-nginx/) - Comprehensive NGINX Ingress documentation
