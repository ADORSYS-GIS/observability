# Manual Cert-Manager Deployment (Helm & Kubectl)

This guide explains how to manually deploy **Cert-Manager** and configure a **ClusterIssuer** without using Terraform.

## Prerequisites

- **Helm** 3.x installed
- **kubectl** installed and configured

## 1. Verify Context

Ensure you are targeting the correct Kubernetes cluster:

```bash
kubectl config current-context
```

## 2. Install Cert-Manager via Helm

1. **Add the Jetstack Helm repository**:
   ```bash
   helm repo add jetstack https://charts.jetstack.io
   helm repo update
   ```

2. **Install Cert-Manager**:
   ```bash
   helm install cert-manager jetstack/cert-manager \
     --namespace cert-manager \ # You can change this to your preferred namespace
     --create-namespace \
     --version v1.16.2 \
     --set installCRDs=true
   ```

3. **Verify Installation**:
   ```bash
   kubectl get pods --namespace cert-manager # Adjust namespace if changed above
   ```

## 3. Configure ClusterIssuer

1. **Create the manifest file**:
   Create a file named `cluster-issuer.yaml` in your current directory:

   ```yaml
   apiVersion: cert-manager.io/v1
   kind: ClusterIssuer
   metadata:
     name: letsencrypt-prod
   spec:
     acme:
       server: https://acme-v02.api.letsencrypt.org/directory
       email: your-email@example.com  # REPLACE THIS
       privateKeySecretRef:
         name: letsencrypt-prod-key
       solvers:
       - http01:
           ingress:
             class: nginx
   ```

2. **Apply the manifest**:
   ```bash
   kubectl apply -f cluster-issuer.yaml
   ```

## 4. Verification

Check the status of the ClusterIssuer:

```bash
kubectl get clusterissuer letsencrypt-prod -o wide
```
It should say `True` in the `READY` column.

## 5. Troubleshooting

### Pods Not Starting
```bash
# Check for ImagePullBackOff or CrashLoopBackOff
kubectl describe pod <pod-name> -n cert-manager

# Fix: Verify internet access to pull images
```

### CRD Errors
```bash
# Fix: Ensure installCRDs=true was passed to Helm
helm upgrade cert-manager jetstack/cert-manager -n cert-manager --set installCRDs=true
```

### Certificate Issuance Failed
```bash
# Check certificate lifecycle events
kubectl describe certificate <name>
kubectl describe challengerequest <name>

# Fix: Ensure Ingress is publicly reachable for Let's Encrypt validation
```
