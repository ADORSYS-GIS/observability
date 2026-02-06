# ArgoCD Agent GitHub Actions Deployment

Automated hub-and-spoke multi-cluster GitOps deployment using GitHub Actions CI/CD workflows.

**Official Documentation**: [argocd-agent.readthedocs.io](https://argocd-agent.readthedocs.io/) | **GitHub Repository**: [argoproj-labs/argocd-agent](https://github.com/argoproj-labs/argocd-agent) | **Version**: `v0.5.3`

> **Already have ArgoCD Agent installed?** See [Adopting Existing Installation](adopting-argocd-agent.md).

---

## Overview

GitHub Actions workflows automatically deploy ArgoCD Agent using Terraform. Hub cluster runs ArgoCD UI + Principal, spoke clusters run agents connecting via mTLS.

**Features:** Hub-spoke architecture, multi-cloud support (GKE/EKS/Generic), automated Terraform backend, NetBird VPN integration, mTLS security.

---

## Deployment Modes Index

| Deployment Mode | Folder/Path | Quick Start (Plan) | Prerequisites | Required Secrets | Guide/Validation |
|:---|:---|:---|:---|:---|:---|
| **GKE** | `argocd-agent/terraform/environments/prod` | `Run GKE Workflow` | GCP Project, GCS Bucket | `GCP_CREDENTIALS`, `GCP_PROJECT_ID` | [GKE Guide](#gke-google-kubernetes-engine) |
| **EKS** | `argocd-agent/terraform/environments/prod` | `Run EKS Workflow` | AWS IAM Role, S3 Bucket | `AWS_ROLE_ARN`, `REGION` | [EKS Guide](#eks-amazon-elastic-kubernetes-service) |
| **Generic** | `argocd-agent/terraform/environments/prod` | `Run Generic Workflow` | Kubeconfigs (Hub+Spokes) | `KUBECONFIG_CONTENT`, `ARGOCD_URL` | [Generic Guide](#generic-kubernetes--on-premises) |
| **Manual** | `argocd-agent/scripts/` | `bash scripts/01-hub-setup.sh` | Local kubectl access | Local kubeconfig, Helm | [Manual Guide](argocd-agent-terraform-deployment.md#manual-deployment-scripts) |

---

## Prerequisites

- **Clusters**: Hub + spoke clusters (Kubernetes ≥1.24) with admin access
- **GitHub**: Repo with Actions enabled
- **Cloud**: GCP service account / AWS IAM role / kubeconfig
- **Storage**: GCS/S3 bucket for Terraform state
- **Network**: Spokes reach hub LoadBalancer on port 443 (or use NetBird VPN)

---

## Setup

### Step 1: Configure GitHub Secrets

Navigate to repository **Settings → Secrets and variables → Actions → New repository secret**

#### GKE (Google Kubernetes Engine)

| Secret Name | Description | Example |
|-------------|-------------|---------|
| `GCP_CREDENTIALS` | Base64-encoded service account JSON key | `{"type":"service_account",...}` |
| `GCP_PROJECT_ID` | GCP project ID | `my-project-123456` |
| `CLUSTER_NAME` | GKE hub cluster name | `observe-prod-cluster` |
| `REGION` | GKE cluster zone or region | `europe-west3` or `europe-west3-a` |
| `TF_STATE_BUCKET_ARGOCD` | GCS bucket for Terraform state | `my-terraform-state-bucket` |
| `PASSWORD` | ArgoCD admin password | `SuperSecure123!` |
| `ARGOCD_HOST` | ArgoCD ingress hostname | `argocd.example.com` |
| `LETSENCRYPT_EMAIL_ARGOCD` | Email for Let's Encrypt | `admin@example.com` |
| `KUBECONFIG_DATA` | Base64-encoded kubeconfig for spoke clusters | See below |
| `WORKLOAD_CLUSTERS_JSON` | JSON map of spoke clusters | `{"agent-1":"spoke-1","agent-2":"spoke-2"}` |
| `NETBIRD_SETUP_KEY` | NetBird VPN setup key (only for local/private clusters) | Get from [netbird.io](https://netbird.io) Dashboard → Setup Keys |

**Optional Keycloak SSO Secrets:**
| Secret Name | Description |
|-------------|-------------|
| `KEYCLOAK_URL` | Keycloak server URL | `https://keycloak.example.com` |
| `KEYCLOAK_CLIENT_ID` | OAuth2 client ID | `argocd` |
| `KEYCLOAK_PASSWORD` | Keycloak admin password | |

**Create GCP Service Account:**
```bash
# Create service account
gcloud iam service-accounts create argocd-deployer \
  --display-name="ArgoCD GitHub Actions Deployer"

# Grant Kubernetes admin permissions
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:argocd-deployer@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/container.admin"

# Grant storage permissions for Terraform state
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:argocd-deployer@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/storage.objectAdmin"

# Create and download key
gcloud iam service-accounts keys create key.json \
  --iam-account=argocd-deployer@YOUR_PROJECT_ID.iam.gserviceaccount.com

# Use the JSON content directly for GCP_CREDENTIALS secret
cat key.json
```

**Create KUBECONFIG_DATA (for spoke clusters):**

This secret contains kubeconfig for all spoke clusters merged into a single file. It's **base64-encoded** and used specifically for GKE workflows.

```bash
# Merge existing kubeconfigs from all spoke clusters
KUBECONFIG=~/.kube/spoke-1-config:~/.kube/spoke-2-config kubectl config view --flatten > merged-kubeconfig.yaml

# Base64 encode for GitHub Secret
cat merged-kubeconfig.yaml | base64 -w 0 > kubeconfig-base64.txt
# Copy content of kubeconfig-base64.txt to KUBECONFIG_DATA secret
```

**Note:** `KUBECONFIG_DATA` is base64-encoded and used for GKE workflows only.

**Create WORKLOAD_CLUSTERS_JSON:**

This JSON maps agent names to their kubectl context names:

```json
{
  "agent-1": "spoke-1",
  "agent-2": "spoke-2",
  "agent-3": "aks-production-cluster"
}
```

The agent names (keys) will be used in ArgoCD Application namespaces, and context names (values) must match those in your kubeconfig.

---

#### EKS (Amazon Elastic Kubernetes Service)

| Secret Name | Description |
|-------------|-------------|
| `AWS_ROLE_ARN` | IAM role ARN for GitHub Actions OIDC | `arn:aws:iam::123456789012:role/github-actions` |
| `REGION` | AWS region | `us-west-2` |
| `CLUSTER_NAME` | EKS hub cluster name | `argocd-hub-cluster` |
| `TF_STATE_BUCKET_ARGOCD` | S3 bucket for Terraform state | `my-terraform-state` |
| `PASSWORD` | ArgoCD admin password | |
| `ARGOCD_URL` | ArgoCD base URL | `https://argocd.example.com` |
| `LETSENCRYPT_EMAIL_ARGOCD` | Email for Let's Encrypt | |
| `WORKLOAD_CLUSTERS_JSON` | JSON map of spoke clusters | |

**Optional:** Same Keycloak secrets as GKE

**Configure AWS IAM:**

```bash
# Create IAM role for GitHub Actions OIDC
aws iam create-role --role-name github-actions-argocd \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::YOUR_ACCOUNT:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:sub": "repo:YOUR_ORG/YOUR_REPO:ref:refs/heads/main"
        }
      }
    }]
  }'

# Attach policies
aws iam attach-role-policy \
  --role-name github-actions-argocd \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy

aws iam attach-role-policy \
  --role-name github-actions-argocd \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
```

---

#### Generic Kubernetes / On-Premises

| Secret Name | Description |
|-------------|-------------|
| `KUBECONFIG_CONTENT` | Complete kubeconfig with hub + spoke clusters | |
| `PASSWORD` | ArgoCD admin password | |
| `ARGOCD_URL` | ArgoCD base URL | |
| `LETSENCRYPT_EMAIL_ARGOCD` | Email for Let's Encrypt | |
| `WORKLOAD_CLUSTERS_JSON` | JSON map of spoke clusters | |

**Create KUBECONFIG_CONTENT:**

This secret contains the complete kubeconfig for hub and all spoke clusters. It's **NOT base64-encoded** and used for Generic/EKS workflows.

```bash
# Merge all cluster configs (hub + spokes)
KUBECONFIG=hub-config:spoke1-config:spoke2-config kubectl config view --flatten > complete-kubeconfig.yaml

# Copy entire YAML content to GitHub Secret (no base64 encoding)
cat complete-kubeconfig.yaml
```

**Note:** `KUBECONFIG_CONTENT` is plain YAML (not base64) and used for Generic/EKS workflows.

---

### Step 2: Workflow Overview

**Available Workflows:**
- **GKE**: [`deploy-argocd-agent-gke.yaml`](../.github/workflows/deploy-argocd-agent-gke.yaml) (GCS backend)
- **EKS**: [`deploy-argocd-agent-eks.yaml`](../.github/workflows/deploy-argocd-agent-eks.yaml) (S3 backend)
- **Generic**: [`deploy-argocd-agent-generic.yaml`](../.github/workflows/deploy-argocd-agent-generic.yaml)
- **Destroy**: [`destroy-argocd-agent.yaml`](../.github/workflows/destroy-argocd-agent.yaml)

**Triggers:**
- Push to `main` → `terraform apply` (auto-deploy)
- Pull request / other branches → `terraform plan` (preview only)
- Manual → Choose `plan` or `apply`

---

### Step 3: Deploy ArgoCD Agent

#### Manual Trigger (First Deployment)

1. Go to **Actions** → Select your cloud provider workflow
2. Click **"Run workflow"** → Select `main` branch
3. Choose action: `plan` (preview) or `apply` (deploy)
4. Click **"Run workflow"**

#### Automatic Trigger (Ongoing Updates)

Push changes to `main` branch → workflow auto-runs `terraform apply`

---

### Step 4: Understand Hub-Spoke Configuration

ArgoCD Agent uses a hub-and-spoke architecture where:
- **Hub Cluster**: Runs ArgoCD UI, Principal (gRPC server), and control plane
- **Spoke Clusters**: Run lightweight agents that connect to hub Principal

**WORKLOAD_CLUSTERS_JSON Format:**

This secret defines which spoke clusters to deploy agents to:

```json
{
  "agent-1": "spoke-context-1",
  "agent-2": "gke_project_region_spoke2", 
  "agent-3": "arn:aws:eks:region:account:cluster/spoke3"
}
```

**Key Points:**
- **Keys (agent names)**: Used for agent identification - each agent gets its own namespace on hub
- **Values (contexts)**: Must match kubectl context names in your kubeconfig
- **Namespace auto-creation**: ArgoCD automatically creates a namespace on the hub for each agent (e.g., `agent-1`, `agent-2`)
- **Application routing**: Applications created in the `agent-2` namespace on hub are automatically synced to the spoke cluster associated with agent-2
- **Multiple spokes**: Add as many spoke clusters as needed (tested with 10+)

**How namespace mapping works:**
1. You define agents in `WORKLOAD_CLUSTERS_JSON`: `{"agent-1": "spoke-1", "agent-2": "spoke-2"}`
2. Terraform deploys ArgoCD Agent to each spoke using the context names
3. ArgoCD automatically creates namespaces `agent-1` and `agent-2` on the hub cluster
4. Applications placed in `agent-1` namespace → deployed to `spoke-1` cluster
5. Applications placed in `agent-2` namespace → deployed to `spoke-2` cluster

**Example Deployment Flow:**

1. Create Application on hub cluster:
   ```yaml
   apiVersion: argoproj.io/v1alpha1
   kind: Application
   metadata:
     name: my-app
     namespace: agent-1  # Targets agent-1 spoke cluster
   spec:
     destination:
       server: https://kubernetes.default.svc
       namespace: production
     source:
       repoURL: https://github.com/my-org/my-app
       path: manifests
   ```

2. Hub ArgoCD syncs Application definition
3. Principal sends deployment to agent-1 via gRPC
4. Agent on spoke cluster deploys to `production` namespace
5. Agent reports status back to hub
6. Hub UI shows application health and sync status

**NetBird VPN (Optional - for Local/Private Clusters):**

NetBird is needed when:
- Spoke clusters are **local/private** (GitHub Actions runner cannot reach them directly)
- Spokes are behind NAT/firewalls without public access

**Not needed when:**
- Spoke clusters have **public IPs accessible** by GitHub Actions runners

**Setup:**
Setup key from [netbird.io](https://netbird.io) Dashboard → Setup Keys, add to `NETBIRD_SETUP_KEY` secret. Alternatives: self-hosted NetBird or Tailscale.

---

### Step 5: Verify Deployment

After workflow completes, verify the deployment:

#### Hub Cluster Verification

```bash
kubectl get pods -n argocd --context HUB
kubectl get svc argocd-agent-principal -n argocd --context HUB
```
Verify all pods are `Running` and LoadBalancer has EXTERNAL-IP (may take 5-10 minutes).

#### Spoke Cluster Verification

```bash
# Set spoke context
kubectl config use-context spoke-1

# Check agent pods
kubectl get pods -n argocd
```

**Expected output:**
```
NAME                                       READY   STATUS    RESTARTS   AGE
argocd-agent-agent-867bbf58cd-xxxxx        1/1     Running   0          5m
argocd-application-controller-0            1/1     Running   0          5m
argocd-redis-f6476c79b-xxxxx               1/1     Running   0          5m
argocd-repo-server-77d887cfb9-xxxxx        1/1     Running   0          5m
```

#### Check Agent Connectivity

```bash
# Hub: Check Principal logs for agent connections
kubectl logs -n argocd deployment/argocd-agent-principal --tail=20

# Look for:
# level=info msg="Agent connected" agent=agent-1
# level=info msg="Received update for application" agent=agent-1

# Spoke: Check agent logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-agent-agent --tail=20

# Look for:
# level=info msg="Connected to principal" address=34.107.69.216:443
# level=info msg="Authenticated via mTLS" cn=agent-1
```

#### Check Certificate

```bash
# Verify Principal certificate includes LoadBalancer IP
kubectl get secret argocd-agent-principal-tls -n argocd \
  -o jsonpath='{.data.tls\.crt}' | base64 -d | \
  openssl x509 -noout -text | grep -A5 "Subject Alternative Name"
```

**Expected output:**
```
X509v3 Subject Alternative Name:
    DNS:localhost
    DNS:argocd-agent-principal.argocd.svc.cluster.local
    IP Address:127.0.0.1
    IP Address:34.107.69.216  ✅ LoadBalancer IP
```

---

## Usage

### Deploy Applications to Spoke Clusters

Applications are created on the **hub cluster** and automatically synced to **spoke clusters** by the agent.

**Example 1: Simple Application**

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: guestbook
  namespace: agent-1  # Targets spoke cluster agent-1
spec:
  project: default
  source:
    repoURL: https://github.com/argoproj/argocd-example-apps.git
    targetRevision: HEAD
    path: guestbook
  destination:
    server: https://kubernetes.default.svc
    namespace: guestbook
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
```

Apply to hub cluster:
```bash
kubectl apply -f guestbook-app.yaml --context gke_PROJECT_REGION_HUB
```

Verify on hub:
```bash
kubectl get application guestbook -n agent-1 --context gke_PROJECT_REGION_HUB
```

Verify on spoke:
```bash
kubectl get pods -n guestbook --context spoke-1
```

**Example 2: Helm Application**

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: nginx
  namespace: agent-2  # Targets spoke cluster agent-2
spec:
  project: default
  source:
    repoURL: https://charts.bitnami.com/bitnami
    targetRevision: 15.0.0
    chart: nginx
    helm:
      values: |
        replicaCount: 2
        service:
          type: ClusterIP
  destination:
    server: https://kubernetes.default.svc
    namespace: web
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
```

### Access ArgoCD UI

After deployment, access the ArgoCD UI:

**If using ingress with TLS:**
```
https://argocd.example.com
```

**If using port-forward:**
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:80 --context gke_PROJECT_REGION_HUB
# Access: http://localhost:8080
```

**Get admin password:**
```bash
kubectl get secret argocd-initial-admin-secret -n argocd \
  --context gke_PROJECT_REGION_HUB \
  -o jsonpath='{.data.password}' | base64 -d
```

**Login:**
- Username: `admin`
- Password: (from command above or `PASSWORD` secret)

---


## Managing Spoke Clusters

### Add/Remove Spoke Clusters

**Add a spoke cluster:**

1. Update `WORKLOAD_CLUSTERS_JSON` secret:
   ```json
   {
     "agent-1": "spoke-1",
     "agent-2": "spoke-2",
     "agent-3": "new-spoke-context"  ← Add this
   }
   ```

2. Update `KUBECONFIG_DATA` to include new spoke cluster kubeconfig
3. Run workflow with `apply`

**Remove a spoke cluster:**

1. Update `WORKLOAD_CLUSTERS_JSON` to remove the agent
2. Run workflow with `apply`
3. Manually clean up namespace on hub:
   ```bash
   kubectl delete namespace agent-3 --context gke_PROJECT_REGION_HUB
   ```

---

## Uninstalling

Use the automated destroy workflow:

**Workflow:** [`.github/workflows/destroy-argocd-agent.yaml`](../.github/workflows/destroy-argocd-agent.yaml)

**Steps:**
1. Navigate to **Actions** → **Destroy ArgoCD Agent**
2. Click **"Run workflow"**
3. Select your cloud provider: `gke`, `eks`, or `generic`
4. Type `DESTROY` to confirm
5. Click **"Run workflow"**

The workflow automatically:
- Removes all ArgoCD Agent components from hub and spokes
- Deletes namespaces and certificates
- Cleans up Terraform state

**Manual cleanup (if namespace stuck):**
```bash
kubectl delete namespace argocd --force --grace-period=0
kubectl patch namespace argocd -p '{"metadata":{"finalizers":[]}}' --type=merge
```

---

## Troubleshooting

### Workflow Failures

#### Cannot Connect to Cluster

**Symptom:** Workflow fails with "Unable to connect to the server"

**Causes & Solutions:**

**GKE:**
- Verify `GCP_CREDENTIALS` secret contains valid service account JSON
- Check `CLUSTER_NAME`, `REGION`, and `GCP_PROJECT_ID` are correct
- Ensure service account has `roles/container.admin` permission
- Test locally:
  ```bash
  gcloud container clusters get-credentials CLUSTER_NAME --region REGION
  kubectl get nodes
  ```

**EKS:**
- Verify `AWS_ROLE_ARN` is correct and assumable
- Check IAM role has `eks:DescribeCluster` permission
- Verify `CLUSTER_NAME` and `REGION` match actual cluster

**Generic:**
- Verify `KUBECONFIG_CONTENT` contains valid kubeconfig
- Test contexts locally:
  ```bash
  kubectl config get-contexts
  kubectl get nodes --context=hub-context
  ```

---

#### Terraform Backend Error

**Symptom:** "Error loading state: NoSuchBucket" or similar

**Solution:**
```bash
# GCP: Create bucket
gsutil mb gs://YOUR-TERRAFORM-STATE-BUCKET

# AWS: Create bucket
aws s3 mb s3://YOUR-TERRAFORM-STATE-BUCKET

# Verify bucket name in GitHub Secret matches
```

---

#### LoadBalancer IP Pending

**Symptom:** LoadBalancer shows `<pending>` for >15 minutes

**Solution:** Check cloud provider quotas and events
```bash
kubectl describe svc argocd-agent-principal -n argocd
kubectl get events -n argocd | grep LoadBalancer
```

**Common causes:**
- GCP: Resource quotas exhausted
- AWS: No available IPs in subnet
- Azure: Insufficient permissions

---

#### Let's Encrypt Rate Limit

**Symptom:** Certificate error "429 urn:ietf:params:acme:error:rateLimited"

**Solutions:**
- Use Let's Encrypt staging server for testing
- Wait 7 days for rate limit reset
- Use a different domain/subdomain

---

#### Agent Cannot Connect to Principal

**Symptom:** Agent logs show "connection refused" or "timeout"

**Check:**
```bash
# Verify LoadBalancer has IP
kubectl get svc argocd-agent-principal -n argocd

# Test connectivity from spoke
kubectl run -it --rm debug --image=curlimages/curl --context spoke-1 -- curl -v https://PRINCIPAL_IP:443

# Check agent logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-agent-agent --context spoke-1 --tail=50
```

**Common issues:**
- LoadBalancer IP pending (wait 5-10 minutes)
- NetBird VPN not connected: `sudo netbird status`
- Firewall blocking port 443
- Certificate mismatch

---

#### Application Stuck in "Unknown" Status

**Symptom:** Application shows "Unknown" sync/health status

**Solution:** Restart components on spoke cluster
```bash
# Check pods
kubectl get pods -n argocd --context spoke-1

# Restart repo-server if CrashLooping
kubectl delete pod -l app.kubernetes.io/name=argocd-repo-server -n argocd --context spoke-1

# Restart application-controller
kubectl rollout restart statefulset/argocd-application-controller -n argocd --context spoke-1

# Check agent logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-agent-agent --context spoke-1
```

---

#### NetBird VPN Connection Issues

**Symptom:** Workflow logs show "NetBird connection failed"

**Check:**
- Verify `NETBIRD_SETUP_KEY` is valid and not expired
- Run `sudo netbird status` to check connection
- Ensure UDP port 51820 (WireGuard) is open

**Alternative:** Remove NetBird setup from workflow if spokes can reach hub LoadBalancer directly

---

#### Workflow Hangs During Destroy

**Solution:** Remove namespace finalizers
```bash
kubectl patch namespace argocd -p '{"metadata":{"finalizers":[]}}' --type=merge
```

---

### Quick Debugging Commands

```bash
# Check all resources
kubectl get all -n argocd --context HUB
kubectl get all -n argocd --context SPOKE

# Check certificates
kubectl get certificate,certificaterequest -n argocd

# Export logs
kubectl logs -n argocd deployment/argocd-agent-principal > principal.log
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-agent-agent --context spoke-1 > agent.log

# Terraform state
cd argocd-agent/terraform/environments/prod
terraform state list
```

---


## State Management

Terraform state is stored in cloud storage:

| Provider | Backend | Path |
|----------|---------|------|
| **GKE** | GCS | `gs://BUCKET/terraform/argocd-agent/prod/terraform.tfstate` |
| **EKS** | S3 + DynamoDB | `s3://BUCKET/terraform/argocd-agent/prod/terraform.tfstate` |
| **Generic** | Configurable | Based on backend config |

**Inspect state locally:**
```bash
cd argocd-agent/terraform/environments/prod
export TF_STATE_BUCKET="your-bucket"
bash ../../../../.github/scripts/configure-backend.sh gke argocd-agent
terraform init
terraform state list
```

**Backup state:**
```bash
terraform state pull > backup-$(date +%Y%m%d).tfstate
```

---

## Related Documentation

- [Manual Deployment Guide](argocd-agent-terraform-deployment.md) - Terraform CLI deployment
- [Architecture Guide](argocd-agent-architecture.md) - Hub-spoke architecture explained
- [Configuration Reference](argocd-agent-configuration.md) - All Terraform variables
- [Operations Guide](argocd-agent-operations.md) - Day-2 operations, scaling, monitoring
- [RBAC & SSO](argocd-agent-rbac.md) - Keycloak integration details
- [Troubleshooting Guide](argocd-agent-troubleshooting.md) - Comprehensive troubleshooting
- [Official ArgoCD Agent Docs](https://argocd-agent.readthedocs.io/) - Upstream documentation

---
