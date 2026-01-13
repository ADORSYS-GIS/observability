# Manual Cert-Manager Deployment

Guide for manually deploying cert-manager using Helm with ClusterIssuer configuration for Let's Encrypt integration.

**Official Documentation**: [cert-manager.io/docs](https://cert-manager.io/docs/)  
**GitHub Repository**: [cert-manager/cert-manager](https://github.com/cert-manager/cert-manager)

## Overview

This deployment installs cert-manager with:

- **Automated Certificate Management**: Let's Encrypt integration via ACME
- **Custom Resource Definitions**: Certificate lifecycle management
- **Webhook Validation**: Admission control for certificate resources
- **ClusterIssuer**: Cluster-wide certificate authority

## Prerequisites

### Required Tools

| Tool | Version | Purpose |
|------|---------|---------|
| **kubectl** | ≥ 1.24 | Kubernetes CLI |
| **Helm** | ≥ 3.12 | Package manager |
| **Kubernetes Cluster** | ≥ 1.24 | Target platform |

### Required Infrastructure

- **Ingress Controller**: NGINX Ingress Controller for HTTP-01 challenges
- **Public DNS**: Domain names must resolve publicly for Let's Encrypt

## Deployment

### Step 1: Verify Kubernetes Context

```bash
kubectl config current-context
```

Ensure you're connected to the correct cluster.

### Step 2: Add Helm Repository

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update
```

### Step 3: Install Cert-Manager

```bash
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.16.2 \
  --set installCRDs=true
```

**Installation parameters**:
- `--namespace cert-manager` - Dedicated namespace
- `--create-namespace` - Create namespace if it doesn't exist
- `--version v1.16.2` - Chart version
- `--set installCRDs=true` - Install Custom Resource Definitions

**Installation time**: 1-2 minutes.

### Step 4: Verify Installation

```bash
kubectl get pods -n cert-manager
```

Expected output - all pods `Running`:
```
NAME                                      READY   STATUS    RESTARTS   AGE
cert-manager-xxxxxxxxxx-xxxxx             1/1     Running   0          1m
cert-manager-webhook-xxxxxxxxxx-xxxxx     1/1     Running   0          1m
cert-manager-cainjector-xxxxxxxxxx-xxxxx  1/1     Running   0          1m
```

Check CRDs:
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

## Configure ClusterIssuer

### Step 1: Create Issuer Manifest

Create `letsencrypt-prod-issuer.yaml`:

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    # Let's Encrypt production server
    server: https://acme-v02.api.letsencrypt.org/directory
    
    # Email for Let's Encrypt notifications
    email: your-email@example.com  # CHANGE THIS
    
    # Secret to store ACME account private key
    privateKeySecretRef:
      name: letsencrypt-prod-account-key
    
    # HTTP-01 challenge solver
    solvers:
    - http01:
        ingress:
          class: nginx  # Must match your IngressClass
```

> **Important**: Replace `your-email@example.com` with a valid email address.

### Step 2: Apply Issuer Configuration

```bash
kubectl apply -f letsencrypt-prod-issuer.yaml
```

### Step 3: Verify Issuer

```bash
kubectl get clusterissuer letsencrypt-prod
```

Expected output:
```
NAME               READY   AGE
letsencrypt-prod   True    30s
```

Check details:
```bash
kubectl describe clusterissuer letsencrypt-prod
```

Look for `Ready: True` in the status conditions.

## Optional: Create Staging Issuer

For testing, create a staging issuer to avoid Let's Encrypt rate limits:

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    # Let's Encrypt staging server
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: your-email@example.com
    privateKeySecretRef:
      name: letsencrypt-staging-account-key
    solvers:
    - http01:
        ingress:
          class: nginx
```

Apply:
```bash
kubectl apply -f letsencrypt-staging-issuer.yaml
```

## Usage

### Request Certificate via Ingress

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

### Request Certificate Directly

Create a Certificate resource:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: example-cert
  namespace: default
spec:
  secretName: example-tls-secret
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
    - example.com
    - www.example.com
```

Apply and monitor:
```bash
kubectl apply -f certificate.yaml
kubectl get certificate example-cert
kubectl describe certificate example-cert
```

## Verification

### Check Certificate Status

```bash
# List all certificates
kubectl get certificates -A

# Check specific certificate
kubectl describe certificate <name> -n <namespace>
```

### Monitor Challenge Progress

```bash
# View challenges
kubectl get challenges -A

# Check challenge details
kubectl describe challenge <n> -n <namespace>
```

### View Certificate Requests

```bash
kubectl get certificaterequests -A
```

### Check Certificate Secret

```bash
# Verify secret was created
kubectl get secret <secret-name> -n <namespace>

# View certificate details
kubectl get secret <secret-name> -n <namespace> -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout
```

## Troubleshooting

### Pods Not Starting

**Check pod status**:
```bash
kubectl get pods -n cert-manager
kubectl describe pod <pod-name> -n cert-manager
```

**Common causes**:
- Insufficient resources
- Image pull errors
- CRD installation failures

**Fix**:
```bash
# Reinstall with CRDs
helm upgrade cert-manager jetstack/cert-manager \
  -n cert-manager --set installCRDs=true
```

### Webhook Not Ready

**Check webhook logs**:
```bash
kubectl logs -n cert-manager -l app=webhook
```

**Common cause**: CRDs not installed

**Fix**:
```bash
# Verify CRDs exist
kubectl get crd | grep cert-manager

# Reinstall if missing
helm upgrade cert-manager jetstack/cert-manager \
  -n cert-manager --set installCRDs=true
```

### Certificate Issuance Failed

**Check certificate events**:
```bash
kubectl describe certificate <name> -n <namespace>
```

**Check challenges**:
```bash
kubectl get challenges -A
kubectl describe challenge <n> -n <namespace>
```

**Common causes**:

1. **Ingress not publicly accessible**:
```bash
# Test from external network
curl -v http://<domain>/.well-known/acme-challenge/test
```

2. **DNS not resolving**:
```bash
dig <domain>
nslookup <domain>
```

3. **Wrong ingress class**:
```bash
# Verify ingress class in ClusterIssuer matches your controller
kubectl get ingressclass
```

### ClusterIssuer Not Ready

**Check issuer status**:
```bash
kubectl describe clusterissuer letsencrypt-prod
```

**Common causes**:
- Invalid email address
- Wrong ACME server URL
- Network connectivity issues

**Fix**: Edit the ClusterIssuer:
```bash
kubectl edit clusterissuer letsencrypt-prod
```

### Rate Limiting

Let's Encrypt has rate limits. If you hit them:

**Switch to staging issuer**:
```bash
# Update Ingress annotation
cert-manager.io/cluster-issuer: "letsencrypt-staging"
```

**Rate limits**:
- Production: 50 certificates per week per domain
- Staging: Higher limits, but invalid certificates

## Upgrade

### Check Current Version

```bash
helm list -n cert-manager
```

### Upgrade to New Version

```bash
helm repo update

helm upgrade cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --version v1.17.0
```

## Uninstall

```bash
# Uninstall Helm release
helm uninstall cert-manager -n cert-manager

# Delete namespace
kubectl delete namespace cert-manager
```

**Optional - Delete CRDs**:
```bash
kubectl delete crd certificaterequests.cert-manager.io
kubectl delete crd certificates.cert-manager.io
kubectl delete crd challenges.acme.cert-manager.io
kubectl delete crd clusterissuers.cert-manager.io
kubectl delete crd issuers.cert-manager.io
kubectl delete crd orders.acme.cert-manager.io
```

> **Warning**: Deleting CRDs removes all Certificate resources!

## Management

### View Logs

```bash
# Controller logs
kubectl logs -n cert-manager -l app=cert-manager --tail=100

# Webhook logs
kubectl logs -n cert-manager -l app=webhook --tail=100

# CA injector logs
kubectl logs -n cert-manager -l app=cainjector --tail=100
```

### Port Forward for Debugging

```bash
kubectl port-forward -n cert-manager svc/cert-manager 9402:9402
```

Access metrics at `http://localhost:9402/metrics`

## Additional Resources

- [Adoption Guide](adopting-cert-manager.md)
- [Troubleshooting Guide](troubleshooting-cert-manager.md)
- [Official Cert-Manager Documentation](https://cert-manager.io/docs/)
- [Let's Encrypt Rate Limits](https://letsencrypt.org/docs/rate-limits/)