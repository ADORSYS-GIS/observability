# NGINX Inc RBAC Fix for Ingress Controller

## For: Cert-Manager/Ingress-Controller Owner

---

## 🚨 What Was Wrong

When deploying NGINX Inc ingress controller via Helm, the controller **cannot read ingress resources** from Kubernetes API because the Helm chart doesn't create sufficient RBAC permissions.

### Error Observed:
```
User "system:serviceaccount:ingress-nginx:nginx-monitoring-nginx-ingress" 
cannot list resource "ingresses" in API group "networking.k8s.io"
```

### Impact:
- NGINX Inc controller ignores all ingress resources
- ArgoCD ingress exists but isn't processed
- Traffic doesn't route → 403 Forbidden errors

---

## ✅ The Fix

**File Changed:** `ingress-controller/terraform/main.tf`

**What Was Added:** (~95 lines after line 109)

```terraform
resource "kubernetes_cluster_role_v1" "nginx_ingress_rbac" {
  count = var.install_nginx_ingress ? 1 : 0

  metadata {
    name = "nginx-ingress"
  }

  # Grants permissions to:
  # - List and watch ingresses
  # - Read services, endpoints, pods, secrets, configmaps
  # - Update ingress status
  # - Create/patch events
}

resource "kubernetes_cluster_role_binding_v1" "nginx_ingress_rbac" {
  count = var.install_nginx_ingress ? 1 : 0

  metadata {
    name = "nginx-ingress"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.nginx_ingress_rbac[0].metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = "nginx-monitoring-nginx-ingress"  # Created by Helm
    namespace = var.namespace
  }

  depends_on = [helm_release.nginx_ingress]
}
```

---

## 🎯 Why This Is Needed

### NGINX Inc vs Community NGINX:

| Feature | Community NGINX | NGINX Inc |
|---------|----------------|-----------|
| Helm creates RBAC | ✅ Yes | ❌ No |
| Requires manual RBAC | ❌ No | ✅ Yes |

The NGINX Inc Helm chart is designed for enterprise use where RBAC is often managed separately. This fix adds Terraform-managed RBAC that's created alongside the Helm release.

---

## 📦 How to Deploy

### Option 1: Via GitHub Workflow
```bash
# Push this change to your branch
git add ingress-controller/terraform/main.tf
git commit -m "fix(ingress-controller): add required RBAC for NGINX Inc"
git push

# Run the workflow:
.github/workflows/deploy-ingress-controller-gke.yaml
```

### Option 2: Manual Terraform Apply
```bash
cd ingress-controller/terraform
terraform validate
terraform plan
terraform apply
```

---

## ✅ Verification

After deployment, verify RBAC exists:

```bash
# Check ClusterRole
kubectl get clusterrole nginx-ingress
kubectl describe clusterrole nginx-ingress

# Check ClusterRoleBinding
kubectl get clusterrolebinding nginx-ingress
kubectl describe clusterrolebinding nginx-ingress

# Verify no RBAC errors in controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=nginx-ingress --tail=50 | grep -i "error\|forbidden"
# Should show no RBAC errors

# Verify ingresses are being processed
kubectl get ingress -A
# All ingresses should have ADDRESS populated
```

---

## 📋 Impact on Other Services

### ✅ ArgoCD Agent:
- No changes needed to ArgoCD workflows or Terraform
- ArgoCD ingress will now be processed correctly by NGINX Inc

### ✅ Cert-Manager:
- No changes needed
- ACME challenges will work properly
- TLS certificates will be issued correctly

### ✅ Other Ingresses:
- Any ingress in the cluster will now work with NGINX Inc
- All services using ingress resources benefit from this fix

---

## 🔒 Security Note

This RBAC configuration grants **read-only** permissions for most resources:
- ✅ Read: ingresses, services, endpoints, pods, secrets, configmaps
- ✅ Update: ingress status (to populate LoadBalancer IP)
- ✅ Create/Patch: events (for logging)

This follows the **principle of least privilege** - only permissions needed for the ingress controller to function.

---

## 📚 References

- NGINX Inc Docs: https://docs.nginx.com/nginx-ingress-controller/
- Kubernetes RBAC: https://kubernetes.io/docs/reference/access-authn-authz/rbac/
- Related Issue: ArgoCD 403 errors due to missing NGINX Inc RBAC

---

**Questions?** Contact the ArgoCD Agent team member who created this fix.

