# Multi-Cloud LGTM Stack Deployment Workflows

## Available Workflows

### 1. GKE Deployment - `deploy-lgtm-gke.yaml`
**Status:** ✅ Tested and Working

**Required Secrets:**
- `GCP_PROJECT_ID`
- `GCP_SA_KEY`
- `TF_STATE_BUCKET`
- `CLUSTER_NAME`
- `CLUSTER_LOCATION`
- `REGION`
- `ENVIRONMENT` (or use "production")
- `MONITORING_DOMAIN`
- `LETSENCRYPT_EMAIL`
- `GRAFANA_ADMIN_PASSWORD`

**How to Use:**
```bash
# Via GitHub Actions UI
Actions → Deploy LGTM Stack (GKE) → Run workflow → Select "apply"

# Or push to trigger
git push origin main  # Auto-applies
git push origin 25-setup-pipeline-for-deploying-terraform-scripts  # Test branch also applies
```

---

### 2. EKS Deployment - `deploy-lgtm-eks.yaml`
**Status:** ✅ Ready (Requires AWS EKS cluster)

**Required Secrets:**
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_REGION`
- `TF_STATE_BUCKET` (S3 bucket name)
- `CLUSTER_NAME`
- `EKS_OIDC_PROVIDER_ARN`
- `MONITORING_DOMAIN`
- `LETSENCRYPT_EMAIL`
- `GRAFANA_ADMIN_PASSWORD`

**Setup:**
1. Create EKS cluster
2. Get OIDC provider ARN:
   ```bash
   aws eks describe-cluster --name <cluster-name> \
     --query "cluster.identity.oidc.issuer" --output text
   ```
3. Create S3 bucket for Terraform state
4. Configure GitHub secrets
5. Run workflow

---

### 3. Generic K8s - `deploy-lgtm-generic.yaml`
**Status:** ✅ Ready (Any Kubernetes cluster)

**Required Secrets:**
- `KUBECONFIG` (base64-encoded)
- `CLUSTER_NAME`
- `MONITORING_DOMAIN`
- `LETSENCRYPT_EMAIL`
- `GRAFANA_ADMIN_PASSWORD`

**Use Cases:**
- Minikube
- Kind
- On-premise Kubernetes
- Managed K8s without cloud integration

**Setup:**
```bash
# Encode kubeconfig
cat ~/.kube/config | base64 -w 0

# Add to GitHub secrets as KUBECONFIG
```

---

### 4. Destroy Stack - `destroy-lgtm-stack.yaml`
**Status:** ✅ Updated with gcloud authentication

**How to Use:**
1. Go to Actions → Destroy LGTM Stack
2. Select cloud provider (gke/eks/aks/generic)
3. Choose whether to delete storage buckets
4. Type "DESTROY" to confirm
5. Run workflow

---

## Workflow Features

All workflows include:

✅ **setup-environment** - Authenticates and validates cluster access
✅ **import-existing-resources** - Imports existing K8s resources to avoid conflicts  
✅ **terraform-plan** - Generates execution plan (always runs)
✅ **terraform-apply** - Deploys LGTM stack (only on main or manual apply)
✅ **verify-deployment** - Runs smoke tests and verification (after apply)

## Testing on Non-Main Branch

The GKE workflow is configured to allow **apply** on the test branch:
- `25-setup-pipeline-for-deploying-terraform-scripts`

This allows full testing before merging to main.

## Artifacts Generated

Each workflow run produces:
- **import-report.json** - Resource import results
- **plan.txt** - Human-readable Terraform plan
- **tfplan** - Binary Terraform plan file
- **terraform-outputs.json** - Deployment outputs (after apply)
- **verification-report.html** - Deployment health check
- **smoke-test-results.json** - Component test results

## Next Steps

1. **Test GKE Apply** - Workflow is ready to apply on your test branch
2. **Test Destroy** - After apply completes, test destroy workflow
3. **Configure EKS** - If you have AWS, set up EKS workflow
4. **Configure Generic** - For other K8s clusters
5. **Merge to Main** - After testing, merge to enable production deployments
