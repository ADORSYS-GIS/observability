# ArgoCD Agent - Deployment Guide

Complete instructions for deploying hub-and-spoke multi-cluster GitOps with Terraform or shell scripts.

## Prerequisites

| Requirement | Version | Purpose |
|-------------|---------|---------|
| Terraform | >= 1.0 | Infrastructure automation |
| kubectl | Latest | Cluster access |
| Kubernetes | 1.24-1.28 | Hub and spoke clusters |
| argocd-agentctl | v0.5.3 | PKI management (scripts only) |

**Network requirements**:
- Spoke clusters must reach hub Principal on port 443
- Firewall rules allowing gRPC traffic

**Cluster access**:
```bash
kubectl config get-contexts
```

---

## Deployment Option 1: Terraform (Recommended)

### Step 1: Prepare Configuration

```bash
cd argocd-agent/terraform/environments/prod
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your settings. See **[Configuration Reference](argocd-agent-configuration.md)** for all options.

**Minimal configuration** (development):
```hcl
hub_cluster_context = "gke_project_region_hub"
workload_clusters = {
  "agent-1" = "gke_project_region_spoke1"
}
```

**Production configuration** - see [Configuration Guide](argocd-agent-configuration.md#production-ingress--sso--ha) for complete example with:
- Ingress exposure
- Keycloak SSO
- High availability
- Existing infrastructure integration

### Step 2: Deploy

```bash
terraform init
terraform plan
terraform apply
```

Deployment takes ~10-15 minutes.

### Step 3: Access ArgoCD

```bash
# Get URL
terraform output argocd_url

# Get initial password
kubectl --context=<hub> -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
```

---

## Configuration Options

**For complete variable reference, see [Configuration Guide](argocd-agent-configuration.md)**.

Key configuration areas:
- **[Exposure methods](argocd-agent-configuration.md#exposure-configuration)** - LoadBalancer vs Ingress
- **[Keycloak SSO](argocd-agent-configuration.md#sso-with-keycloak)** - OIDC authentication
- **[High availability](argocd-agent-configuration.md#high-availability)** - Principal replicas
- **[Deployment modes](argocd-agent-configuration.md#deployment-control)** - Hub-only, spokes-only, or full

---

## Verification

**Hub cluster**:
```bash
export HUB_CTX="your-hub-context"

# Check pods
kubectl --context=$HUB_CTX get pods -n argocd

# Expected: argocd-server, argocd-agent-principal, argocd-repo-server, argocd-redis
# NOT expected: argocd-application-controller (runs on spokes)

# Check Principal
kubectl --context=$HUB_CTX logs -n argocd -l app.kubernetes.io/name=argocd-agent-principal
```

**Spoke cluster**:
```bash
export SPOKE_CTX="your-spoke-context"

# Check pods
kubectl --context=$SPOKE_CTX get pods -n argocd

# Expected: argocd-agent, argocd-application-controller, argocd-repo-server, argocd-redis

# Check agent connectivity
kubectl --context=$SPOKE_CTX logs -n argocd -l app.kubernetes.io/name=argocd-agent | grep "connected"
```

**End-to-end test**:
```bash
# Create test app on hub
kubectl --context=$HUB_CTX apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: test
  namespace: agent-1
spec:
  project: default
  source:
    repoURL: https://github.com/argoproj/argocd-example-apps
    path: guestbook
    targetRevision: HEAD
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated: {}
EOF

# Wait for sync
kubectl --context=$HUB_CTX wait --for=jsonpath='{.status.sync.status}'=Synced \
  app/test -n agent-1 --timeout=300s

# Verify on spoke
kubectl --context=$SPOKE_CTX get deploy -n default guestbook-ui

# Cleanup
kubectl --context=$HUB_CTX delete app test -n agent-1
```

---

## Deployment Option 2: Shell Scripts

### Prerequisites

Download `argocd-agentctl`:
```bash
cd argocd-agent/scripts
VERSION=v0.5.3
curl -LO https://github.com/argoproj-labs/argocd-agent/releases/download/${VERSION}/argocd-agentctl-linux-amd64
mv argocd-agentctl-linux-amd64 argocd-agentctl
chmod +x argocd-agentctl
```

### Deployment Steps

| Script | Purpose | Usage |
|--------|---------|-------|
| `01-hub-setup.sh` | Install ArgoCD hub (UI + control plane) | `HUB_CTX=<ctx> ./01-hub-setup.sh` |
| `02-hub-pki-principal.sh` | PKI setup + deploy Principal | `HUB_CTX=<ctx> ./02-hub-pki-principal.sh agent-1` |
| `03-spoke-setup.sh` | Install ArgoCD on spoke | `./03-spoke-setup.sh <spoke-ctx>` |
| `04-agent-connect.sh` | Connect agent to principal | `HUB_CTX=<ctx> ./04-agent-connect.sh agent-1 <spoke-ctx>` |
| `05-verify.sh` | Test end-to-end deployment | `HUB_CTX=<ctx> ./05-verify.sh agent-1 <spoke-ctx>` |

**Full deployment**:
```bash
cd argocd-agent/scripts

export HUB_CTX=gke_project_region_hub
export SPOKE_CTX=gke_project_region_spoke1

# Deploy hub
HUB_CTX=$HUB_CTX ./01-hub-setup.sh
HUB_CTX=$HUB_CTX ./02-hub-pki-principal.sh agent-1

# Deploy spoke
./03-spoke-setup.sh $SPOKE_CTX
HUB_CTX=$HUB_CTX ./04-agent-connect.sh agent-1 $SPOKE_CTX

# Verify
HUB_CTX=$HUB_CTX ./05-verify.sh agent-1 $SPOKE_CTX
```

### Add Additional Spokes

```bash
# Add agent-2
HUB_CTX=$HUB_CTX ./02-hub-pki-principal.sh agent-1,agent-2  # Update allowed namespaces

./03-spoke-setup.sh $SPOKE2_CTX
HUB_CTX=$HUB_CTX ./04-agent-connect.sh agent-2 $SPOKE2_CTX
HUB_CTX=$HUB_CTX ./05-verify.sh agent-2 $SPOKE2_CTX
```

### Script Details

**01-hub-setup.sh**:
- Creates `argocd` namespace
- Installs ArgoCD Principal profile (no application-controller)
- Enables apps-in-any-namespace
- Exposes UI via LoadBalancer

**02-hub-pki-principal.sh**:
- Initializes PKI CA
- Issues Principal certificates (gRPC + resource-proxy)
- Creates JWT signing key
- Deploys and exposes Principal
- Configures allowed agent namespaces

**03-spoke-setup.sh**:
- Creates `argocd` namespace
- Installs ArgoCD agent-managed profile
- Patches Redis for k3s compatibility (if detected)
- Waits for all components

**04-agent-connect.sh**:
- Creates agent configuration on hub
- Issues agent client certificates
- Propagates CA to spoke
- Deploys agent on spoke
- Configures agent connection to Principal

**05-verify.sh**:
- Creates test guestbook application
- Verifies sync on hub and spoke
- Shows deployed resources

---

## Post-Deployment

### DNS Configuration (LoadBalancer)

```bash
# Get IPs
kubectl --context=$HUB_CTX get svc -n argocd argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
kubectl --context=$HUB_CTX get svc -n argocd argocd-agent-principal -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

Create DNS A records:
- `argocd.example.com` → UI IP
- `principal.example.com` → Principal IP

### Backup PKI CA

Critical for disaster recovery:
```bash
kubectl --context=$HUB_CTX get secret argocd-agent-ca -n argocd -o yaml > pki-ca-backup.yaml
```

Store securely offline.

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| LoadBalancer stuck pending | Check cloud provider quotas: `kubectl describe svc -n argocd` |
| Agent can't connect | Verify network: `kubectl --context=$SPOKE_CTX run -it --rm debug --image=curlimages/curl -- curl -v https://PRINCIPAL_IP:443` |
| Apps stuck "Unknown" | Delete agent pods: `kubectl --context=$SPOKE_CTX delete pod -l app.kubernetes.io/name=argocd-agent -n argocd` |
| Certificate errors | Re-run `04-agent-connect.sh` to regenerate certs |

See [Troubleshooting guide](argocd-agent-troubleshooting.md) for complete solutions.

---

## Next Steps

- **[Operations Guide](argocd-agent-operations.md)** - Scaling, upgrades, monitoring
- **[RBAC & SSO](argocd-agent-rbac.md)** - Keycloak integration
- **[Troubleshooting](argocd-agent-troubleshooting.md)** - Common issues
