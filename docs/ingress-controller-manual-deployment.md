# NGINX Ingress Controller Manual Deployment

Direct Helm-based deployment for command-line control.

Recommended for local development environments, learning, or clusters without CI/CD infrastructure. This method provides step-by-step control over Layer 7 load balancing deployment.

**Official Documentation**: [kubernetes.github.io/ingress-nginx](https://kubernetes.github.io/ingress-nginx/) | **GitHub**: [kubernetes/ingress-nginx](https://github.com/kubernetes/ingress-nginx) | **Version**: `4.14.2`

---

## Prerequisites

Required tools and versions:

| Tool | Version | Verification Command |
|------|---------|---------------------|
| kubectl | ≥ 1.24 | `kubectl version --client` |
| Helm | ≥ 3.12 | `helm version` |
| Kubernetes cluster | ≥ 1.24 | `kubectl version --short` |

**Cloud Provider Requirements:**
- LoadBalancer support: Cluster must provision external IPs (GKE, EKS, AKS, or on-premise with MetalLB)
- Cluster access: `kubectl cluster-info` returns cluster information

**Note:** The ingress controller requires an external IP to route internet traffic to services. Cloud providers (GKE, EKS, AKS) automatically provision LoadBalancers. On-premise clusters require MetalLB or similar LoadBalancer implementation.

---

## Installation

### Step 1: Verify Cluster Context

Confirm connection to the correct cluster:

```bash
kubectl config current-context

kubectl cluster-info

kubectl get nodes
```

To switch to a different cluster context:
```bash
kubectl config get-contexts
kubectl config use-context <context-name>
```

---

### Step 2: Add Helm Repository

Add the official NGINX Ingress Controller Helm repository:

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
```

Verify repository addition:
```bash
helm search repo ingress-nginx/ingress-nginx
```

---

### Step 3: Install NGINX Ingress Controller

Deploy with recommended configuration:

```bash
helm install nginx-monitoring ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --version 4.14.2 \
  --set controller.ingressClassResource.name=nginx \
  --set controller.ingressClass=nginx \
  --set controller.ingressClassResource.controllerValue=k8s.io/ingress-nginx \
  --set controller.ingressClassResource.enabled=true \
  --set controller.ingressClassByName=true
```

This command:
- Creates `ingress-nginx` namespace
- Deploys NGINX controller (2 replicas by default for high availability)
- Creates LoadBalancer service to obtain external IP from cloud provider
- Registers `nginx` IngressClass for routing
- Configures RBAC and service accounts

Installation typically completes in 1-3 minutes, depending on LoadBalancer provisioning time.

**Note:** The release name `nginx-monitoring` allows for multiple ingress controller deployments if needed.

---

### Step 4: Verify Installation

Check pod status:

```bash
kubectl get pods -n ingress-nginx
```

Expected output:
```
NAME                                                READY   STATUS    RESTARTS   AGE
nginx-monitoring-ingress-nginx-controller-xxxxx     1/1     Running   0          60s
nginx-monitoring-ingress-nginx-controller-yyyyy     1/1     Running   0          60s
```

Wait for pods to reach ready state:
```bash
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=ingress-nginx \
  -n ingress-nginx \
  --timeout=300s
```

---

Check LoadBalancer service status:

```bash
kubectl get svc -n ingress-nginx
```

Expected output:
```
NAME                                          TYPE           CLUSTER-IP      EXTERNAL-IP       PORT(S)
nginx-monitoring-ingress-nginx-controller     LoadBalancer   10.52.x.x       34.123.45.67      80:xxxxx/TCP,443:yyyyy/TCP
```

The `EXTERNAL-IP` field should show a public IP address (not `<pending>`).

**If still pending:**
- Allow 2-3 minutes for cloud provider provisioning
- Check cloud provider quotas for external IPs and load balancers
- Verify IAM permissions for LoadBalancer creation

Save the external IP for DNS configuration:
```bash
EXTERNAL_IP=$(kubectl get svc -n ingress-nginx \
  nginx-monitoring-ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
  
echo "External IP: $EXTERNAL_IP"
```

---

Verify IngressClass creation:

```bash
kubectl get ingressclass nginx
```

Expected output:
```
NAME    CONTROLLER                      PARAMETERS   AGE
nginx   k8s.io/ingress-nginx            <none>       2m
```

---

## Usage

Once installed, create Ingress resources to route external traffic to your services.

### Basic HTTP Ingress

Route traffic to a service:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app-ingress
  namespace: default
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

Apply the Ingress:
```bash
kubectl apply -f myapp-ingress.yaml
```

**Traffic flow:**
1. NGINX ingress controller detects new Ingress resource
2. Updates NGINX configuration to route `myapp.example.com` to `myapp-service`
3. External traffic hits LoadBalancer IP → NGINX → application service

---

### Ingress with TLS (HTTPS)

Configure TLS with cert-manager annotation for automatic certificate provisioning:

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

**Requires:** cert-manager installed ([deployment guide](cert-manager-manual-deployment.md))

Apply the Ingress:
```bash
kubectl apply -f tls-ingress.yaml
```

cert-manager automatically provisions and manages TLS certificates from Let's Encrypt.

---

### Path-Based Routing

Route different paths to different services:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: path-based-ingress
spec:
  ingressClassName: nginx
  rules:
    - host: myapp.example.com
      http:
        paths:
          - path: /api
            pathType: Prefix
            backend:
              service:
                name: api-service
                port:
                  number: 8080
          - path: /web
            pathType: Prefix
            backend:
              service:
                name: web-service
                port:
                  number: 80
```

**Traffic routing:**
- `myapp.example.com/api/*` → `api-service:8080`
- `myapp.example.com/web/*` → `web-service:80`

---

## DNS Configuration

Point your domain to the LoadBalancer external IP.

**Step 1: Get external IP**
```bash
kubectl get svc -n ingress-nginx \
  nginx-monitoring-ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

**Step 2: Create DNS A records**

Configure DNS records in your DNS provider (Cloudflare, Route53, Google Domains, etc.):

| Type | Name | Value |
|------|------|-------|
| A | `myapp.example.com` | `<EXTERNAL-IP>` |
| A | `*.example.com` | `<EXTERNAL-IP>` (wildcard for subdomains) |

**Step 3: Wait for DNS propagation**

DNS propagation typically takes 5-30 minutes.

Test DNS resolution:
```bash
dig myapp.example.com
nslookup myapp.example.com
```

**Step 4: Test connectivity**
```bash
curl -v http://myapp.example.com
```

---

## Upgrading Ingress Controller

Update to a newer version:

```bash
# Update Helm repository
helm repo update

# Check available versions
helm search repo ingress-nginx/ingress-nginx --versions

# Upgrade to new version
helm upgrade nginx-monitoring ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --version 4.15.0
```

Helm performs a rolling update with zero downtime.

---

## Uninstalling

**Warning:** Uninstalling removes the LoadBalancer and breaks all Ingress-based routing.

```bash
# Uninstall Helm release
helm uninstall nginx-monitoring -n ingress-nginx

# Delete namespace
kubectl delete namespace ingress-nginx
```

The LoadBalancer external IP is released. All Ingress resources become non-functional.

---

## Troubleshooting

### External IP Stuck in Pending

Check service status:
```bash
kubectl describe svc -n ingress-nginx nginx-monitoring-ingress-nginx-controller
```

**Common causes:**

| Cause | Resolution |
|-------|------------|
| Cloud provider quota exceeded | Check external IP quota in cloud console |
| Insufficient IAM permissions | Verify service account has LoadBalancer creation permission |
| Network policy blocking | Check firewall rules and security groups |
| No LoadBalancer support | Use NodePort or install MetalLB for on-premise clusters |

**For on-premise clusters**, install MetalLB:
```bash
helm repo add metallb https://metallb.github.io/metallb
helm install metallb metallb/metallb --namespace metallb-system --create-namespace
```

---

### Ingress Returns 404 Not Found

Check Ingress configuration:
```bash
kubectl get ingress -A
kubectl describe ingress <ingress-name> -n <namespace>
```

**Common issues:**

| Symptom | Cause | Resolution |
|---------|-------|------------|
| No Ingress Address | Ingress not associated with controller | Verify `ingressClassName: nginx` is set |
| Backend service missing | Service does not exist | Check `kubectl get svc <service> -n <namespace>` |
| No endpoints | Pods not running | Check `kubectl get endpoints <service> -n <namespace>` |
| Wrong host | DNS mismatch | Verify `host:` matches request URL |

---

### Ingress Returns 503 Service Unavailable

Backend service is unreachable:

```bash
# Check backend pod status
kubectl get pods -n <namespace>

# Verify service has endpoints
kubectl get endpoints <service> -n <namespace>
```

**Common causes:**
- No healthy backend pods
- Service selector mismatch (pods don't match service selector)
- Pods failing readiness probes

Check ingress controller logs:
```bash
kubectl logs -n ingress-nginx deploy/nginx-monitoring-ingress-nginx-controller
```

---

### Pods Crash or CrashLoopBackOff

Check pod logs and status:
```bash
kubectl logs -n ingress-nginx <pod-name>
kubectl describe pod -n ingress-nginx <pod-name>
```

**Common causes:**
- Insufficient CPU/memory (check node resources)
- Port conflicts (port 80/443 already in use)
- Image pull errors (verify image pull policy)
- RBAC issues (check service account permissions)

---

### TLS Certificate Not Working

Verify cert-manager is installed:
```bash
kubectl get pods -n cert-manager
```

Check certificate status:
```bash
kubectl get certificate -A
kubectl describe certificate <cert-name> -n <namespace>
```

Check ClusterIssuer:
```bash
kubectl get clusterissuer
kubectl describe clusterissuer letsencrypt-prod
```

See [cert-manager troubleshooting guide](cert-manager-manual-deployment.md#troubleshooting) for detailed debugging.

---

## Monitoring

Access controller metrics:

```bash
# Get controller pod name
CONTROLLER_POD=$(kubectl get pods -n ingress-nginx \
  -l app.kubernetes.io/name=ingress-nginx \
  -o jsonpath='{.items[0].metadata.name}')

# Port forward to metrics endpoint
kubectl port-forward -n ingress-nginx $CONTROLLER_POD 10254:10254
```

Access metrics at `http://localhost:10254/metrics`

**Key metrics:**
- `nginx_ingress_controller_requests` - Request count
- `nginx_ingress_controller_request_duration_seconds` - Request latency
- `nginx_ingress_controller_ingress_upstream_latency_seconds` - Backend latency

---

## Related Documentation

- [GitHub Actions Deployment](ingress-controller-github-actions.md) - Automated CI/CD deployment
- [Deployment Overview](ingress-controller-terraform-deployment.md) - Method comparison
- [cert-manager Manual Deployment](cert-manager-manual-deployment.md) - TLS automation
- [Troubleshooting Guide](troubleshooting-ingress-controller.md) - Advanced debugging
- [Adopting Existing Installation](adopting-ingress-controller.md) - Migration guide

---

**Official Documentation**: [kubernetes.github.io/ingress-nginx](https://kubernetes.github.io/ingress-nginx/)
