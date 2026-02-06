# Adopting Existing LGTM Stack Installation

This guide walks you through adopting an existing LGTM stack (Loki, Grafana, Tempo, Mimir) into Terraform management.

> **Fast Track**: A complete import script is provided at the [end of this guide](#import-script) to automate the import process of all resources.

## Overview

Adoption involves:
1.  **Discovering** current resource names (Buckets, Service Accounts, Helm Releases).
2.  **Configuring** Terraform variables to match your deployment.
3.  **Importing** resources into Terraform state.

## Prerequisites

- Existing LGTM stack deployed in your cluster
- Cloud Provider CLI (`gcloud`, `aws`, or `az`) authenticated
- Terraform >= 1.5.0 and `kubectl` installed

---

## Step 1: Discover Existing Installation

Run these commands to verify your resource names.

### 1. Helm Releases
```bash
helm list -n lgtm
# Note versions for: loki, mimir, tempo, prometheus, grafana
```

### 2. Cloud Storage (GKE Example)
```bash
gcloud storage buckets list --project=YOUR_PROJECT | grep -E "loki|mimir|tempo"
# Record bucket names for: chunks, ruler, blocks, traces
```

### 3. Service Accounts
```bash
# GCP Service Account
gcloud iam service-accounts list | grep observability

# Kubernetes Service Account
kubectl get sa -n lgtm
```

---

## Step 2: Configure `terraform.tfvars`

Navigate to `lgtm-stack/terraform`.

> **Critical**: Ensure `install_cert_manager` and `install_nginx_ingress` are set to `false` if managing them separately.

```hcl
# Cloud Provider
cloud_provider = "gke"       # options: gke, eks, aks, generic
project_id     = "your-project"
region         = "us-central1"

# Cluster & Domain
cluster_name      = "your-cluster"
monitoring_domain = "monitoring.example.com"

# Stack Config (Match existing versions)
loki_version       = "6.20.0"
mimir_version      = "5.5.0"
tempo_version      = "1.57.0"
grafana_version    = "10.3.0"
prometheus_version = "25.27.0"

# Service Accounts (Match existing names)
gcp_service_account_name = "gke-observability-sa"
k8s_service_account_name = "observability-sa"
namespace                = "lgtm"

# External Dependencies (Manage separately)
install_cert_manager  = false
install_nginx_ingress = false
```

---

## Step 3: Import Resources

Initialize Terraform:
```bash
terraform init
```

### Option A: Automated Script (Recommended)

Save this as `import.sh`, make executable (`chmod +x`), and run:

```bash
#!/bin/bash
set -e
PROJECT="your-project"
NAMESPACE="lgtm"
GCPSA="gke-observability-sa@${PROJECT}.iam.gserviceaccount.com"

echo "Importing GCS Buckets..."
for b in loki-chunks loki-ruler mimir-blocks mimir-ruler tempo-traces; do
  terraform import "google_storage_bucket.observability_buckets[\"$b\"]" "${PROJECT}-${b}"
done

echo "Importing Service Accounts..."
terraform import 'google_service_account.observability_sa' "projects/${PROJECT}/serviceAccounts/${GCPSA}"
terraform import 'kubernetes_service_account.observability_sa' "${NAMESPACE}/observability-sa"

echo "Importing Helm Releases..."
terraform import 'helm_release.loki'       "${NAMESPACE}/monitoring-loki"
terraform import 'helm_release.mimir'      "${NAMESPACE}/monitoring-mimir"
terraform import 'helm_release.tempo'      "${NAMESPACE}/monitoring-tempo"
terraform import 'helm_release.grafana'    "${NAMESPACE}/monitoring-grafana"
terraform import 'helm_release.prometheus' "${NAMESPACE}/monitoring-prometheus"

echo "Importing Ingress..."
terraform import 'kubernetes_ingress_v1.monitoring_stack' "${NAMESPACE}/monitoring-stack-ingress"
```

### Option B: Manual Import

If you prefer to import one by one:

```bash
# Helm Releases
terraform import 'helm_release.loki' lgtm/monitoring-loki

# Buckets (Repeat for all buckets)
terraform import 'google_storage_bucket.observability_buckets["loki-chunks"]' project-loki-chunks

# GKE Workload Identity
terraform import 'google_service_account_iam_member.workload_identity_binding' \
  "projects/PROJ/serviceAccounts/SA_EMAIL roles/iam.workloadIdentityUser serviceAccount:PROJ.svc.id.goog[lgtm/observability-sa]"
```

---

## Step 4: Verify Import

```bash
terraform plan
```

**Expected Result**: No changes or minor metadata updates.
*If Terraform plans to destroy/recreate buckets, STOP and check bucket names.*

---

## Common Issues

### "Bucket already exists"
**Cause**: Mismatch between `terraform.tfvars` bucket naming logic and actual bucket names.
**Fix**: Ensure `project_id` and `bucket_suffix` variables align with actual bucket names.

### "Service Account already exists"
**Cause**: Missed importing the GCP Service Account.
**Fix**: Run the service account import command.

---

## Next Steps

1.  **Commit State**: Push `terraform.tfstate` to remote backend.
2.  **Monitor**: Verify Grafana access and data ingestion.
3.  **Upgrade**: Use Terraform to manage future version upgrades.
