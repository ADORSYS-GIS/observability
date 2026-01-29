# NGINX Ingress Controller Manual Deployment

Helm-based deployment of NGINX Ingress Controller for Layer 7 load balancing.

**Official**: [kubernetes.github.io/ingress-nginx](https://kubernetes.github.io/ingress-nginx/) | **GitHub**: [kubernetes/ingress-nginx](https://github.com/kubernetes/ingress-nginx)

## Prerequisites

| Tool | Version |
|------|---------|
| kubectl | ≥ 1.24 |
| Helm | ≥ 3.12 |
| Kubernetes | ≥ 1.24 with LoadBalancer support |

**Cloud Provider Requirements:** Cluster must support LoadBalancer services (GKE, EKS, AKS, or on-premises with MetalLB).

## Installation

**Step 1: Verify Context**

```bash
kubectl config current-context
kubectl cluster-info
```

**Step 2: Add Helm Repository**

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
```

**Step 3: Install NGINX Ingress Controller**

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

**Step 4: Verify Installation**

```bash
# Check pods
kubectl get pods -n ingress-nginx
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=ingress-nginx -n ingress-nginx --timeout=300s

# Check LoadBalancer (may take 1-3 minutes)
kubectl get svc -n ingress-nginx
EXTERNAL_IP=$(kubectl get svc -n ingress-nginx nginx-monitoring-ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "External IP: $EXTERNAL_IP"

# Verify IngressClass
kubectl get ingressclass nginx
```

## Usage

**Basic Ingress:**

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: example-ingress
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
```

**Ingress with TLS (requires cert-manager):**

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: tls-ingress
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

## DNS Configuration

Point your domain A records to the LoadBalancer external IP:

```bash
# Get external IP
kubectl get svc -n ingress-nginx nginx-monitoring-ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

Create DNS records:
- `example.com` → `<EXTERNAL-IP>` (A record)
- `*.example.com` → `<EXTERNAL-IP>` (A record for wildcard)

## Upgrading

```bash
helm repo update
helm upgrade nginx-monitoring ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --version 4.15.0
```

## Uninstalling

```bash
helm uninstall nginx-monitoring -n ingress-nginx
kubectl delete namespace ingress-nginx
```

**Note:** This removes the LoadBalancer, affecting all Ingress-based routing.

## Troubleshooting

| Issue | Check | Fix |
|-------|-------|-----|
| External IP pending | `kubectl describe svc -n ingress-nginx` | Check cloud provider quota/permissions |
| 404 Not Found | `kubectl describe ingress <name>` | Verify service exists and IngressClass is correct |
| 503 Service Unavailable | `kubectl get endpoints <service>` | Verify backend pods are ready |
| Pod CrashLoopBackOff | `kubectl logs -n ingress-nginx <pod>` | Check resource constraints or port conflicts |

Full guide: [Troubleshooting](troubleshooting-ingress-controller.md)

## Adoption

Already have NGINX Ingress Controller? See [Adoption Guide](adopting-ingress-controller.md).
