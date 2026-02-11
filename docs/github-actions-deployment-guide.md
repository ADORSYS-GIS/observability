# GitHub Actions Deployment Guide

Complete guide for using the GitHub Actions workflows to deploy ArgoCD Agent in hub-spoke architecture with Netbird connectivity.

> [!IMPORTANT]
> **Prerequisites**: Complete [Netbird Setup Guide](netbird-setup-guide.md) before using these workflows. Spoke clusters must already be in the Netbird network.

## Overview

Two workflows automate the deployment:

1. **`deploy-argocd-hub-gke.yaml`** - Deploy ArgoCD hub cluster to GKE
2. **`deploy-argocd-spokes-netbird.yaml`** - Deploy ArgoCD agents to local spoke clusters via Netbird

---

## Prerequisites Checklist

Before running workflows, ensure:

- [ ] ✅ Netbird account created
- [ ] ✅ Spoke clusters installed Netbird and registered (persistent peers)
- [ ] ✅ GitHub runners setup key created (ephemeral)
- [ ] ✅ ACLs configured (`github-runners` → `spoke-clusters`, TCP port 6443)
- [ ] ✅ GKE cluster exists for hub deployment
- [ ] ✅ All GitHub Secrets configured (see [Netbird Setup Guide](netbird-setup-guide.md#6-github-secrets-configuration))

---

## Deployment Workflow

### Step 1: Deploy Hub Cluster to GKE

The hub cluster runs the ArgoCD control plane and Agent Principal.

#### Trigger Workflow

1. Navigate to **GitHub repository → Actions**
2. Select workflow: **Deploy ArgoCD Hub (GKE)**
3. Click **"Run workflow"**
4. Configure inputs:
   - **Branch**: `main`
   - **Terraform Action**: `plan` *(first run to preview changes)*
   - **Adopt existing resources**: `false` *(set `true` if importing existing ArgoCD)*
5. Click **"Run workflow"**

#### Review Plan

1. Wait for workflow completion (~2-3 minutes)
2. Click on the workflow run
3. Open **"Terraform Plan"** job
4. Review the **"Terraform Plan"** step output
5. Check plan artifacts:
   - Download `tfplan-argocd-hub-gke` artifact
   - Review `plan.txt` for human-readable changes

#### Apply Changes

1. Return to **Actions → Deploy ArgoCD Hub (GKE)**
2. Click **"Run workflow"** again
3. Configure inputs:
   - **Terraform Action**: `apply` *(executes the plan)*
   - **Adopt existing resources**: *(same as plan)*
4. Click **"Run workflow"**
5. **Approval**: If environment protection is enabled, approve the deployment
6. Wait for completion (~5-10 minutes)

#### Extract Outputs

After successful deployment:

1. Open the workflow run
2. Go to **"Terraform Apply & Verify"** job
3. Scroll to **"Verify ArgoCD Hub deployment"** step
4. Find the deployment summary with:
   - **Principal Address**: External IP or hostname
   - **Principal Port**: Usually `443`
   - **ArgoCD UI URL**: For accessing the dashboard

**Example output**:
```
📊 Deployment Summary:
{
  "argocd_url": "https://argocd.example.com",
  "principal_address": "34.123.45.67",
  "principal_port": 443,
  ...
}
```

5. **Download Terraform outputs**:
   - Scroll to bottom of workflow run
   - Download artifact: `terraform-outputs-argocd-hub-gke`
   - Open `terraform-outputs.json`

#### Update GitHub Secrets

**CRITICAL**: Store principal address for spoke deployment:

1. Navigate to **Settings → Secrets → Actions**
2. Create or update secrets:
   - **Name**: `HUB_PRINCIPAL_ADDRESS`
   - **Value**: `34.123.45.67` *(from outputs above)*
   - **Name**: `HUB_PRINCIPAL_PORT`
   - **Value**: `443` *(or custom port if changed)*

3. If using Ingress for ArgoCD UI:
   - **Name**: `ARGOCD_URL`
   - **Value**: `https://argocd.example.com`

---

### Step 2: Backup PKI CA Certificate

**CRITICAL SECURITY STEP**:

```bash
# Connect to hub cluster
gcloud container clusters get-credentials <HUB_CLUSTER_NAME> \
  --region=<HUB_CLUSTER_LOCATION> \
  --project=<GCP_PROJECT_ID>

# Backup PKI CA
kubectl get secret argocd-agent-ca -n argocd -o yaml > pki-ca-backup-$(date +%Y%m%d).yaml

# Store securely! This certificate is needed for agent authentication
```

---

###Step 3: Deploy Spoke Clusters via Netbird

Deploy ArgoCD agents to local Kubernetes clusters.

#### Trigger Workflow

1. Navigate to **GitHub repository → Actions**
2. Select workflow: **Deploy ArgoCD Spokes (Netbird)**
3. Click **"Run workflow"**
4. Configure inputs:
   - **Branch**: `main`
   - **Terraform Action**: `plan`
   - **Adopt existing resources**: `false`
5. Click **"Run workflow"**

#### Monitor Netbird Connection

1. Open the workflow run
2. Check **"Connect to Netbird"** step
3. Verify connection successful:
   ```
   ✅ Connected to Netbird network
   ```

4. Check **"Verify Netbird connection"** step
5. Confirm spoke clusters reachable:
   ```
   Testing connectivity to 100.64.1.10...
   ✅ Reachable: 100.64.1.10
   ```

#### Review Plan

1. Review **"Terraform Plan"** step
2. Verify resources to be created:
   - Namespaces on spoke clusters
   - ArgoCD Helm releases
   - Agent configurations
   - mTLS certificates

#### Apply Changes

1. Run workflow again with **Terraform Action**: `apply`
2. Wait for deployment (~10-15 minutes)
   - Netbird connection
   - Terraform apply
   - Agent deployment
   - Certificate issuance
   - Connectivity verification

#### Verify Agent Connectivity

Check the **"Verify ArgoCD Spoke deployment"** step:

```
═══════════════════════════════════════════════════════════
Verifying spoke-1...
═══════════════════════════════════════════════════════════
1. Checking namespace...
   ✅ Namespace exists
2. Checking ArgoCD pods...
   ✅ All pods ready
3. Checking agent connection...
   ✅ Agent connected to principal
4. Checking certificates...
   ✅ Client certificate exists
   ✅ CA certificate exists

📊 Verification Summary
══════════════════════════════════════════════════════════════
✅ Successfully connected: 3
❌ Failed connections: 0

✅ All spoke clusters deployed and connected successfully!
```

---

## Using the Import Mechanism

### When to Use

Use `adopt_existing_resources=true` when:
- You have manually deployed ArgoCD already
- Previous Terraform state was lost
- You want to bring existing resources under Terraform management

### Hub Cluster Import

1. Run workflow with **Adopt existing resources**: `true`
2. Workflow will import:
   - ArgoCD namespace
   - Helm releases
   - Visible resources

3. Resources NOT imported (handled automatically):
   - `null_resource` (PKI operations, configurations)
   - These re-run idempotently

**Example import output**:
```
════════════════════════════════════════════════════════════════
Checking for existing ArgoCD resources to import...
════════════════════════════════════════════════════════════════
✓ Found existing argocd namespace
Importing into Terraform state...
Successfully imported kubernetes_namespace.hub_argocd
✓ Found existing ArgoCD Helm release
════════════════════════════════════════════════════════════════
Import check complete! Proceeding with Terraform operations...
════════════════════════════════════════════════════════════════
```

### Spoke Cluster Import

Similar process for spoke clusters:
- Set **Adopt existing resources**: `true`
- Workflow checks each spoke cluster
- Imports namespaces and visible resources
- Agent resources handled idempotently

---

## Workflow Secrets Reference

### Complete Secrets List

#### Netbird
| Secret | Required | Example | Description |
|--------|----------|---------|-------------|
| `NETBIRD_SETUP_KEY_RUNNERS` | Yes | `nb_...` | Ephemeral key for runners |

#### GCP / Hub Cluster
| Secret | Required | Example | Description |
|--------|----------|---------|-------------|
| `GCP_SA_KEY` | Yes | `{"type": "service_account"...}` | Service account JSON |
| `GCP_PROJECT_ID` | Yes | `my-project` | GCP project ID |
| `HUB_CLUSTER_NAME` | Yes | `argocd-hub` | GKE cluster name |
| `HUB_CLUSTER_LOCATION` | Yes | `us-central1` | GKE region |
| `TF_STATE_BUCKET` | Yes | `my-tf-state` | GCS bucket |
| `ARGOCD_HOST` | If using Ingress | `argocd.example.com` | UI hostname |
| `LETSENCRYPT_EMAIL` | If cert-manager | `admin@example.com` | Cert notifications |
| `KEYCLOAK_URL` | If SSO | `https://keycloak.example.com` | Keycloak URL |

#### Spoke Clusters
| Secret | Required | Example | Description |
|--------|----------|---------|-------------|
| `SPOKE_CLUSTERS` | Yes | `spoke-1,spoke-2,spoke-3` | Comma-separated list |
| `HUB_PRINCIPAL_ADDRESS` | Yes | `34.123.45.67` | From hub outputs |
| `HUB_PRINCIPAL_PORT` | No (default 443) | `443` | Principal port |

#### Per-Spoke Secrets (repeat for each)
| Secret | Required | Example | Description |
|--------|----------|---------|-------------|
| `SPOKE_1_NETBIRD_IP` | Yes | `100.64.1.10` | Netbird IP |
| `SPOKE_1_CA_CERT` | Yes | `LS0tLS1...` | K8s CA (base64) |
| `SPOKE_1_CLIENT_CERT` | Yes | `LS0tLS1...` | Client cert (base64) |
| `SPOKE_1_CLIENT_KEY` | Yes | `LS0tLS1...` | Client key (base64) |

### How to Generate Secret Values

See [Netbird Setup Guide - Section 5](netbird-setup-guide.md#5-extracting-spoke-cluster-netbird-ips) for detailed instructions on extracting Netbird IPs and Kubernetes credentials.

---

## Troubleshooting Workflows

### Hub Deployment Failures

#### Problem: Terraform plan fails with authentication error

**Cause**: GCP credentials invalid or insufficient permissions

**Solution**:
```bash
# Verify service account has required roles:
# - Kubernetes Engine Admin
# - Compute Viewer (for cluster info)
# - Storage Admin (for state bucket)

# Test credentials locally
gcloud auth activate-service-account --key-file=<SA_KEY_FILE>
gcloud container clusters list --project=<PROJECT_ID>
```

#### Problem: Principal LoadBalancer IP not allocated

**Cause**: GKE cluster quota or regional limits

**Solution**:
1. Check GCP quotas for external IPs
2. Consider using Ingress instead:
   - Set GitHub Variable: `PRINCIPAL_EXPOSE_METHOD=ingress`
   - Requires cert-manager and nginx-ingress

#### Problem: Helm release already exists

**Cause**: ArgoCD previously installed

**Solution**:
- Re-run workflow with **Adopt existing resources**: `true`
- Or manually delete: `helm uninstall argocd -n argocd`

### Spoke Deployment Failures

#### Problem: Cannot connect to Netbird

**Cause**: Invalid setup key or Netbird service down

**Solution**:
1. Verify `NETBIRD_SETUP_KEY_RUNNERS` secret is valid
2. Check setup key expiry in Netbird dashboard
3. Create new key if expired
4. Verify Netbird management service status

#### Problem: Cannot reach spoke cluster via Netbird

**Cause**: Spoke not in Netbird or ACL blocking

**Solution**:
1. Check Netbird dashboard → Peers
2. Verify spoke cluster appears with "Connected" status
3. Check ACL rules allow `github-runners` → `spoke-clusters`
4. Test manually from Netbird peer:
   ```bash
   ping <SPOKE_NETBIRD_IP>
   curl -k https://<SPOKE_NETBIRD_IP>:6443/version
   ```

#### Problem: Agent connection verification fails

**Cause**: Principal address incorrect or network issues

**Solution**:
1. Verify `HUB_PRINCIPAL_ADDRESS` secret matches hub deployment output
2. Check principal service status:
   ```bash
   kubectl get svc argocd-agent-principal -n argocd
   ```
3. Review agent logs on spoke:
   ```bash
   kubectl logs -l app.kubernetes.io/name=argocd-agent-agent -n argocd --tail=100
   ```

#### Problem: Certificate generation fails

**Cause**: PKI not initialized on hub or network issues

**Solution**:
1. Verify hub deployment completed successfully
2. Check PKI CA secret exists on hub:
   ```bash
   kubectl get secret argocd-agent-ca -n argocd
   ```
3. Ensure hub cluster context accessible from workflow

### Common Terraform State Issues

#### Problem: State lock error

**Cause**: Previous run didn't complete cleanly

**Solution**:
```bash
# Manually release lock (use with caution!)
# Download state from GCS
gsutil cp gs://<TF_STATE_BUCKET>/terraform/argocd-hub/default.tflock /tmp/

# Delete lock file
gsutil rm gs://<TF_STATE_BUCKET>/terraform/argocd-hub/default.tflock

# Or wait ~10 minutes for auto-release
```

#### Problem: Resource already exists in state

**Cause**: Running import when resources already managed

**Solution**:
- Run without **Adopt existing resources**
- Or manually remove from state:
  ```bash
  terraform state rm <RESOURCE_ADDRESS>
  ```

---

## Manual Verification

After workflows complete, verify end-to-end functionality:

### 1. Access ArgoCD UI

```bash
# Get UI URL from hub deployment outputs
# Or if using Ingress:
open https://argocd.example.com

# Login with admin credentials
# Default: admin / <auto-generated password>

# Get password:
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 -d
```

### 2. Verify Spoke Clusters Registered

1. Navigate to **Settings → Clusters**
2. Verify spoke clusters appear:
   - `spoke-1`
   - `spoke-2`
   - `spoke-3`
3. Check status: **Connected** (green)

### 3. Deploy Test Application

1. Click **+ New App**
2. Configure:
   - **Application Name**: `guestbook-test`
   - **Project**: `default`
   - **SYNC POLICY**: `Automatic`
   - **Repository URL**: `https://github.com/argoproj/argocd-example-apps`
   - **Revision**: `HEAD`
   - **Path**: `guestbook`
   - **Cluster**: Select `spoke-1`
   - **Namespace**: `default`
3. Click **Create**
4. Wait for sync (~1-2 minutes)
5. Verify status: **Healthy** and **Synced**

### 4. Verify on Spoke Cluster

```bash
# Via Netbird (join network first)
netbird up --setup-key <NETBIRD_SETUP_KEY_RUNNERS>

# Configure kubectl
kubectl config set-cluster spoke-1 \
  --server=https://<SPOKE_NETBIRD_IP>:6443 \
  --certificate-authority=<CA_CERT_FILE>

# Check deployments
kubectl get all -n default --context spoke-1

# Expected: guestbook deployment, service, pods running
```

---

## Next Steps

After successful deployment:

1. **Configure Applications**: Create apps in ArgoCD UI targeting spoke clusters
2. **Set up Git repositories**: Connect your application repositories
3. **Configure RBAC**: Set up user access controls (or integrate with Keycloak)
4. **Monitor Agents**: Check agent logs and connectivity regularly
5. **Backup**: Schedule regular backups of:
   - PKI CA certificates
   - ArgoCD configuration
   - Terraform state (already in GCS)

---

## Additional Resources

- [ArgoCD Agent Documentation](https://argo-cd.readthedocs.io/en/stable/operator-manual/agent/)
- [Netbird Documentation](https://docs.netbird.io/)
- [Implementation Plan](file:///home/usherking/.gemini/antigravity/brain/205de3d0-d0ba-45e5-847c-68fad0f13eb7/implementation_plan.md)
