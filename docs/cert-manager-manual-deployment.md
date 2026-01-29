# cert-manager Manual Deployment

Helm-based deployment of cert-manager for TLS certificate automation.

**Official**: [cert-manager.io/docs](https://cert-manager.io/docs/) | **GitHub**: [cert-manager/cert-manager](https://github.com/cert-manager/cert-manager)

## Prerequisites

| Tool | Version |
|------|---------|
| kubectl | ≥ 1.24 |
| Helm | ≥ 3.12 |
| Kubernetes | ≥ 1.24 |

**Dependencies**: Requires NGINX Ingress Controller for HTTP-01 ACME challenges.

## Installation

**Step 1: Verify Context**

```bash
kubectl config current-context
kubectl cluster-info
```

**Step 2: Add Helm Repository**

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update
```

**Step 3: Install cert-manager**

```bash
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.16.2 \
  --set installCRDs=true
```

**Step 4: Verify Installation**

```bash
kubectl get pods -n cert-manager
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=300s

# Verify CRDs
kubectl get crd | grep cert-manager
```

Expected CRDs: `certificaterequests`, `certificates`, `challenges`, `clusterissuers`, `issuers`, `orders`

## Configure ClusterIssuer

**Step 1: Create ClusterIssuer Manifest**

```yaml
# letsencrypt-prod-issuer.yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@example.com  # CHANGE THIS
    privateKeySecretRef:
      name: letsencrypt-prod-account-key
    solvers:
    - http01:
        ingress:
          class: nginx
```

**Step 2: Apply Configuration**

```bash
kubectl apply -f letsencrypt-prod-issuer.yaml
```

**Step 3: Verify Issuer**

```bash
kubectl get clusterissuer letsencrypt-prod
kubectl describe clusterissuer letsencrypt-prod
```

Look for `Ready: True` in status.

## Usage

**Request Certificate via Ingress:**

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

**Monitor Certificate:**

```bash
kubectl get certificate -A
kubectl describe certificate example-tls -n default
kubectl get challenges -A
```

## Upgrading

```bash
helm repo update
helm upgrade cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --version v1.17.0
```

## Uninstalling

```bash
helm uninstall cert-manager -n cert-manager
kubectl delete namespace cert-manager
```

**Warning:** This deletes all CRDs and Certificate resources.

## Troubleshooting

| Issue | Check | Fix |
|-------|-------|-----|
| Pods not starting | `kubectl describe pod -n cert-manager` | Verify CRDs: `kubectl get crd \| grep cert-manager` |
| Certificate not issued | `kubectl describe certificate <name>` | Check ClusterIssuer: `kubectl describe clusterissuer` |
| Challenge failed | `kubectl describe challenge -A` | Verify Ingress is publicly accessible and DNS resolves |
| Rate limited | Check Let's Encrypt rate limits | Use staging issuer temporarily |

Full guide: [Troubleshooting](troubleshooting-cert-manager.md)

## Adoption

Already have cert-manager? See [Adoption Guide](adopting-cert-manager.md).
