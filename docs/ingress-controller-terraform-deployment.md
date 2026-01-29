# NGINX Ingress Controller Deployment Guide

Layer 7 load balancing and HTTP/HTTPS traffic routing for Kubernetes services.

**Official Documentation**: [kubernetes.github.io/ingress-nginx](https://kubernetes.github.io/ingress-nginx/) | **GitHub**: [kubernetes/ingress-nginx](https://github.com/kubernetes/ingress-nginx) | **Version**: `4.14.2`

---

## Deployment Methods

This guide covers two deployment approaches for NGINX Ingress Controller:

### Method 1: GitHub Actions (Automated CI/CD)

Recommended for production environments and teams using infrastructure as code workflows.

**Features:**
- Automated Terraform backend configuration (GCS/S3/Azure Blob)
- Cloud provider authentication via GitHub Secrets
- LoadBalancer provisioning with external IP assignment
- Pull request-based plan review
- Automated state management
- Zero-downtime upgrades

**Supported platforms:** GKE, EKS, AKS

**Guide:** [GitHub Actions Deployment](ingress-controller-github-actions.md)

---

### Method 2: Manual Helm Deployment

Recommended for local development, learning environments, or clusters without CI/CD infrastructure.

**Features:**
- Direct command-line control
- Helm chart-based installation
- Step-by-step LoadBalancer verification
- Works with any Kubernetes cluster

**Supported platforms:** Any Kubernetes cluster with LoadBalancer support (≥ 1.24)

**Guide:** [Manual Deployment](ingress-controller-manual-deployment.md)

---

## Choosing a Deployment Method

Consider the following when selecting a deployment approach:

**Use GitHub Actions if:**
- Deploying to production environments
- Managing multi-cloud infrastructure
- Requiring audit trails and version control
- Working in team environments

**Use Manual Deployment if:**
- Running local development clusters (Minikube, Kind, etc.)
- Learning ingress controller functionality
- Operating without CI/CD infrastructure
- Requiring immediate, hands-on control

**Note:** Kind clusters require additional LoadBalancer setup (e.g., MetalLB) for full functionality.

---

## Prerequisites

### Common Requirements (Both Methods)

| Component | Requirement |
|-----------|-------------|
| Kubernetes cluster | Version ≥ 1.24 (GKE, EKS, AKS, or generic) |
| LoadBalancer support | Cloud provider native or MetalLB for on-premise |
| kubectl | For cluster access and verification |

### Additional Requirements by Method

| Component | GitHub Actions | Manual Deployment |
|-----------|----------------|-------------------|
| Helm | Not required | Version ≥ 3.12 |
| Cloud credentials | GitHub Secrets | Local authentication |
| Terraform | Not required locally | Not required |

**Note:** Deploy ingress controller before cert-manager. cert-manager depends on the ingress controller for HTTP-01 ACME challenge validation.

Cloud providers (GKE, EKS, AKS) automatically provision LoadBalancers with external IP addresses. For on-premise or local clusters, configure [MetalLB](https://metallb.universe.tf/) or similar LoadBalancer implementation.

---

## How NGINX Ingress Controller Works

The ingress controller performs the following functions:

1. **LoadBalancer Provisioning:** Creates cloud LoadBalancer with external IP address
2. **Ingress Resource Monitoring:** Watches for Ingress resource changes
3. **Traffic Routing:** Routes HTTP/HTTPS traffic based on host and path rules
4. **TLS Termination:** Handles SSL/TLS certificate termination
5. **Health Monitoring:** Performs readiness and liveness checks

### Example Usage

#### Basic HTTP Routing

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: example-ingress
spec:
  ingressClassName: nginx
  rules:
    - host: app.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: app-service
                port:
                  number: 80
```

#### With TLS (requires cert-manager)

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: example-ingress
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - app.example.com
      secretName: app-tls
  rules:
    - host: app.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: app-service
                port:
                  number: 80
```

---

## DNS Configuration

After deployment, configure DNS records to point to the LoadBalancer external IP.

### Get LoadBalancer IP

```bash
kubectl get svc -n ingress-nginx nginx-monitoring-ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

### Configure DNS Records

Create A records in your DNS provider:
- `example.com` → `<EXTERNAL-IP>`
- `*.example.com` → `<EXTERNAL-IP>` (for wildcard subdomain support)

DNS propagation typically takes 5-60 minutes depending on TTL settings and provider.

---

## Upgrading

### GitHub Actions Deployments

1. Update `nginx_ingress_version` in `terraform/terraform.tfvars`
2. Commit and push changes to trigger workflow
3. Review Terraform plan in pull request
4. Merge to apply changes

### Manual Deployments

Update chart version in Helm upgrade command:

```bash
helm upgrade nginx-monitoring ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --version <new-version> \
  --reuse-values
```

All upgrades are performed with zero downtime. The LoadBalancer IP address persists across upgrades, eliminating DNS reconfiguration requirements.

---

## Uninstalling

**Warning:** Uninstalling the ingress controller removes the LoadBalancer and terminates all external traffic routing. All Ingress resources will become non-functional.

### GitHub Actions

Use the destroy workflow:
```bash
.github/workflows/destroy-ingress-controller.yaml
```

### Manual Helm

```bash
helm uninstall nginx-monitoring -n ingress-nginx
kubectl delete namespace ingress-nginx
```

---

## Additional Documentation

- [Troubleshooting Guide](troubleshooting-ingress-controller.md) - LoadBalancer issues, DNS configuration, routing problems
- [Adoption Guide](adopting-ingress-controller.md) - Migrating existing NGINX Ingress installations
- [cert-manager Deployment](cert-manager-terraform-deployment.md) - TLS certificate management (deploy after ingress)
- [NGINX Ingress Official Documentation](https://kubernetes.github.io/ingress-nginx/) - Comprehensive upstream documentation

---

## Next Steps

After deploying the ingress controller:

1. Verify LoadBalancer has assigned external IP
2. Configure DNS A records pointing to external IP
3. Deploy cert-manager for automatic TLS certificate management
4. Create Ingress resources to route traffic to services

---

## Deployment Guides

Select your deployment method and follow the corresponding guide:

- [GitHub Actions Deployment](ingress-controller-github-actions.md) - Automated CI/CD approach
- [Manual Helm Deployment](ingress-controller-manual-deployment.md) - Direct installation approach

Both methods result in a production-ready NGINX Ingress Controller installation. Choose based on your operational requirements and infrastructure setup.
