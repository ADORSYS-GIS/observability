# NGINX Ingress Controller - Terraform Deployment

External traffic routing and Layer 7 load balancing with multi-cloud support.

**Version**: 4.14.2 (latest stable as of January 2026)  
**Official Docs**: [kubernetes.github.io/ingress-nginx](https://kubernetes.github.io/ingress-nginx/)

## Overview

Deploys NGINX Ingress Controller with:
- Multi-cloud support (GKE, EKS, AKS, generic)
- Cloud provider LoadBalancer integration
- Path-based and host-based routing
- SSL/TLS termination with cert-manager
- WebSocket support
- High availability with replica scaling

---

## State Management

Terraform state tracks ingress controller deployment.

### State File Location

```
<bucket>/terraform/ingress-controller/
```

### Backend Setup by Provider

**GKE (GCS)**:
```bash
export TF_STATE_BUCKET="your-bucket"
cd ingress-controller/terraform
bash ../../.github/scripts/configure-backend.sh gke ingress-controller
```

**EKS (S3)**:
```bash
export TF_STATE_BUCKET="your-bucket"
export AWS_REGION="us-east-1"
bash ../../.github/scripts/configure-backend.sh eks ingress-controller
```

**AKS (Azure Blob)**:
```bash
export AZURE_STORAGE_ACCOUNT="your-account"
export AZURE_STORAGE_CONTAINER="terraform-state"
bash ../../.github/scripts/configure-backend.sh aks ingress-controller
```

See [Terraform State Management Guide](terraform-state-management.md) for bucket setup.

---

## Prerequisites

| Requirement | Version | Purpose |
|-------------|---------|---------|
| Terraform | ≥ 1.5.0 | Infrastructure provisioning |
| kubectl | ≥ 1.24 | Kubernetes access |
| Kubernetes | ≥ 1.24 | Target cluster |

**Cloud provider authentication** must be configured before deployment.

---

## Deployment Methods

### Option A: Automated (GitHub Actions)

**Workflows**:
- `.github/workflows/deploy-ingress-controller-gke.yaml`
- `.github/workflows/deploy-ingress-controller-eks.yaml`
- `.github/workflows/deploy-ingress-controller-aks.yaml`
- `.github/workflows/destroy-ingress-controller.yaml`

**Features**:
- Terraform plan with PR comments
- Multi-cloud backend (GCS/S3/Azure Blob)
- Automatic authentication
- LoadBalancer validation
- Zero-downtime upgrades

**Usage**:
1. Configure GitHub secrets (see workflow files)
2. Push to trigger deployment
3. Review plan in PR comments
4. Merge to apply

### Option B: Manual Terraform

#### Step 1: Configure Backend

```bash
cd ingress-controller/terraform

# Example: GKE
export TF_STATE_BUCKET="my-tf-state"
bash ../../.github/scripts/configure-backend.sh gke ingress-controller
```

#### Step 2: Configure Variables

```bash
cp terraform.tfvars.template terraform.tfvars
```

**Configuration**:
```hcl
# Cloud provider
cloud_provider = "gke"  # Options: gke, eks, aks, generic

# GKE-specific (if using GKE)
project_id         = "your-gcp-project"
region             = "us-central1"
gke_endpoint       = ""  # Auto-populated
gke_ca_certificate = ""  # Auto-populated

# Ingress controller
install_nginx_ingress = true
nginx_ingress_version = "4.14.2"
namespace             = "ingress-nginx"
release_name          = "nginx-monitoring"
ingress_class_name    = "nginx"

# High availability
replica_count = 2  # Use 3 for production

# Optional: Resource limits
# controller_resources = {
#   requests = {
#     cpu    = "100m"
#     memory = "90Mi"
#   }
#   limits = {
#     cpu    = "1000m"
#     memory = "512Mi"
#   }
# }
```

#### Step 3: Deploy

```bash
terraform init
terraform plan
terraform apply
```

Deployment: ~2-3 minutes.

---

## Verification

### Check Pods

```bash
kubectl get pods -n ingress-nginx
```

Expected: `nginx-monitoring-ingress-nginx-controller-*` pods running.

### Check LoadBalancer

```bash
kubectl get svc -n ingress-nginx
```

Expected:
```
NAME                                        TYPE           EXTERNAL-IP
nginx-monitoring-ingress-nginx-controller   LoadBalancer   34.xx.xx.xx
```

**Note**: `EXTERNAL-IP` may be `<pending>` for 1-3 minutes.

### Verify IngressClass

```bash
kubectl get ingressclass
```

Expected:
```
NAME    CONTROLLER             
nginx   k8s.io/ingress-nginx
```

### Test Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: test-ingress
  namespace: default
spec:
  ingressClassName: nginx
  rules:
    - host: test.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: test-service
                port:
                  number: 80
```

```bash
kubectl apply -f test-ingress.yaml
kubectl get ingress test-ingress
```

---

## Usage

### Basic Ingress with TLS

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: example
  namespace: default
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - example.com
      secretName: example-tls
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

### Common Annotations

```yaml
metadata:
  annotations:
    # SSL redirect
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    
    # Force SSL
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    
    # Body size limit
    nginx.ingress.kubernetes.io/proxy-body-size: "100m"
    
    # WebSocket
    nginx.ingress.kubernetes.io/websocket-services: "ws-service"
    
    # Rate limiting
    nginx.ingress.kubernetes.io/limit-rps: "10"
    
    # Timeout
    nginx.ingress.kubernetes.io/proxy-read-timeout: "600"
```

### DNS Configuration

```bash
# Get LoadBalancer IP
kubectl get svc -n ingress-nginx nginx-monitoring-ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# Create A record: example.com -> <EXTERNAL-IP>
```

---

## Operations

### Upgrade Version

Update `terraform.tfvars`:
```hcl
nginx_ingress_version = "4.15.0"
```

Apply:
```bash
terraform apply
```

### Scale Replicas

Update `terraform.tfvars`:
```hcl
replica_count = 3
```

Apply:
```bash
terraform apply
```

### View Logs

```bash
# All controllers
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=100

# Specific pod
kubectl logs -n ingress-nginx <pod-name>

# Follow
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx -f
```

### Metrics

```bash
# Port-forward
kubectl port-forward -n ingress-nginx svc/nginx-monitoring-ingress-nginx-controller-metrics 10254:10254

# Query
curl http://localhost:10254/metrics
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| **State lock error** | Wait or `terraform force-unlock LOCK_ID` |
| **Bucket not found** | Create bucket (see [State Management](terraform-state-management.md)) |
| **Backend config changed** | Run `terraform init -reconfigure` |
| **LoadBalancer stuck** | Check quotas: `kubectl describe svc -n ingress-nginx` |
| **404 errors** | Verify Ingress exists: `kubectl get ingress -A` |
| **IngressClass conflict** | Use unique name: `ingress_class_name = "nginx-custom"` |
| **TLS not working** | Check cert: `kubectl get certificate -A` |
| **Permission denied** | Verify cloud IAM roles (see workflow files) |

See [Troubleshooting Guide](troubleshooting-ingress-controller.md) for detailed solutions.

---

## Production Configuration

```hcl
replica_count = 3

controller_resources = {
  requests = {
    cpu    = "200m"
    memory = "256Mi"
  }
  limits = {
    cpu    = "2000m"
    memory = "1Gi"
  }
}
```

### High Traffic Settings

```yaml
# Custom Helm values
controller:
  config:
    keep-alive: "75"
    keep-alive-requests: "10000"
    proxy-buffer-size: "16k"
    worker-processes: "auto"
```

---

## Supported Cloud Providers

| Provider | Authentication | Backend | LoadBalancer |
|----------|---------------|---------|--------------|
| **GKE** | `gcloud` + SA | GCS | Network LB / HTTP(S) LB |
| **EKS** | `aws` + IAM | S3 | Network LB / Classic LB |
| **AKS** | `az` + SP | Azure Blob | Azure LB |
| **Generic** | `kubectl` | K8s Secret | Cloud-specific |

---

## Next Steps

- [Adoption Guide](adopting-ingress-controller.md) - Import existing installation
- [Troubleshooting](troubleshooting-ingress-controller.md) - Common issues
- [NGINX Docs](https://kubernetes.github.io/ingress-nginx/) - Official documentation
