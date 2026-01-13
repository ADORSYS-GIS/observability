# Manual NGINX Ingress Controller Deployment

Guide for manually deploying NGINX Ingress Controller using Helm for external traffic management and load balancing.

**Official Documentation**: [kubernetes.github.io/ingress-nginx](https://kubernetes.github.io/ingress-nginx/)  
**GitHub Repository**: [kubernetes/ingress-nginx](https://github.com/kubernetes/ingress-nginx)

## Overview

This deployment installs NGINX Ingress Controller with:

- **External Load Balancing**: Cloud provider LoadBalancer for public traffic
- **SSL/TLS Termination**: HTTPS support with certificate management
- **Path-Based Routing**: Flexible request routing rules
- **WebSocket Support**: Real-time communication protocols
- **IngressClass Management**: Kubernetes-native ingress configuration

## Prerequisites

### Required Tools

| Tool | Version | Purpose |
|------|---------|---------|
| **kubectl** | ≥ 1.24 | Kubernetes CLI |
| **Helm** | ≥ 3.12 | Package manager |
| **Kubernetes Cluster** | ≥ 1.24 | Target platform with LoadBalancer support |

### Cloud Provider Requirements

Your cluster must support LoadBalancer services:

- **GKE**: Network Load Balancer provisioning
- **EKS**: AWS Network/Classic Load Balancer
- **AKS**: Azure Load Balancer
- **On-Premises**: MetalLB or similar LoadBalancer implementation

## Deployment

### Step 1: Verify Kubernetes Context

```bash
kubectl config current-context
```

Ensure you're connected to the correct cluster.

### Step 2: Add Helm Repository

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
```

### Step 3: Install NGINX Ingress Controller

```bash
helm install nginx-monitoring ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --version 4.14.1 \
  --set controller.ingressClassResource.name=nginx \
  --set controller.ingressClass=nginx \
  --set controller.ingressClassResource.controllerValue=k8s.io/ingress-nginx \
  --set controller.ingressClassResource.enabled=true \
  --set controller.ingressClassByName=true
```

**Installation parameters**:
- `--namespace ingress-nginx` - Dedicated namespace
- `--create-namespace` - Create namespace if it doesn't exist
- `--version 4.14.1` - Chart version
- `--set controller.ingressClassResource.name=nginx` - IngressClass name
- `--set controller.ingressClassResource.enabled=true` - Create IngressClass resource

**Installation time**: 2-3 minutes for LoadBalancer provisioning.

### Step 4: Verify Installation

```bash
kubectl get pods -n ingress-nginx
```

Expected output - controller pod `Running`:
```
NAME                                                      READY   STATUS    RESTARTS   AGE
nginx-monitoring-ingress-nginx-controller-xxxxxxxxxx-xxxxx   1/1     Running   0          2m
```

## Verification

### Check LoadBalancer Service

```bash
kubectl get svc -n ingress-nginx
```

Expected output:
```
NAME                                        TYPE           CLUSTER-IP      EXTERNAL-IP     PORT(S)
nginx-monitoring-ingress-nginx-controller   LoadBalancer   10.xx.xx.xx     34.xx.xx.xx     80:xxxxx/TCP,443:xxxxx/TCP
```

**Note**: `EXTERNAL-IP` may show `<pending>` for 1-3 minutes during provisioning.

Get the external IP:
```bash
kubectl get svc -n ingress-nginx nginx-monitoring-ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

### Verify IngressClass

```bash
kubectl get ingressclass
```

Expected output:
```
NAME    CONTROLLER             PARAMETERS   AGE
nginx   k8s.io/ingress-nginx   <none>       2m
```

Check details:
```bash
kubectl describe ingressclass nginx
```

### Test Ingress Controller

Create a test backend service:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: test-service
  namespace: default
spec:
  selector:
    app: test
  ports:
    - port: 80
      targetPort: 8080
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-app
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: test
  template:
    metadata:
      labels:
        app: test
    spec:
      containers:
      - name: app
        image: hashicorp/http-echo
        args:
          - "-text=Hello from Ingress Controller"
        ports:
        - containerPort: 8080
```

Create Ingress:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: test-ingress
  namespace: default
spec:
  ingressClassName: nginx
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: test-service
                port:
                  number: 80
```

Apply and test:
```bash
kubectl apply -f test-backend.yaml
kubectl apply -f test-ingress.yaml

# Get LoadBalancer IP
INGRESS_IP=$(kubectl get svc -n ingress-nginx nginx-monitoring-ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Test ingress
curl http://$INGRESS_IP
```

Expected response: `Hello from Ingress Controller`

## Usage

### Basic Ingress with Host-Based Routing

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: example-ingress
  namespace: default
spec:
  ingressClassName: nginx
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
    - host: api.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: api-service
                port:
                  number: 8080
```

### Ingress with TLS

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: tls-ingress
  namespace: default
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - secure.example.com
      secretName: tls-cert-secret
  rules:
    - host: secure.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: secure-service
                port:
                  number: 443
```

### Ingress with Annotations

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: advanced-ingress
  namespace: default
  annotations:
    # SSL redirect
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    
    # Request size limit
    nginx.ingress.kubernetes.io/proxy-body-size: "100m"
    
    # Connection timeout
    nginx.ingress.kubernetes.io/proxy-connect-timeout: "600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "600"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "600"
    
    # Rate limiting
    nginx.ingress.kubernetes.io/limit-rps: "10"
    
    # WebSocket support
    nginx.ingress.kubernetes.io/websocket-services: "ws-service"
    
    # Custom headers
    nginx.ingress.kubernetes.io/configuration-snippet: |
      more_set_headers "X-Custom-Header: custom-value";
spec:
  ingressClassName: nginx
  rules:
    - host: advanced.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: advanced-service
                port:
                  number: 80
```

## Configure DNS

Point your domain A records to the LoadBalancer external IP:

```bash
# Get LoadBalancer IP
kubectl get svc -n ingress-nginx nginx-monitoring-ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# Create DNS records:
# example.com         A    <EXTERNAL-IP>
# *.example.com       A    <EXTERNAL-IP>  (for wildcard subdomains)
```

## Troubleshooting

### LoadBalancer External IP Pending

**Check service status**:
```bash
kubectl get svc -n ingress-nginx
kubectl describe svc nginx-monitoring-ingress-nginx-controller -n ingress-nginx
```

**Common causes**:
- Cloud provider quota exceeded
- Insufficient IAM permissions
- Regional capacity issues

**Fix**:
- Check cloud provider console for LoadBalancer status
- Verify service account permissions
- Try different cluster zone/region

### 404 Not Found Error

**Check Ingress configuration**:
```bash
kubectl get ingress -A
kubectl describe ingress <n> -n <namespace>
```

**Common causes**:
- No Ingress resource defined
- Wrong ingress class name
- Service not found or not ready
- Path/host mismatch

**Fix**:
```bash
# Verify backend service exists
kubectl get svc <service-name> -n <namespace>

# Check service endpoints
kubectl get endpoints <service-name> -n <namespace>

# Verify ingress class
kubectl get ingress <n> -n <namespace> -o jsonpath='{.spec.ingressClassName}'
```

### 503 Service Unavailable

**Check backend service**:
```bash
# Verify service has endpoints
kubectl get endpoints <service-name> -n <namespace>

# Check pod status
kubectl get pods -n <namespace> -l app=<label>
```

**Common causes**:
- No healthy backend pods
- Service selector mismatch
- Pod not ready

### IngressClass Conflicts

**Check existing IngressClasses**:
```bash
kubectl get ingressclass
```

**Fix**: Change IngressClass name to avoid conflicts:
```bash
helm upgrade nginx-monitoring ingress-nginx/ingress-nginx \
  -n ingress-nginx \
  --set controller.ingressClassResource.name=nginx-custom
```

### Controller Pod CrashLoopBackOff

**Check pod logs**:
```bash
kubectl logs -n ingress-nginx <controller-pod>
```

**Common causes**:
- Port conflicts (80/443 already in use)
- Resource constraints
- Configuration errors

**Fix**:
```bash
# Check node port availability
kubectl get svc -A | grep NodePort

# Increase resources
helm upgrade nginx-monitoring ingress-nginx/ingress-nginx \
  -n ingress-nginx \
  --set controller.resources.requests.cpu=200m \
  --set controller.resources.requests.memory=256Mi
```

## High Availability Configuration

For production deployments with HA:

```bash
helm upgrade nginx-monitoring ingress-nginx/ingress-nginx \
  -n ingress-nginx \
  --set controller.replicaCount=3 \
  --set controller.resources.requests.cpu=200m \
  --set controller.resources.requests.memory=256Mi \
  --set controller.autoscaling.enabled=true \
  --set controller.autoscaling.minReplicas=3 \
  --set controller.autoscaling.maxReplicas=10 \
  --set controller.autoscaling.targetCPUUtilizationPercentage=80
```

## Upgrade

### Check Current Version

```bash
helm list -n ingress-nginx
```

### Upgrade to New Version

```bash
helm repo update

helm upgrade nginx-monitoring ingress-nginx/ingress-nginx \
  -n ingress-nginx \
  --version 4.15.0
```

## Uninstall

```bash
# Uninstall Helm release
helm uninstall nginx-monitoring -n ingress-nginx

# Delete namespace
kubectl delete namespace ingress-nginx
```

**Note**: This will remove the LoadBalancer, affecting all Ingress-based traffic routing.

## Management

### View Controller Logs

```bash
# All controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=100

# Follow logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx -f

# Specific pod
kubectl logs -n ingress-nginx <pod-name>
```

### Access Metrics

```bash
# Port-forward to metrics endpoint
kubectl port-forward -n ingress-nginx svc/nginx-monitoring-ingress-nginx-controller-metrics 10254:10254

# View metrics
curl http://localhost:10254/metrics
```

### Check Configuration

```bash
# Get current Helm values
helm get values nginx-monitoring -n ingress-nginx

# Export complete configuration
kubectl get configmap -n ingress-nginx nginx-monitoring-ingress-nginx-controller -o yaml
```

## Additional Resources

- [Adoption Guide](adopting-ingress-controller.md)
- [Troubleshooting Guide](troubleshooting-ingress-controller.md)
- [Official NGINX Ingress Documentation](https://kubernetes.github.io/ingress-nginx/)
- [Annotations Reference](https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/annotations/)
- [Examples Repository](https://github.com/kubernetes/ingress-nginx/tree/main/docs/examples)