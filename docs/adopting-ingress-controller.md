# Adopting Existing Ingress Controller Installation

This guide walks you through adopting an existing NGINX Ingress Controller installation into Terraform management.

## Prerequisites

- Existing NGINX Ingress Controller in your cluster
- Terraform >= 1.0
- `kubectl` configured for your cluster
- `helm` CLI installed

## Step 1: Discover Existing Installation

Run these commands to gather information about your current Ingress Controller:

```bash
# 1. Find the Helm release
helm list -A | grep ingress

# Expected output format:
# RELEASE_NAME     NAMESPACE             REVISION  UPDATED                   STATUS    CHART                  APP_VERSION
# ingress-nginx    ingress-nginx  1         2025-12-08 10:53:04...    deployed  ingress-nginx-4.14.1   1.14.1

# 2. Check the IngressClass
kubectl get ingressclass

# Expected output:
# NAME    CONTROLLER                  PARAMETERS   AGE
# nginx   k8s.io/ingress-nginx        <none>       35d

# 3. Check the LoadBalancer service
kubectl get svc -n ingress-nginx

# 4. Verify controller configuration
kubectl get deployment -n ingress-nginx -o yaml | grep -A 10 "args:"
```

**Record these values**:
- Release name (e.g., `ingress-nginx`)
- Namespace (e.g., `ingress-nginx`)
- Chart version (e.g., `4.14.1`)
- IngressClass name (e.g., `nginx`)
- Controller value (e.g., `k8s.io/ingress-nginx`)

---

## Step 2: Configure `terraform.tfvars`

> [!IMPORTANT]
> **Critical**: You MUST set `install_nginx_ingress = true` to create the Terraform resource configuration before importing.

Create or update `terraform.tfvars` with values matching your cluster:

```hcl
# Enable the module (required for import)
install_nginx_ingress = true

# Match your existing installation
nginx_ingress_version      = "4.14.1"                # From helm list
nginx_ingress_namespace    = "ingress-nginx"  # From helm list
nginx_ingress_release_name = "ingress-nginx"         # From helm list
ingress_class_name         = "nginx"                 # From kubectl get ingressclass
```

---

## Step 3: Initialize Terraform

```bash
cd ingress-controller/terraform
terraform init
```

---

## Step 4: Import the Helm Release

```bash
# Format: terraform import <resource_address> <namespace>/<release_name>
terraform import 'helm_release.nginx_ingress[0]' ingress-nginx/ingress-nginx
```

**Expected output**:
```
helm_release.nginx_ingress[0]: Importing from ID "ingress-nginx/ingress-nginx"...
helm_release.nginx_ingress[0]: Import prepared!
  Prepared helm_release for import
helm_release.nginx_ingress[0]: Refreshing state... [id=ingress-nginx]

Import successful!
```

---

## Step 5: Verify the Import

```bash
terraform plan
```

**Expected output**: Should show **no changes** or only minor metadata updates.

> [!WARNING]
> If you see changes to `spec.controller` for the IngressClass, **DO NOT APPLY**. This field is immutable and will cause errors.

---

## Common Issues

### Error: Error: "Configuration for import target does not exist"

**Cause**: `install_nginx_ingress = false` in your `tfvars`.

**Fix**:
```bash
# Set install_nginx_ingress = true in terraform.tfvars
terraform plan  # This creates the resource config
terraform import 'helm_release.nginx_ingress[0]' ingress-nginx/ingress-nginx
```

---

### Error: Error: "IngressClass field is immutable"

**Symptoms**:
```
Error: cannot patch "nginx" with kind IngressClass: IngressClass.networking.k8s.io "nginx" is invalid: 
spec.controller: Invalid value: "k8s.io/nginx": field is immutable
```

**Cause**: Terraform is trying to change the `spec.controller` value, which cannot be modified after creation.

**Fix**: Ensure your `tfvars` matches the existing controller value **exactly**:

```bash
# 1. Check current controller value
kubectl get ingressclass nginx -o jsonpath='{.spec.controller}'
# Output: k8s.io/ingress-nginx

# 2. Verify your module sets this correctly
# In ingress-controller/terraform/main.tf, the controller value is set as:
# controller.ingressClassResource.controllerValue = "k8s.io/${var.ingress_class_name}"

# 3. If ingress_class_name = "nginx", this produces "k8s.io/nginx"
# If your cluster has "k8s.io/ingress-nginx", you have a mismatch!

# 4. Solution: Don't manage the IngressClass via Terraform, or accept the existing value
```

**Workaround**: If the controller value doesn't match, you may need to:
1. Delete the IngressClass manually: `kubectl delete ingressclass nginx`
2. Let Terraform recreate it (⚠️ **WARNING**: This will briefly disrupt ingress routing)

---

### Error: LoadBalancer IP Changes

**Cause**: Terraform may try to recreate the LoadBalancer service, changing the external IP.

**Fix**: Ensure your Helm values preserve the existing service configuration:

```bash
# Check current service type
kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.spec.type}'

# If it's LoadBalancer, ensure Terraform doesn't change it
```

---

## Next Steps

After successful adoption:

1. **Test**: Run `terraform plan` regularly to ensure no drift
2. **Verify Routing**: Test that existing Ingress resources still work
3. **Document**: Update your team's runbook with the adopted configuration

---

## See Also

- [Ingress Controller Terraform Deployment Guide](ingress-controller-terraform-deployment.md)
- [Troubleshooting Ingress Controller](troubleshooting-ingress-controller.md)
