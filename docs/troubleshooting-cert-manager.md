# Troubleshooting Cert-Manager

This guide covers common issues encountered when deploying or managing Cert-Manager.

## Deployment Issues

### Webhook Pod Not Ready

**Symptoms**:
```bash
kubectl get pods -n cert-manager
# NAME                                      READY   STATUS             RESTARTS   AGE
# cert-manager-webhook-xxx                  0/1     CrashLoopBackOff   5          3m
```

**Diagnosis**:
```bash
# Check pod logs
kubectl logs -n cert-manager -l app=webhook

# Check webhook service
kubectl get svc -n cert-manager cert-manager-webhook
```

**Common Causes**:
1. **CRDs not installed**: Webhook requires CRDs to validate resources
2. **Network policies**: Blocking API server → webhook communication
3. **Resource constraints**: Insufficient CPU/memory

**Fix**:
```bash
# Ensure CRDs are installed
kubectl get crd | grep cert-manager

# If missing, reinstall with CRDs
helm upgrade cert-manager jetstack/cert-manager \
  -n cert-manager --set installCRDs=true
```

---

### CRD Namespace Conflicts

**Symptoms**:
```
Error: Unable to continue with update: CustomResourceDefinition "certificaterequests.cert-manager.io" 
in namespace "" exists and cannot be imported into the current release: invalid ownership metadata; 
annotation validation error: key "meta.helm.sh/release-namespace" must equal "cert-manager": 
current value is "cert-manager"
```

**Cause**: CRDs were installed by a previous Cert-Manager in a different namespace.

**Diagnosis**:
```bash
# Check CRD annotations
kubectl get crd certificaterequests.cert-manager.io -o yaml | grep -A 5 "annotations:"
```

**Fix (Option 1 - Recommended)**: Don't manage CRDs via Helm
```bash
# Upgrade without managing CRDs
helm upgrade cert-manager jetstack/cert-manager \
  -n cert-manager --set installCRDs=false
```

**Fix (Option 2 - Advanced)**: Update CRD annotations
```bash
# WARNING: This can break other Cert-Manager installations
kubectl annotate crd certificaterequests.cert-manager.io \
  meta.helm.sh/release-namespace=cert-manager --overwrite
```

---

## Certificate Issuance Issues

### Certificate Stuck in "False" State

**Symptoms**:
```bash
kubectl get certificate -A
# NAME        READY   SECRET      AGE
# my-cert     False   my-secret   5m
```

**Diagnosis**:
```bash
# Check certificate status
kubectl describe certificate my-cert -n <namespace>

# Check certificate request
kubectl get certificaterequest -n <namespace>
kubectl describe certificaterequest <name> -n <namespace>

# Check challenges (for ACME/Let's Encrypt)
kubectl get challenges -A
kubectl describe challenge <name> -n <namespace>
```

**Common Causes**:

#### 1. **HTTP-01 Challenge Failure**

**Symptoms in events**:
```
Waiting for HTTP-01 challenge propagation: failed to perform self check GET request
```

**Fix**:
```bash
# Verify Ingress is created for the challenge
kubectl get ingress -n <namespace>

# Ensure Ingress Class matches
kubectl describe ingress <challenge-ingress> -n <namespace> | grep "Class:"

# Test challenge URL is reachable
curl -v http://<domain>/.well-known/acme-challenge/<token>
```

#### 2. **DNS Propagation Issues** (DNS-01)

**Fix**:
```bash
# Check DNS records
dig _acme-challenge.<domain> TXT

# Wait for propagation (can take up to 10 minutes)
```

#### 3. **Rate Limiting** (Let's Encrypt)

**Symptoms**: "too many certificates already issued"

**Fix**:
```bash
# Switch to staging issuer temporarily
kubectl edit clusterissuer letsencrypt-prod
# Change server to: https://acme-staging-v02.api.letsencrypt.org/directory
```

---

### Issuer Not Ready

**Symptoms**:
```bash
kubectl get clusterissuer
# NAME                 READY   AGE
# letsencrypt-prod     False   5m
```

**Diagnosis**:
```bash
# Check issuer status
kubectl describe clusterissuer letsencrypt-prod
```

**Common Causes**:

#### 1. **Invalid ACME Server URL**

**Fix**:
```yaml
# Correct URLs:
# Production: https://acme-v02.api.letsencrypt.org/directory
# Staging: https://acme-staging-v02.api.letsencrypt.org/directory
```

#### 2. **Invalid Email**

**Fix**:
```bash
# Update issuer with valid email
kubectl edit clusterissuer letsencrypt-prod
```

#### 3. **Solver Configuration Error**

**Fix**:
```bash
# Verify solver configuration
kubectl get clusterissuer letsencrypt-prod -o yaml

# Ensure ingress class matches your controller
spec:
  acme:
    solvers:
    - http01:
        ingress:
          class: nginx  # Must match your IngressClass
```

---

## Terraform-Specific Issues

### Import Failures

**Error**: "Issuer already exists"

**Fix**:
```bash
# Import existing ClusterIssuer
terraform import 'kubernetes_manifest.letsencrypt_issuer[0]' \
  apiVersion=cert-manager.io/v1,kind=ClusterIssuer,name=letsencrypt-prod

# For namespaced Issuer
terraform import 'kubernetes_manifest.letsencrypt_issuer[0]' \
  apiVersion=cert-manager.io/v1,kind=Issuer,namespace=<ns>,name=<name>
```

---

### Helm Release Conflicts

**Error**: "release: already exists"

**Fix**:
```bash
# Check existing release
helm list -A | grep cert-manager

# Import into Terraform
terraform import 'helm_release.cert_manager[0]' <namespace>/<release-name>
```

---

## Verification Commands

```bash
# Check all Cert-Manager resources
kubectl get all -n cert-manager

# Check CRDs
kubectl get crd | grep cert-manager

# Check Issuers
kubectl get clusterissuers,issuers -A

# Check Certificates
kubectl get certificates -A

# Check Certificate Requests
kubectl get certificaterequests -A

# Check Challenges
kubectl get challenges -A

# View webhook logs
kubectl logs -n cert-manager -l app=webhook --tail=100

# View controller logs
kubectl logs -n cert-manager -l app=cert-manager --tail=100
```

---

