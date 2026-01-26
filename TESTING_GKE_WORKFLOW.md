# Testing LGTM Stack GKE Deployment Workflow

## Quick Start for GKE Testing

### 1. Configure GitHub Secrets

Go to your repository: `Settings → Secrets and variables → Actions → New repository secret`

Add the following secrets:

```bash
# Required GKE Secrets
KUBECONFIG=<base64-encoded-kubeconfig>
GCP_PROJECT_ID=<your-gcp-project-id>
GCP_SA_KEY=<service-account-json-key>
TF_STATE_BUCKET=<terraform-state-bucket-name>
CLUSTER_NAME=<gke-cluster-name>
CLUSTER_LOCATION=<us-central1>
REGION=<us-central1>

# LGTM Configuration
ENVIRONMENT=production
MONITORING_DOMAIN=<monitoring.your-domain.com>
LETSENCRYPT_EMAIL=<your-email@example.com>
GRAFANA_ADMIN_PASSWORD=<secure-password>
```

### 2. Get Base64 Kubeconfig

```bash
# Get your kubeconfig
cat ~/.kube/config | base64 -w 0

# Or for GKE cluster
gcloud container clusters get-credentials <cluster-name> \
  --region=<region> --project=<project-id>

cat ~/.kube/config | base64 -w 0
```

### 3. Create GCS State Bucket

```bash
export PROJECT_ID="your-gcp-project"
export BUCKET_NAME="${PROJECT_ID}-terraform-state"

# Create bucket
gsutil mb -p $PROJECT_ID -l us-central1 gs://$BUCKET_NAME

# Enable versioning
gsutil versioning set on gs://$BUCKET_NAME
```

### 4. Trigger Plan Mode

**Option A: Via GitHub UI**
1. Go to `Actions` tab
2. Click `Deploy LGTM Stack (GKE)`
3. Click `Run workflow`
4. Select branch: `25-setup-pipeline-for-deploying-terraform-scripts`
5. Choose action: `plan`
6. Click `Run workflow`

**Option B: Via GitHub CLI** 
```bash
gh workflow run deploy-lgtm-gke.yaml \
  --ref 25-setup-pipeline-for-deploying-terraform-scripts \
  -f terraform_action=plan
```

**Option C: Push to Branch (Auto-triggers)**
```bash
# The workflow automatically runs on push
git push origin 25-setup-pipeline-for-deploying-terraform-scripts
```

### 5. Monitor Workflow

```bash
# Watch workflow status
gh run watch

# Or view in browser
# Go to: Actions → Deploy LGTM Stack (GKE) → Latest run
```

### 6. Check Results

After workflow completes:
1. View workflow logs in GitHub Actions tab
2. Download artifacts:
   - `import-report.json` - Resource import results
   - `plan.txt` - Terraform plan output  
   - `tfplan` - Terraform plan binary

### Workflow Jobs

The workflow runs these jobs in order:

1. **setup-environment** - Validates GKE access
2. **import-existing-resources** - Imports existing K8s resources
3. **terraform-plan** - Generates Terraform plan
4. **terraform-apply** - Applies changes (only on `main` or if action=apply)
5. **verify-deployment** - Runs smoke tests (only after apply)

In plan mode (default), only jobs 1-3 run.

## Troubleshooting

### "Invalid base64" Error
```bash
# Make sure no line breaks in base64
cat ~/.kube/config | base64 -w 0 > kubeconfig.b64
```

### "Permission Denied" on GCS
```bash
# Check service account has storage.admin role
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:<SA-EMAIL>" \
  --role="roles/storage.admin"
```

### "Cluster Not Found"
```bash
# Verify cluster exists
gcloud container clusters list --project=$PROJECT_ID

# Get current credentials
gcloud container clusters get-credentials <cluster-name> \
  --region=<region> --project=$PROJECT_ID
```

## Next Steps After Plan

If the plan looks good:

1. **Manual Apply:**
   - Trigger workflow again with `terraform_action=apply`

2. **Auto Apply:**
   - Merge to `main` branch
   - Workflow auto-applies on main

3. **Review Plan:**
   - Check `plan.txt` artifact
   - Review import report for conflicts
