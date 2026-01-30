# NGINX Ingress Controller

Layer 7 load balancing and external traffic routing for Kubernetes clusters.

NGINX Ingress Controller provisions cloud LoadBalancers, routes HTTP/HTTPS traffic based on domain and path rules, and handles TLS termination for internet-facing applications.

**Official Documentation**: [NGINX Inc. Ingress Controller](https://docs.nginx.com/nginx-ingress-controller/) | **GitHub**: [nginxinc/kubernetes-ingress](https://github.com/nginxinc/kubernetes-ingress) | **Helm Repository**: `https://helm.nginx.com/stable` | **Version**: `2.4.2`

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
| **Manual Helm** | [Manual Deployment](../docs/ingress-controller-manual-deployment.md) | Learning, local development, direct control |
| **Terraform CLI** | [Terraform Deployment](../docs/ingress-controller-terraform-deployment.md) | Infrastructure as Code, reproducible deployments |
| **GitHub Actions** | [Automated CI/CD](../docs/ingress-controller-github-actions.md) | Production environments, team workflows |

**Choosing a Method:**
- **Manual Helm**: Best for learning, quick setups, local development
- **Terraform CLI**: Best for infrastructure as code workflows, version control, multi-environment deployments
- **GitHub Actions**: Best for production, automated deployments, team collaboration with PR-based reviews

---

## Operations

- [Adopting Existing Installation](../docs/adopting-ingress-controller.md) - Migrate existing NGINX Ingress deployment
- [Troubleshooting Guide](../docs/troubleshooting-ingress-controller.md) - LoadBalancer issues, DNS problems, routing failures

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

## Additional Resources

- [Official Documentation](https://docs.nginx.com/nginx-ingress-controller/) - Comprehensive NGINX Inc. Ingress Controller documentation
- [Helm Repository](https://helm.nginx.com/stable) - NGINX Inc. stable Helm charts
