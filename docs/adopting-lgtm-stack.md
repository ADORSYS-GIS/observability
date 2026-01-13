# Adopting Existing LGTM Stack Installation

This guide walks you through adopting an existing LGTM (Loki, Grafana, Tempo, Mimir) observability stack into Terraform management.

## Prerequisites

- Existing LGTM stack deployed in your cluster
- GCS buckets for object storage
- GCP Service Account with Workload Identity
- Terraform >= 1.0
- `kubectl` and `helm` CLI installed
- `gcloud` CLI authenticated

## Step 1: Discover Existing Installation

### Helm Releases

```bash
# List all monitoring-related Helm releases
helm list -n lgtm

# Expected output:
# NAME                  NAMESPACE  REVISION  STATUS    CHART
# monitoring-grafana    lgtm       2         deployed  grafana-10.3.0
# monitoring-loki       lgtm       2         deployed  loki-6.20.0
# monitoring-mimir      lgtm       2         deployed  mimir-distributed-5.5.0
# monitoring-prometheus lgtm       2         deployed  prometheus-25.27.0
# monitoring-tempo      lgtm       2         deployed  tempo-distributed-1.57.0
```

### GCS Buckets

```bash
# List buckets (adjust project ID)
gcloud storage buckets list --project=YOUR_PROJECT_ID | grep -E "loki|mimir|tempo"

# Expected output:
# gs://project-id-loki-chunks/
# gs://project-id-loki-ruler/
# gs://project-id-mimir-blocks/
# gs://project-id-mimir-ruler/
# gs://project-id-tempo-traces/
```

### Service Accounts

```bash
# GCP Service Account
gcloud iam service-accounts list --project=YOUR_PROJECT_ID | grep observability

# Kubernetes Service Account
kubectl get sa -n lgtm

# Workload Identity binding
gcloud iam service-accounts get-iam-policy \
  gke-observability-sa@YOUR_PROJECT_ID.iam.gserviceaccount.com
```

**Record these values**:
- Project ID
- GKE cluster name and location
- Namespace (e.g., `lgtm`)
- GCP Service Account email
- K8s Service Account name
- Bucket names
- Chart versions

---

## Step 2: Configure `terraform.tfvars`

Navigate to the Terraform directory:

```bash
cd lgtm-stack/terraform
```

> [!IMPORTANT]
> **Critical**: All component toggles must be set correctly before importing.

```hcl
# GCP Configuration
project_id       = "your-gcp-project-id"
region           = "us-central1"
cluster_name     = "your-cluster-name"
cluster_location = "us-central1"

# Namespace
namespace = "lgtm"

# Service Accounts
gcp_service_account_name = "gke-observability-sa"
k8s_service_account_name = "observability-sa"

# Domain and Email
monitoring_domain = "monitoring.example.com"
letsencrypt_email = "admin@example.com"
grafana_admin_password = "your-secure-password"

# Infrastructure Components (set to false if managed elsewhere)
install_cert_manager  = false
install_nginx_ingress = false

# Reference existing infrastructure
cert_manager_namespace  = "cert-manager"
nginx_ingress_namespace = "ingress-nginx"
ingress_class_name      = "nginx"
cert_issuer_name        = "letsencrypt-prod"
cert_issuer_kind        = "ClusterIssuer"

# Chart Versions (match your cluster)
loki_version       = "6.20.0"
mimir_version      = "5.5.0"
tempo_version      = "1.57.0"
prometheus_version = "25.27.0"
grafana_version    = "10.3.0"
```

---

## Step 3: Initialize Terraform

```bash
terraform init
```

---

## Step 4: Import GCP Resources

### Import GCS Buckets

```bash
# Import each bucket
terraform import 'google_storage_bucket.observability_buckets["loki-chunks"]' project-id-loki-chunks
terraform import 'google_storage_bucket.observability_buckets["loki-ruler"]' project-id-loki-ruler
terraform import 'google_storage_bucket.observability_buckets["mimir-blocks"]' project-id-mimir-blocks
terraform import 'google_storage_bucket.observability_buckets["mimir-ruler"]' project-id-mimir-ruler
terraform import 'google_storage_bucket.observability_buckets["tempo-traces"]' project-id-tempo-traces
```

### Import GCP Service Account

```bash
# Format: projects/{project}/serviceAccounts/{email}
terraform import 'google_service_account.observability_sa' \
  projects/your-gcp-project-id/serviceAccounts/gke-observability-sa@your-gcp-project-id.iam.gserviceaccount.com
```

### Import IAM Bindings

```bash
# Bucket IAM members (repeat for each bucket)
terraform import 'google_storage_bucket_iam_member.bucket_object_admin["loki-chunks"]' \
  "b/your-project-loki-chunks roles/storage.objectAdmin serviceAccount:gke-observability-sa@your-gcp-project-id.iam.gserviceaccount.com"

terraform import 'google_storage_bucket_iam_member.bucket_legacy_writer["loki-chunks"]' \
  "b/your-project-loki-chunks roles/storage.legacyBucketWriter serviceAccount:gke-observability-sa@your-gcp-project-id.iam.gserviceaccount.com"

# Repeat for: loki-ruler, mimir-blocks, mimir-ruler, tempo-traces
```

### Import Workload Identity Binding

```bash
terraform import 'google_service_account_iam_member.workload_identity_binding' \
  "projects/your-gcp-project-id/serviceAccounts/gke-observability-sa@your-gcp-project-id.iam.gserviceaccount.com roles/iam.workloadIdentityUser serviceAccount:your-gcp-project-id.svc.id.goog[lgtm/observability-sa]"
```

---

## Step 5: Import Kubernetes Resources

### Import Namespace

```bash
terraform import 'kubernetes_namespace.observability' lgtm
```

### Import Kubernetes Service Account

```bash
terraform import 'kubernetes_service_account.observability_sa' lgtm/observability-sa
```

### Import Helm Releases

```bash
# Loki
terraform import 'helm_release.loki' lgtm/monitoring-loki

# Mimir
terraform import 'helm_release.mimir' lgtm/monitoring-mimir

# Tempo
terraform import 'helm_release.tempo' lgtm/monitoring-tempo

# Prometheus
terraform import 'helm_release.prometheus' lgtm/monitoring-prometheus

# Grafana
terraform import 'helm_release.grafana' lgtm/monitoring-grafana
```

### Import Ingress Resources

```bash
# Main monitoring ingress
terraform import 'kubernetes_ingress_v1.monitoring_stack' lgtm/monitoring-stack-ingress

# Tempo gRPC ingress
terraform import 'kubernetes_ingress_v1.tempo_grpc' lgtm/monitoring-stack-ingress-grpc
```

---

## Step 6: Verify the Import

```bash
terraform plan
```

**Expected output**: Should show **no changes** or only minor metadata updates.

> [!WARNING]
> If you see planned changes to GCS buckets or Service Accounts, **STOP** and review your configuration. Applying changes could disrupt your production observability stack.

---

## Common Issues

### Error: Error: "Bucket already exists"

**Cause**: Bucket names must be globally unique. Terraform is trying to create a bucket that already exists.

**Fix**: Ensure bucket names in `terraform.tfvars` match exactly:
```bash
# Check actual bucket names
gcloud storage buckets list --project=YOUR_PROJECT_ID

# Ensure local.bucket_prefix in main.tf matches
# local.bucket_prefix = var.project_id
```

---

### Error: Error: "Service Account already exists"

**Cause**: The GCP Service Account already exists but isn't imported.

**Fix**: Import it (see Step 4 above).

---

### Error: Helm Release Version Mismatch

**Symptoms**: Terraform wants to upgrade/downgrade Helm releases.

**Fix**: Ensure chart versions in `terraform.tfvars` match exactly:
```bash
# Check current versions
helm list -n lgtm

# Update terraform.tfvars to match
loki_version = "6.20.0"  # Must match helm list output
```

---

### Error: Workload Identity Not Working

**Symptoms**: Pods can't access GCS buckets after adoption.

**Fix**: Verify the binding:
```bash
# Check K8s SA annotation
kubectl get sa observability-sa -n lgtm -o yaml | grep iam.gke.io

# Check GCP IAM binding
gcloud iam service-accounts get-iam-policy \
  gke-observability-sa@PROJECT_ID.iam.gserviceaccount.com
```

---

## Import Script

For convenience, here's a complete import script:

```bash
#!/bin/bash
set -e

PROJECT_ID="your-gcp-project-id"
NAMESPACE="lgtm"
GCP_SA="gke-observability-sa@${PROJECT_ID}.iam.gserviceaccount.com"

echo "Importing GCS Buckets..."
for bucket in loki-chunks loki-ruler mimir-blocks mimir-ruler tempo-traces; do
  terraform import "google_storage_bucket.observability_buckets[\"$bucket\"]" "${PROJECT_ID}-${bucket}"
done

echo "Importing GCP Service Account..."
terraform import 'google_service_account.observability_sa' \
  "projects/${PROJECT_ID}/serviceAccounts/${GCP_SA}"

echo "Importing Workload Identity..."
terraform import 'google_service_account_iam_member.workload_identity_binding' \
  "projects/${PROJECT_ID}/serviceAccounts/${GCP_SA} roles/iam.workloadIdentityUser serviceAccount:${PROJECT_ID}.svc.id.goog[${NAMESPACE}/observability-sa]"

echo "Importing Kubernetes Resources..."
terraform import 'kubernetes_namespace.observability' "${NAMESPACE}"
terraform import 'kubernetes_service_account.observability_sa' "${NAMESPACE}/observability-sa"

echo "Importing Helm Releases..."
for release in loki mimir tempo prometheus grafana; do
  terraform import "helm_release.${release}" "${NAMESPACE}/monitoring-${release}"
done

echo "Importing Ingress Resources..."
terraform import 'kubernetes_ingress_v1.monitoring_stack' "${NAMESPACE}/monitoring-stack-ingress"
terraform import 'kubernetes_ingress_v1.tempo_grpc' "${NAMESPACE}/monitoring-stack-ingress-grpc"

echo "Success: Import complete! Run 'terraform plan' to verify."
```

---

## Next Steps

After successful adoption:

1. **Test**: Verify all dashboards and queries work in Grafana
2. **Monitor**: Check that metrics, logs, and traces are still being ingested
3. **Document**: Update your team's runbook with the adopted configuration
4. **Backup**: Commit your `terraform.tfstate` to secure remote storage
