# Troubleshooting ArgoCD

This guide covers common issues encountered when deploying or managing ArgoCD with Keycloak OIDC integration.

## Deployment Issues

### ClusterRole Ownership Conflicts

**Symptoms**:
```
Error: Unable to continue with install: ClusterRole "argocd-server" in namespace "" exists 
and cannot be imported into the current release: invalid ownership metadata; 
annotation validation error: key "meta.helm.sh/release-namespace" must equal "argocd-test": 
current value is "argocd"
```

**Cause**: Old ArgoCD installation left cluster-wide resources (ClusterRoles, ClusterRoleBindings) with different namespace annotations.

**Diagnosis**:
```bash
# List all ArgoCD ClusterRoles
kubectl get clusterrole | grep argocd

# Check annotations
kubectl get clusterrole argocd-server -o yaml | grep -A 5 "annotations:"
```

**Fix**: Delete conflicting cluster resources
```bash
# Delete ClusterRoles
kubectl delete clusterrole argocd-server
kubectl delete clusterrole argocd-application-controller
kubectl delete clusterrole argocd-notifications-controller

# Delete ClusterRoleBindings
kubectl delete clusterrolebinding argocd-server
kubectl delete clusterrolebinding argocd-application-controller
kubectl delete clusterrolebinding argocd-notifications-controller

# Then retry deployment
terraform apply
```

---

### CRD Cleanup After Uninstall

**Symptoms**:
```
Warning: Helm uninstall returned an information message

These resources were kept due to the resource policy:
[CustomResourceDefinition] applications.argoproj.io
[CustomResourceDefinition] applicationsets.argoproj.io
[CustomResourceDefinition] appprojects.argoproj.io
```

**Cause**: ArgoCD CRDs are retained by default when uninstalling to prevent data loss.

**Diagnosis**:
```bash
# Check for ArgoCD CRDs
kubectl get crd | grep argoproj
```

**Fix**: Manually delete if doing a clean reinstall
```bash
kubectl delete crd applications.argoproj.io
kubectl delete crd applicationsets.argoproj.io
kubectl delete crd appprojects.argoproj.io
```

> [!CAUTION]
> Deleting CRDs will also delete all Application, ApplicationSet, and AppProject resources!

---

## Keycloak OIDC Integration Issues

### Login Redirect Fails

**Symptoms**: Clicking "Login via Keycloak" redirects to Keycloak but returns with error "invalid redirect URI".

**Diagnosis**:
```bash
# Check ArgoCD OIDC configuration
kubectl get cm argocd-cm -n argocd-test -o yaml

# Check Keycloak client configuration (via Keycloak Admin Console)
# Clients → argocd-client → Settings → Valid Redirect URIs
```

**Fix**: Ensure redirect URIs match
```bash
# In Keycloak, add these URIs:
https://argocd.example.com/auth/callback
https://argocd.example.com/*

# Verify argocd_url in terraform.tfvars matches
argocd_url = "https://argocd.example.com"
```

---

### "Failed to query provider" Error

**Symptoms**: ArgoCD logs show:
```
Failed to query provider "https://keycloak.example.com/realms/argocd": 
Get "https://keycloak.example.com/realms/argocd/.well-known/openid-configuration": 
dial tcp: lookup keycloak.example.com: no such host
```

**Cause**: ArgoCD cannot reach Keycloak (DNS, network, or certificate issues).

**Diagnosis**:
```bash
# Test from ArgoCD pod
kubectl exec -n argocd-test <argocd-server-pod> -- \
  curl -v https://keycloak.example.com/realms/argocd/.well-known/openid-configuration

# Check DNS resolution
kubectl exec -n argocd-test <argocd-server-pod> -- \
  nslookup keycloak.example.com
```

**Fix**:
1. **DNS Issue**: Ensure Keycloak domain resolves
2. **Certificate Issue**: If using self-signed certs, configure ArgoCD to skip TLS verification (not recommended for production)
3. **Network Policy**: Ensure ArgoCD namespace can reach Keycloak

---

### "Groups" Claim Not Received

**Symptoms**: Users can log in but don't have correct RBAC permissions.

**Diagnosis**:
```bash
# Check ArgoCD RBAC configuration
kubectl get cm argocd-rbac-cm -n argocd-test -o yaml

# Check Keycloak group mapper
# In Keycloak Admin Console:
# Clients → argocd-client → Client Scopes → Dedicated → Mappers
```

**Fix**: Ensure group mapper exists
```bash
# In Keycloak, create a "Group Membership" mapper:
# - Name: group-mapper
# - Mapper Type: Group Membership
# - Token Claim Name: groups
# - Full group path: OFF
# - Add to ID token: ON
# - Add to access token: ON
# - Add to userinfo: ON
```

---

## Application Sync Issues

### Application Stuck in "Unknown" Status

**Symptoms**:
```bash
kubectl get applications -n argocd-test
# NAME      SYNC STATUS   HEALTH STATUS
# my-app    Unknown       Unknown
```

**Diagnosis**:
```bash
# Check application details
kubectl describe application my-app -n argocd-test

# Check repo-server logs
kubectl logs -n argocd-test -l app.kubernetes.io/name=argocd-repo-server
```

**Common Causes**:

#### 1. **Git Repository Unreachable**

**Fix**:
```bash
# Test Git access from repo-server pod
kubectl exec -n argocd-test <repo-server-pod> -- \
  git ls-remote https://github.com/user/repo.git
```

#### 2. **Invalid Credentials**

**Fix**: Update repository credentials in ArgoCD UI or via kubectl:
```bash
kubectl edit secret -n argocd-test argocd-repo-creds-<hash>
```

---

### "ComparisonError" - Manifest Generation Failed

**Symptoms**: Application shows "ComparisonError" with message about Helm/Kustomize failure.

**Diagnosis**:
```bash
# Check application events
kubectl describe application my-app -n argocd-test

# Check repo-server logs
kubectl logs -n argocd-test -l app.kubernetes.io/name=argocd-repo-server --tail=100
```

**Common Causes**:
1. **Invalid Helm values**: Syntax error in values file
2. **Missing Helm dependencies**: Chart dependencies not downloaded
3. **Kustomize build error**: Invalid kustomization.yaml

**Fix**: Validate manifests locally
```bash
# For Helm
helm template my-app ./chart --values values.yaml

# For Kustomize
kustomize build ./overlay
```

---

## Performance Issues

### Slow Application Sync

**Diagnosis**:
```bash
# Check application-controller logs
kubectl logs -n argocd-test -l app.kubernetes.io/name=argocd-application-controller

# Check resource usage
kubectl top pods -n argocd-test
```

**Fix**: Increase controller resources
```bash
# Edit deployment
kubectl edit deployment argocd-application-controller -n argocd-test

# Increase CPU/memory limits
```

---

## Terraform-Specific Issues

### Import Failures

**Error**: "Configuration for import target does not exist"

**Fix**:
```bash
# Ensure Keycloak provider is configured
# Check provider.tf has keycloak provider block

# Import Keycloak client
terraform import 'keycloak_openid_client.argocd' <realm>/<client-id>
```

---

### Keycloak Client Secret Rotation

**Issue**: After Terraform manages Keycloak client, the secret may change.

**Fix**: Retrieve new secret and update ArgoCD
```bash
# Get secret from Terraform output
terraform output -raw argocd_admin_secret

# Or from Keycloak Admin Console:
# Clients → argocd-client → Credentials → Client Secret
```

---

## Verification Commands

```bash
# Check all ArgoCD resources
kubectl get all -n argocd-test

# Check ArgoCD CRDs
kubectl get crd | grep argoproj

# Check Applications
kubectl get applications -A

# Check ArgoCD ConfigMaps
kubectl get cm -n argocd-test

# View server logs
kubectl logs -n argocd-test -l app.kubernetes.io/name=argocd-server --tail=100

# View application-controller logs
kubectl logs -n argocd-test -l app.kubernetes.io/name=argocd-application-controller --tail=100

# View repo-server logs
kubectl logs -n argocd-test -l app.kubernetes.io/name=argocd-repo-server --tail=100

# Port-forward to ArgoCD UI
kubectl port-forward -n argocd-test svc/argocd-server 8080:443
# Access: https://localhost:8080
```

---

