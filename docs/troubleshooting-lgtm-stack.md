# Troubleshooting LGTM Stack

This guide covers common issues encountered when deploying or managing the LGTM (Loki, Grafana, Tempo, Mimir) observability stack.

## Terraform Deployment Issues

### Terraform State Locks

**Symptoms**:
```
Error: Error acquiring the state lock

Error message: ConditionalCheckFailedException: The conditional request failed
Lock Info:
  ID:        abc123...
  Path:      terraform.tfstate
  Operation: OperationTypeApply
  Who:       user@hostname
  Version:   1.5.0
  Created:   2024-01-12 10:30:00 UTC
```

**Cause**: Another Terraform process is running, or a previous run was interrupted.

**Diagnosis**:
```bash
# Check if another terraform process is running
ps aux | grep terraform

# Check state file lock
terraform force-unlock -help
```

**Fix**:
```bash
# If you're SURE no other process is running:
terraform force-unlock <LOCK_ID>

# Example:
terraform force-unlock abc123-def456-ghi789
```

> [!CAUTION]
> Only force-unlock if you're certain no other Terraform process is running!

---

### Provider Authentication Errors

**Symptoms**:
```
Error: Request had insufficient authentication scopes.

googleapi: Error 403: Request had insufficient authentication scopes., forbidden
```

**Cause**: `gcloud` credentials don't have required permissions.

**Fix**:
```bash
# Re-authenticate with application-default credentials
gcloud auth application-default login

# Verify credentials
gcloud auth application-default print-access-token

# Ensure you have required roles:
# - roles/storage.admin (for GCS buckets)
# - roles/iam.serviceAccountAdmin (for service accounts)
# - roles/container.developer (for GKE)
```

---

### Resource Conflicts with Other Stacks

**Symptoms**: Terraform tries to create resources that already exist (e.g., Cert-Manager, Ingress).

**Diagnosis**:
```bash
# Check what's already deployed
helm list -A | grep -E "cert-manager|ingress"
kubectl get ns
```

**Fix**: Disable conflicting modules in `terraform.tfvars`
```hcl
# If Cert-Manager is managed by another stack:
install_cert_manager = false

# If Ingress is managed by another stack:
install_nginx_ingress = false
```

See: [Shared Infrastructure Guide](kubernetes-observability.md#modular-components--shared-infrastructure)

---

## GCS Bucket Issues

### Bucket Already Exists

**Symptoms**:
```
Error: Error creating bucket: googleapi: Error 409: You already own this bucket. 
Please select another name., conflict
```

**Cause**: Bucket names must be globally unique across all GCP projects.

**Fix**:
```bash
# Check existing buckets
gcloud storage buckets list --project=YOUR_PROJECT_ID

# Ensure bucket_prefix in terraform.tfvars matches your project
# Buckets are named: ${project_id}-${bucket_name}
```

---

### Permission Denied on Bucket

**Symptoms**: Loki/Mimir/Tempo pods can't write to GCS buckets.

**Diagnosis**:
```bash
# Check pod logs
kubectl logs -n lgtm <loki-pod> | grep -i "permission\|denied\|403"

# Check Workload Identity binding
kubectl get sa observability-sa -n lgtm -o yaml | grep iam.gke.io

# Check GCP IAM binding
gcloud iam service-accounts get-iam-policy \
  gke-observability-sa@PROJECT_ID.iam.gserviceaccount.com
```

**Fix**:
```bash
# Verify service account has correct roles
gcloud projects get-iam-policy YOUR_PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:gke-observability-sa@*"

# Should have:
# - roles/storage.objectAdmin (on buckets)
# - roles/storage.legacyBucketWriter (on buckets)
```

---

## Helm Release Issues

### Pods Pending (Resource Constraints)

**Symptoms**:
```bash
kubectl get pods -n lgtm
# NAME                                    READY   STATUS    RESTARTS   AGE
# monitoring-loki-ingester-0              0/1     Pending   0          5m
```

**Diagnosis**:
```bash
# Check pod events
kubectl describe pod monitoring-loki-ingester-0 -n lgtm

# Common event:
# Warning  FailedScheduling  pod has unbound immediate PersistentVolumeClaims
# OR
# Warning  FailedScheduling  0/3 nodes are available: insufficient cpu, insufficient memory
```

**Fix**:

#### 1. **Insufficient Resources**
```bash
# Check node resources
kubectl top nodes

# Scale cluster or reduce resource requests in values files
```

#### 2. **PVC Issues**
```bash
# Check PVCs
kubectl get pvc -n lgtm

# Check storage class
kubectl get storageclass
```

---

### Loki Ingester CrashLoopBackOff

**Symptoms**:
```bash
kubectl get pods -n lgtm
# NAME                                    READY   STATUS             RESTARTS   AGE
# monitoring-loki-ingester-0              0/1     CrashLoopBackOff   5          5m
```

**Diagnosis**:
```bash
# Check logs
kubectl logs -n lgtm monitoring-loki-ingester-0

# Common errors:
# - "failed to create bucket: 403 Forbidden"
# - "schema config invalid"
# - "out of memory"
```

**Fix**:

#### 1. **GCS Permission Issues** (see above)

#### 2. **Invalid Schema Config**
```bash
# Check schema date in values/loki-values.yaml
# Must be in the past:
schemaConfig:
  configs:
    - from: "2025-12-01"  # Must be <= today's date
```

#### 3. **Memory Issues**
```bash
# Increase memory limits in values/loki-values.yaml
resources:
  limits:
    memory: 2Gi  # Increase if needed
```

---

### Mimir Compactor Disk Full

**Symptoms**: Mimir compactor pod evicted or crashing.

**Diagnosis**:
```bash
# Check PVC usage
kubectl exec -n lgtm <compactor-pod> -- df -h /data

# Check events
kubectl describe pod <compactor-pod> -n lgtm
```

**Fix**: Increase PVC size
```bash
# Edit PVC (if storage class supports expansion)
kubectl edit pvc data-monitoring-mimir-compactor-0 -n lgtm

# Or update values/mimir-values.yaml:
compactor:
  persistentVolume:
    size: 500Gi  # Increase size
```

---

## Grafana Issues

### Datasource Connection Failures

**Symptoms**: Grafana can't connect to Loki/Mimir/Tempo.

**Diagnosis**:
```bash
# Check Grafana logs
kubectl logs -n lgtm <grafana-pod> | grep -i "datasource\|error"

# Test connectivity from Grafana pod
kubectl exec -n lgtm <grafana-pod> -- \
  curl -v http://monitoring-loki-gateway:80/ready
```

**Fix**: Verify datasource URLs in `values/grafana-values.yaml`
```yaml
datasources:
  datasources.yaml:
    datasources:
      - name: Loki
        url: http://monitoring-loki-gateway:80  # Must match service name
```

---

### Admin Password Not Working

**Symptoms**: Can't log in to Grafana with configured password.

**Fix**: Retrieve password from secret
```bash
# Get password
kubectl get secret -n lgtm monitoring-grafana \
  -o jsonpath="{.data.admin-password}" | base64 -d

# Or reset via Terraform
# Update grafana_admin_password in terraform.tfvars
terraform apply
```

---

## Ingress Issues

### Monitoring Endpoints Not Accessible

**Symptoms**: Can't access Grafana/Loki/Mimir via Ingress.

**Diagnosis**:
```bash
# Check Ingress resource
kubectl describe ingress monitoring-stack-ingress -n lgtm

# Check Ingress Controller
kubectl get svc -n ingress-nginx

# Check DNS
dig grafana.monitoring.example.com
```

**Fix**:

#### 1. **DNS Not Configured**
```bash
# Point DNS to LoadBalancer IP
kubectl get svc -n ingress-nginx ingress-nginx-controller

# Create A records:
# grafana.monitoring.example.com → <EXTERNAL-IP>
# loki.monitoring.example.com → <EXTERNAL-IP>
# etc.
```

#### 2. **Certificate Issues**
```bash
# Check certificate
kubectl get certificate -n lgtm

# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager
```

---

## Verification Commands

```bash
# Check all LGTM resources
kubectl get all -n lgtm

# Check PVCs
kubectl get pvc -n lgtm

# Check Ingress
kubectl get ingress -n lgtm

# Check GCS buckets
gcloud storage buckets list --project=YOUR_PROJECT_ID | grep -E "loki|mimir|tempo"

# Check Workload Identity
kubectl get sa observability-sa -n lgtm -o yaml

# View Loki logs
kubectl logs -n lgtm -l app.kubernetes.io/name=loki --tail=100

# View Mimir logs
kubectl logs -n lgtm -l app.kubernetes.io/name=mimir --tail=100

# View Grafana logs
kubectl logs -n lgtm -l app.kubernetes.io/name=grafana --tail=100

# Port-forward to Grafana
kubectl port-forward -n lgtm svc/monitoring-grafana 3000:80
# Access: http://localhost:3000
```

---

