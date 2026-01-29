# Cert-Manager Terraform Deployment

Automated TLS certificate management deployment using Terraform and Helm with multi-cloud support.

**Official Documentation**: [cert-manager.io/docs](https://cert-manager.io/docs/)  
**GitHub Repository**: [cert-manager/cert-manager](https://github.com/cert-manager/cert-manager)

## Overview

This deployment configures cert-manager with:

- **Multi-Cloud Support**: GKE, EKS, AKS, and generic Kubernetes clusters
- **Automated Certificate Issuance**: Let's Encrypt integration via ACME protocol
- **Automatic Renewal**: Certificates renewed before expiration
- **ClusterIssuer Configuration**: Cluster-wide certificate authority for all namespaces
- **HTTP-01 Challenge Solver**: Ingress-based domain validation
- **CRD Management**: Custom Resource Definitions for certificate lifecycle
- **CI/CD Ready**: GitHub Actions workflows for automated deployments

## Prerequisites

| Requirement | Version | Purpose |
|-------------|---------|---------|
| **Terraform** | ≥ 1.5.0 | Infrastructure provisioning |
| **kubectl** | ≥ 1.24 | Kubernetes cluster access |
| **Kubernetes Cluster** | ≥ 1.24 | Target platform (GKE, EKS, AKS, or generic) |

### Supported Cloud Providers

| Provider | Authentication | Backend Storage |
|----------|---------------|-----------------|
| **GKE** | `gcloud` CLI + service account | Google Cloud Storage |
| **EKS** | `aws` CLI + IAM role | S3 |
| **AKS** | `az` CLI + service principal | Azure Blob Storage |
| **Generic** | `kubectl` config | Kubernetes Secret |

### Required Infrastructure

- **Ingress Controller**: NGINX Ingress Controller for HTTP-01 challenges
- **Public DNS**: Domain names must resolve publicly for Let's Encrypt validation

> **Don't have Ingress Controller?** See [Ingress Controller Setup](ingress-controller-terraform-deployment.md)

## Installation

> **Existing Installation?** If you already have cert-manager deployed and want to manage it with Terraform, see the [Adoption Guide](adopting-cert-manager.md) before proceeding.

### Deployment Methods

Choose between **manual deployment** (command-line) or **automated deployment** (GitHub Actions):

#### Option A: Automated Deployment (Recommended for CI/CD)

GitHub Actions workflows provide automated, multi-cloud deployment capabilities:

**Available Workflows:**
- `.github/workflows/deploy-cert-manager-gke.yaml` - Google Kubernetes Engine
- `.github/workflows/deploy-cert-manager-eks.yaml` - Amazon Elastic Kubernetes Service
- `.github/workflows/deploy-cert-manager-aks.yaml` - Azure Kubernetes Service
- `.github/workflows/destroy-cert-manager.yaml` - Destroy cert-manager resources

**Workflow Features:**
- Terraform plan with detailed output and PR comments
- Multi-cloud backend configuration (GCS, S3, Azure Blob)
- Automatic cluster authentication
- Zero-downtime upgrades
- Rollback capability

**Usage:**
1. Configure GitHub repository secrets (see workflow files for required secrets)
2. Push changes to trigger deployment workflow
3. Review Terraform plan in PR comments
4. Merge to apply changes

See individual workflow files for detailed configuration and required secrets.

#### Option B: Manual Deployment

Follow the steps below for command-line deployment:

### Step 1: Clone Repository

```bash
git clone https://github.com/Adorsys-gis/observability.git
cd observability/cert-manager/terraform
```

### Step 2: Verify Kubernetes Context

```bash
kubectl config current-context
```

Ensure you're pointing to the correct cluster.

### Step 3: Configure Variables

```bash
cp terraform.tfvars.template terraform.tfvars
```

Edit `terraform.tfvars` with your environment values:

```hcl
# Cloud Provider Configuration
cloud_provider = "gke"  # Options: gke, eks, aks, generic

# GKE-specific (required only for GKE)
project_id           = "your-gcp-project"
region               = "us-central1"
gke_endpoint         = ""  # Auto-populated by workflow
gke_ca_certificate   = ""  # Auto-populated by workflow

# EKS-specific (required only for EKS)
# aws_region = "us-east-1"

# Enable cert-manager installation
install_cert_manager = true

# Let's Encrypt Configuration
letsencrypt_email = "admin@example.com"

# Certificate Issuer
cert_issuer_name = "letsencrypt-prod"
cert_issuer_kind = "ClusterIssuer"

# Deployment Configuration
cert_manager_version = "v1.19.2"
namespace            = "cert-manager"
release_name         = "cert-manager"

# Challenge Solver
ingress_class_name = "nginx"

# Optional: Use staging for testing
# issuer_server = "https://acme-staging-v02.api.letsencrypt.org/directory"
```

### Complete Variable Reference

For all available variables, see [variables.tf](../cert-manager/terraform/variables.tf).

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `cloud_provider` | Cloud platform (gke, eks, aks, generic) | `gke` | ✓ |
| `project_id` | GCP Project ID (GKE only) | `""` | GKE |
| `region` | GCP Region (GKE only) | `us-central1` | GKE |
| `aws_region` | AWS Region (EKS only) | `us-east-1` | EKS |
| `gke_endpoint` | GKE cluster endpoint | `""` | GKE |
| `gke_ca_certificate` | GKE cluster CA certificate | `""` | GKE |
| `install_cert_manager` | Enable cert-manager installation | `false` | |
| `letsencrypt_email` | Email for Let's Encrypt notifications | - | ✓ |
| `cert_manager_version` | Helm chart version | `v1.19.2` | |
| `namespace` | Kubernetes namespace | `cert-manager` | |
| `release_name` | Helm release name | `cert-manager` | |
| `cert_issuer_name` | Issuer resource name | `letsencrypt-prod` | |
| `cert_issuer_kind` | Issuer type | `ClusterIssuer` | |
| `issuer_namespace` | Namespace for Issuer (if not ClusterIssuer) | `""` | |
| `issuer_server` | ACME server URL | Let's Encrypt Production | |
| `ingress_class_name` | Ingress class for HTTP-01 challenges | `nginx` | |

### ACME Server URLs

| Environment | URL | Rate Limits |
|-------------|-----|-------------|
| **Production** | `https://acme-v02.api.letsencrypt.org/directory` | 50 certs/week per domain |
| **Staging** | `https://acme-staging-v02.api.letsencrypt.org/directory` | Higher limits, invalid certs |

> **Recommendation**: Use staging for testing, then switch to production.

### Step 4: Initialize Terraform

```bash
terraform init
```

### Step 5: Plan Deployment

```bash
terraform plan
```

Review the planned changes.

### Step 6: Apply Configuration

```bash
terraform apply
```

Type `yes` when prompted.

**Expected deployment time**: 2-3 minutes.

> **Warning**: If you see errors about resources already existing (CRDs, Helm releases), **STOP** and follow the [Adoption Guide](adopting-cert-manager.md) to import existing resources.

## Verification

### Check Pod Status

```bash
kubectl get pods -n cert-manager
```

Expected pods:
- `cert-manager` - Controller
- `cert-manager-webhook` - Validation webhook
- `cert-manager-cainjector` - CA certificate injector

All should be `Running` with `1/1` ready.

### Verify CRDs

```bash
kubectl get crd | grep cert-manager
```

Expected CRDs:
- `certificaterequests.cert-manager.io`
- `certificates.cert-manager.io`
- `challenges.acme.cert-manager.io`
- `clusterissuers.cert-manager.io`
- `issuers.cert-manager.io`
- `orders.acme.cert-manager.io`

### Check ClusterIssuer Status

```bash
kubectl get clusterissuer
```

Output should show:
```
NAME                 READY   AGE
letsencrypt-prod     True    1m
```

Verify details:
```bash
kubectl describe clusterissuer letsencrypt-prod
```

The issuer should show `Ready: True` in the status conditions.

### Test Certificate Issuance

Create a test certificate:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: test-cert
  namespace: default
spec:
  secretName: test-tls-cert
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
    - test.example.com
```

Apply and check status:

```bash
kubectl apply -f test-cert.yaml
kubectl get certificate test-cert -n default
kubectl describe certificate test-cert -n default
```

Certificate should eventually show `Ready: True`.

## Usage

### Configure Ingress for Automatic TLS

Add annotations to your Ingress resource:

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
        - example.com
      secretName: example-tls-cert
  rules:
    - host: example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: example-service
                port:
                  number: 80
```

Cert-manager will automatically:
1. Create a Certificate resource
2. Initiate ACME challenge
3. Obtain certificate from Let's Encrypt
4. Store certificate in the specified Secret

### Monitor Certificate Lifecycle

```bash
# List all certificates
kubectl get certificates -A

# Check certificate details
kubectl describe certificate <name> -n <namespace>

# View certificate requests
kubectl get certificaterequests -A

# Check ACME challenges
kubectl get challenges -A
```

## Operations

### Upgrade Cert-Manager

Update version in `terraform.tfvars`:

```hcl
cert_manager_version = "v1.17.0"
```

Apply changes:

```bash
terraform apply
```

### View Logs

```bash
# Controller logs
kubectl logs -n cert-manager -l app=cert-manager --tail=100

# Webhook logs
kubectl logs -n cert-manager -l app=webhook --tail=100

# CA injector logs
kubectl logs -n cert-manager -l app=cainjector --tail=100
```

### Switch Between Staging and Production

Edit `terraform.tfvars`:

```hcl
# For staging (testing)
issuer_server = "https://acme-staging-v02.api.letsencrypt.org/directory"

# For production
issuer_server = "https://acme-v02.api.letsencrypt.org/directory"
```

Apply changes:

```bash
terraform apply
```

### Uninstall

```bash
terraform destroy
```

**Note**: CRDs are retained by default. To remove them manually:

```bash
kubectl delete crd certificaterequests.cert-manager.io
kubectl delete crd certificates.cert-manager.io
kubectl delete crd challenges.acme.cert-manager.io
kubectl delete crd clusterissuers.cert-manager.io
kubectl delete crd issuers.cert-manager.io
kubectl delete crd orders.acme.cert-manager.io
```

> **Warning**: Deleting CRDs removes all Certificate resources!

## Troubleshooting

### Webhook Not Ready

```bash
# Check webhook pod status
kubectl get pods -n cert-manager -l app=webhook

# Check webhook logs
kubectl logs -n cert-manager -l app=webhook
```

Common cause: CRDs not installed. Fix:

```bash
helm upgrade cert-manager jetstack/cert-manager \
  -n cert-manager --set installCRDs=true
```

### Certificate Stuck in Pending

```bash
# Check certificate status
kubectl describe certificate <name> -n <namespace>

# Check challenges
kubectl get challenges -A
kubectl describe challenge <name> -n <namespace>
```

Common causes:
- Ingress not publicly accessible
- DNS not resolving correctly
- Firewall blocking HTTP traffic

### ClusterIssuer Not Ready

```bash
kubectl describe clusterissuer letsencrypt-prod
```

Common causes:
- Invalid email address
- Wrong ACME server URL
- Incorrect ingress class name

For detailed troubleshooting, see [Troubleshooting Guide](troubleshooting-cert-manager.md).

## API Documentation

- **Cert-Manager API**: [cert-manager.io/docs/reference/api-docs](https://cert-manager.io/docs/reference/api-docs/)
- **Let's Encrypt Rate Limits**: [letsencrypt.org/docs/rate-limits](https://letsencrypt.org/docs/rate-limits/)
- **ACME Protocol**: [datatracker.ietf.org/doc/html/rfc8555](https://datatracker.ietf.org/doc/html/rfc8555)

## Additional Resources

- [Adoption Guide](adopting-cert-manager.md) - Import existing installations into Terraform
- [Troubleshooting Guide](troubleshooting-cert-manager.md)
- [Official Cert-Manager Documentation](https://cert-manager.io/docs/)
- [Certificate Configuration Guide](https://cert-manager.io/docs/usage/certificate/)