# NGINX Ingress Controller Terraform Deployment

External traffic management and load balancing deployment using Terraform and Helm.

**Official Documentation**: [kubernetes.github.io/ingress-nginx](https://kubernetes.github.io/ingress-nginx/)  
**GitHub Repository**: [kubernetes/ingress-nginx](https://github.com/kubernetes/ingress-nginx)

## Overview

This deployment configures NGINX Ingress Controller with:

- **External Load Balancing**: Cloud provider LoadBalancer service for external traffic
- **Path-Based Routing**: Request routing based on hostnames and URL paths
- **SSL/TLS Termination**: HTTPS handling with cert-manager integration
- **WebSocket Support**: Real-time bidirectional communication
- **High Availability**: Multiple controller replicas for production workloads

## Prerequisites

| Requirement | Version | Purpose |
|-------------|---------|---------|
| **Terraform** | ≥ 1.5.0 | Infrastructure provisioning |
| **kubectl** | ≥ 1.24 | Kubernetes cluster access |
| **Kubernetes Cluster** | ≥ 1.24 | Target platform (GKE, EKS, AKS) |

### Cloud Provider Requirements

The ingress controller requires cloud provider LoadBalancer support:

- **GKE**: Network Load Balancer or HTTP(S) Load Balancer
- **EKS**: AWS Network Load Balancer or Classic Load Balancer
- **AKS**: Azure Load Balancer

## Installation

> **Existing Installation?** If you already have NGINX Ingress Controller deployed and want to manage it with Terraform, see the [Adoption Guide](adopting-ingress-controller.md) before proceeding.

### Step 1: Clone Repository

```bash
git clone https://github.com/Adorsys-gis/observability.git
cd observability/ingress-controller/terraform
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
# Enable NGINX Ingress installation
install_nginx_ingress = true

# Deployment Configuration
nginx_ingress_version = "4.14.1"
namespace             = "ingress-nginx"
release_name          = "nginx-monitoring"

# IngressClass Configuration
ingress_class_name = "nginx"

# High Availability
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

### Complete Variable Reference

For all available variables, see [variables.tf](../ingress-controller/terraform/variables.tf).

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `install_nginx_ingress` | Enable NGINX Ingress installation | `false` | |
| `nginx_ingress_version` | Helm chart version | `4.10.1` | |
| `namespace` | Kubernetes namespace | `ingress-nginx` | |
| `release_name` | Helm release name | `nginx-monitoring` | |
| `ingress_class_name` | IngressClass name | `nginx` | |
| `replica_count` | Number of controller replicas | `1` | |

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

**Expected deployment time**: 2-3 minutes for LoadBalancer provisioning.

> **Warning**: If you see errors about resources already existing (Helm releases, IngressClass), **STOP** and follow the [Adoption Guide](adopting-ingress-controller.md) to import existing resources.

## Verification

### Check Pod Status

```bash
kubectl get pods -n ingress-nginx
```

Expected pods:
- `nginx-monitoring-ingress-nginx-controller-*` - Controller pods (1+ replicas)

All should be `Running` with `1/1` ready.

### Check LoadBalancer Service

```bash
kubectl get svc -n ingress-nginx
```

Expected output:
```
NAME                                        TYPE           CLUSTER-IP      EXTERNAL-IP     PORT(S)
nginx-monitoring-ingress-nginx-controller   LoadBalancer   10.xx.xx.xx     34.xx.xx.xx     80:xxxxx/TCP,443:xxxxx/TCP
```

**Note**: `EXTERNAL-IP` may show `<pending>` for 1-3 minutes while the cloud provider provisions the load balancer.

### Verify IngressClass

```bash
kubectl get ingressclass
```

Expected output:
```
NAME    CONTROLLER             PARAMETERS   AGE
nginx   k8s.io/ingress-nginx   <none>       2m
```

### Test Ingress Controller

Create a test Ingress resource:

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

Apply and check:
```bash
kubectl apply -f test-ingress.yaml
kubectl get ingress test-ingress
kubectl describe ingress test-ingress
```

The ingress should show the LoadBalancer IP in the `ADDRESS` field.

## Usage

### Create Ingress Resource

Example Ingress with TLS:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: example-ingress
  namespace: default
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

### Configure DNS

Point your domain to the LoadBalancer IP:

```bash
# Get LoadBalancer IP
kubectl get svc -n ingress-nginx nginx-monitoring-ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# Create A record:
# example.com -> <EXTERNAL-IP>
```

### Common Annotations

```yaml
metadata:
  annotations:
    # SSL redirect
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    
    # Force SSL
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    
    # Increase body size limit
    nginx.ingress.kubernetes.io/proxy-body-size: "100m"
    
    # WebSocket support
    nginx.ingress.kubernetes.io/websocket-services: "ws-service"
    
    # Rate limiting
    nginx.ingress.kubernetes.io/limit-rps: "10"
    
    # Custom timeout
    nginx.ingress.kubernetes.io/proxy-read-timeout: "600"
```

## Operations

### Upgrade Ingress Controller

Update version in `terraform.tfvars`:

```hcl
nginx_ingress_version = "4.15.0"
```

Apply changes:

```bash
terraform apply
```

### Scale Controller Replicas

Update replica count in `terraform.tfvars`:

```hcl
replica_count = 3  # Scale to 3 replicas
```

Apply changes:

```bash
terraform apply
```

### View Controller Logs

```bash
# All controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=100

# Specific pod
kubectl logs -n ingress-nginx <pod-name>

# Follow logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx -f
```

### Check Controller Metrics

```bash
# Port-forward to metrics endpoint
kubectl port-forward -n ingress-nginx svc/nginx-monitoring-ingress-nginx-controller-metrics 10254:10254

# Access metrics
curl http://localhost:10254/metrics
```

### Uninstall

```bash
terraform destroy
```

**Note**: This will remove the LoadBalancer, which may affect DNS resolution and traffic routing.

## Troubleshooting

### LoadBalancer Stuck in Pending

```bash
# Check service status
kubectl describe svc -n ingress-nginx nginx-monitoring-ingress-nginx-controller
```

**Common causes**:
- Cloud provider quota limits
- Insufficient permissions
- Regional capacity issues

**Fix**: Check cloud provider console for LoadBalancer creation status.

### 404 Not Found on Access

**Diagnosis**:
```bash
# Verify Ingress exists
kubectl get ingress -A

# Check Ingress details
kubectl describe ingress <n> -n <namespace>
```

**Common causes**:
- No Ingress resource defined
- Wrong ingress class name
- Backend service not found

### IngressClass Conflicts

**Diagnosis**:
```bash
kubectl get ingressclass
```

**Fix**: Ensure ingress class name is unique:
```hcl
ingress_class_name = "nginx-custom"
```

### TLS Not Working

**Diagnosis**:
```bash
# Check certificate
kubectl get certificate -A

# Check secret exists
kubectl get secret <secret-name> -n <namespace>
```

**Fix**: Verify cert-manager is installed and ClusterIssuer is ready.

For detailed troubleshooting, see [Troubleshooting Guide](troubleshooting-ingress-controller.md).

## Performance Tuning

### Production Configuration

For production workloads:

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

### High Traffic Configuration

For high-traffic scenarios:

```yaml
# Custom Helm values
controller:
  config:
    # Connection settings
    keep-alive: "75"
    keep-alive-requests: "10000"
    
    # Buffer sizes
    proxy-buffer-size: "16k"
    
    # Worker processes
    worker-processes: "auto"
```

## API Documentation

- **NGINX Ingress Configuration**: [kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration](https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/)
- **Annotations Reference**: [kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/annotations](https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/annotations/)
- **Ingress API**: [kubernetes.io/docs/reference/generated/kubernetes-api/v1.28/#ingress-v1-networking-k8s-io](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.28/#ingress-v1-networking-k8s-io)

## Additional Resources

- [Adoption Guide](adopting-ingress-controller.md) - Import existing installations into Terraform
- [Troubleshooting Guide](troubleshooting-ingress-controller.md)
- [Official NGINX Ingress Documentation](https://kubernetes.github.io/ingress-nginx/)
- [Best Practices Guide](https://kubernetes.github.io/ingress-nginx/deploy/)