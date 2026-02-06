# Troubleshooting LGTM Stack

Common issues and solutions for the LGTM (Loki, Grafana, Tempo, Mimir) observability stack.

---

## Terraform Deployment Issues

### State Locks
**Symptoms**: `Error: Error acquiring the state lock`
**Fix**:
```bash
terraform force-unlock <LOCK_ID>
```
> [!CAUTION]
> Establish strictly that no other process is running before unlocking.

### Provider Authentication Service Account
**Symptoms**: `Error 403: Request had insufficient authentication scopes`
**Fix**:
```bash
gcloud auth application-default login
# Verify roles: storage.admin, iam.serviceAccountAdmin, container.developer
```

### Resource Conflicts
**Symptoms**: "already exists" errors for Cert-Manager or Ingress.
**Fix**: Disable conflicting modules in `terraform.tfvars`:
```hcl
install_cert_manager  = false
install_nginx_ingress = false
```

---

## Storage & Permissions

### Bucket Already Exists
**Symptoms**: `googleapi: Error 409: You already own this bucket`
**Fix**: Ensure `bucket_prefix` + `project_id` in `terraform.tfvars` creates a globally unique name.

### Permission Denied (Pods)
**Symptoms**: Loki/Mimir pods crashing with `403 Forbidden` accessing GCS.
**Diagnosis**:
```bash
kubectl logs -n lgtm <pod-name> | grep 403
```
**Fix**: Check Workload Identity.
```bash
# Verify GCP IAM Policy
gcloud projects get-iam-policy PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:gke-observability-sa@*"
```

---

## Helm & Kubernetes Issues

### Pods Pending
**Symptoms**: `Status: Pending` for long duration.
**Diagnosis**: `kubectl describe pod <pod-name> -n lgtm`
**Common Causes**:
1.  **Insufficient Resources**: Scale cluster or reduce requests.
2.  **PVC Binding**: Check `kubectl get pvc -n lgtm`.

### CrashLoopBackOff (Loki)
**Symptoms**: Ingester pods restarting.
**Diagnosis**: `kubectl logs -n lgtm <pod> --previous`
**Fixes**:
- **Schema Date**: Ensure `schemaConfig` date in values is in the past.
- **Memory**: Increase `limits.memory` in `loki-values.yaml`.

---

## Grafana & Connectivity

### Datasource Errors
**Symptoms**: "Error connecting to datasource" in Grafana.
**Fix**: Verify internal service URLs.
- Loki: `http://monitoring-loki-gateway:80`
- Mimir: `http://monitoring-mimir-nginx:80`

### Ingress Unreachable
**Symptoms**: `502 Bad Gateway` or connection timeout on `grafana.domain.com`.
**Fix**:
1.  **DNS**: Ensure A records point to NGINX LoadBalancer IP.
2.  **Certificates**:
    ```bash
    kubectl get certificate -n lgtm
    kubectl describe clusterissuer letsencrypt-prod
    ```

---

## Verification Commands

**Quick Health Check**:
```bash
kubectl get pods -n lgtm
kubectl get ingress -n lgtm
kubectl get certificate -n lgtm
```

**Logs Inspection**:
```bash
kubectl logs -n lgtm -l app.kubernetes.io/name=loki --tail=50
kubectl logs -n lgtm -l app.kubernetes.io/name=grafana --tail=50
```
