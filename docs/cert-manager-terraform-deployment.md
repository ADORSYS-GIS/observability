# cert-manager Deployment Guide

Automated TLS certificate management for Kubernetes clusters with ACME provider support.

**Official Documentation**: [cert-manager.io](https://cert-manager.io/docs/) | **GitHub**: [cert-manager/cert-manager](https://github.com/cert-manager/cert-manager) | **Version**: `v1.19.2`

---

## Deployment Methods

This guide covers two deployment approaches for cert-manager:

### Method 1: GitHub Actions (Automated CI/CD)

Recommended for production environments and teams using infrastructure as code workflows.

**Features:**
- Automated Terraform backend configuration (GCS/S3/Azure Blob)
- Cloud provider authentication via GitHub Secrets
- Pull request-based plan review
- Automated state management
- Zero-downtime upgrades

**Supported platforms:** GKE, EKS, AKS

**Guide:** [GitHub Actions Deployment](cert-manager-github-actions.md)

---

### Method 2: Manual Helm Deployment

Recommended for local development, learning environments, or clusters without CI/CD infrastructure.

**Features:**
- Direct command-line control
- Helm chart-based installation
- Step-by-step verification
- Works with any Kubernetes cluster

**Supported platforms:** Any Kubernetes cluster (≥ 1.24)

**Guide:** [Manual Deployment](cert-manager-manual-deployment.md)

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
- Learning cert-manager functionality
- Operating without CI/CD infrastructure
- Requiring immediate, hands-on control

---

## Prerequisites

### Common Requirements (Both Methods)

| Component | Requirement |
|-----------|-------------|
| Kubernetes cluster | Version ≥ 1.24 (GKE, EKS, AKS, or generic) |
| NGINX Ingress Controller | Must be deployed first |
| kubectl | For cluster access and verification |
| Let's Encrypt email | Valid email address for certificate notifications |

### Additional Requirements by Method

| Component | GitHub Actions | Manual Deployment |
|-----------|----------------|-------------------|
| Helm | Not required | Version ≥ 3.12 |
| Cloud credentials | GitHub Secrets | Local authentication |
| Terraform | Not required locally | Not required |

**Note:** NGINX Ingress Controller must be deployed before cert-manager. cert-manager uses HTTP-01 ACME challenges for domain validation, which requires an active ingress controller.

See: [Ingress Controller Deployment Guide](ingress-controller-terraform-deployment.md)

---

## How cert-manager Works

cert-manager automates the following certificate lifecycle operations:

1. **Certificate Requests:** Initiates certificate requests to ACME providers (Let's Encrypt)
2. **Domain Validation:** Completes HTTP-01 challenges via ingress controller
3. **Certificate Storage:** Stores issued certificates as Kubernetes Secrets
4. **Automatic Renewal:** Renews certificates 30 days before expiration
5. **Ingress Integration:** Automatically updates Ingress resources with valid certificates

### Example Usage

Once deployed, cert-manager automatically provisions and manages TLS certificates for Ingress resources:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: example-app
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - app.example.com
      secretName: app-tls  # cert-manager manages this Secret
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

Certificates are typically issued within 2-3 minutes and automatically renewed every 60 days.

---

## Upgrading

### GitHub Actions Deployments

1. Update `cert_manager_version` in `terraform/terraform.tfvars`
2. Commit and push changes to trigger workflow
3. Review Terraform plan in pull request
4. Merge to apply changes

### Manual Deployments

1. Update chart version in Helm upgrade command:

```bash
helm upgrade cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --version <new-version> \
  --reuse-values
```

All upgrades are performed with zero downtime. Existing certificates remain valid during the upgrade process.

---

## Uninstalling

**Warning:** Uninstalling cert-manager removes all managed Certificate resources and Custom Resource Definitions. Ensure you have backups of any required certificates.

### GitHub Actions

Use the destroy workflow:
```bash
.github/workflows/destroy-cert-manager.yaml
```

### Manual Helm

```bash
helm uninstall cert-manager -n cert-manager
kubectl delete namespace cert-manager
```

---

## Additional Documentation

- [Troubleshooting Guide](troubleshooting-cert-manager.md) - Common issues and resolutions
- [Adoption Guide](adopting-cert-manager.md) - Migrating existing cert-manager installations
- [cert-manager Official Documentation](https://cert-manager.io/docs/) - Comprehensive upstream documentation

---

## Next Steps

Select your deployment method and follow the corresponding guide:

- [GitHub Actions Deployment](cert-manager-github-actions.md) - Automated CI/CD approach
- [Manual Helm Deployment](cert-manager-manual-deployment.md) - Direct installation approach

Both methods result in a production-ready cert-manager installation. Choose based on your operational requirements and infrastructure setup.
