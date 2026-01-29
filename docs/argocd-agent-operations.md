# ArgoCD Agent - Operations Guide

Production operations for ArgoCD Hub-and-Spoke architecture including scaling, upgrades, monitoring, certificate management, and teardown procedures.

---

## Scaling Operations

### Adding a New Spoke Cluster

**Prerequisites**: kubectl access, spoke can reach hub on port 443, cluster context configured

**Steps**:

1. **Update `terraform.tfvars`**:
```hcl
workload_clusters = {
  "agent-1" = "context-1"
  "agent-2" = "context-2"
  "agent-3" = "new-context-3"  # ADD NEW SPOKE
}
```

2. **Deploy**:
```bash
cd argocd-agent/terraform/environments/prod
terraform plan
terraform apply
```

3. **Verify** (~5 minutes):
```bash
export SPOKE_CTX="new-context-3"
kubectl --context=$SPOKE_CTX logs -n argocd -l app.kubernetes.io/name=argocd-agent --tail=50 | grep "connected to principal"
```

**Duration**: ~5-10 minutes | **Impact**: None on existing spokes

---

### Removing a Spoke Cluster

**Warning**: Removes agent but NOT applications running on spoke.

**Steps**:

1. **Delete Applications First** (recommended):
```bash
kubectl --context=$HUB_CTX get applications -n agent-3
kubectl --context=$HUB_CTX delete application <app-name> -n agent-3
```

2. **Update `terraform.tfvars`**:
```hcl
workload_clusters = {
  "agent-1" = "context-1"
  "agent-2" = "context-2"
  # agent-3 removed
}
```

3. **Apply**:
```bash
terraform apply
```

---

### Scaling Hub for More Spokes

**When to Scale**: > 10 spokes, Principal CPU/memory > 80%, increasing sync latency

**Horizontal Scaling**:
```hcl
principal_replicas = 2  # or 3 for higher availability
```

**Capacity Guidelines**:

| Spokes | Hub vCPU | Hub Memory | Principal Replicas |
|--------|----------|------------|-------------------|
| 1-5    | 2        | 4 GB       | 1                 |
| 6-10   | 2        | 4 GB       | 2                 |
| 11-20  | 4        | 8 GB       | 2                 |
| 21-50  | 8        | 16 GB      | 3                 |
| 50+    | 16+      | 32+ GB     | 3+                |

---

## Upgrade Procedures

### Upgrading ArgoCD Version

**Planning**:
1. Review [ArgoCD Release Notes](https://github.com/argoproj/argo-cd/releases)
2. Test in staging environment first
3. Backup current state (see [Backup](#backup-and-recovery))

**Upgrade Order**: Hub first, then spokes one at a time

**Steps**:

1. **Update Version**:
```hcl
argocd_version = "v0.5.4"  # Update to new version
```

2. **Upgrade Hub Only**:
```bash
deploy_hub = true
deploy_spokes = false

terraform plan
terraform apply
```

3. **Verify Hub**:
```bash
kubectl --context=$HUB_CTX get pods -n argocd \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].image}{"\n"}{end}'

argocd login <argocd-url> --username admin
```

4. **Upgrade Spokes**:
```bash
deploy_spokes = true
terraform apply
```

5. **Verify Each Spoke**:
```bash
kubectl --context=$SPOKE_CTX logs -n argocd -l app.kubernetes.io/name=argocd-agent --tail=50
kubectl --context=$SPOKE_CTX get applications -n argocd
```

**Duration**: Hub 10-15 min, each spoke 5-10 min

**Rollback**:
```bash
argocd_version = "v0.5.3"  # Previous version
terraform apply
```

---

## Monitoring

### Key Metrics

#### Hub Metrics

**Principal Health**:
```bash
# Connected agents count
kubectl --context=$HUB_CTX logs -n argocd -l app.kubernetes.io/name=argocd-agent-principal | grep "agent connected" | wc -l

# gRPC errors
kubectl --context=$HUB_CTX logs -n argocd -l app.kubernetes.io/name=argocd-agent-principal | grep "error"
```

**Resource Usage**:
```bash
kubectl --context=$HUB_CTX top pod -n argocd -l app.kubernetes.io/name=argocd-agent-principal
kubectl --context=$HUB_CTX top pod -n argocd -l app.kubernetes.io/name=redis
```

**Application Status**:
```bash
kubectl --context=$HUB_CTX get applications -A \
  -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}: {.status.health.status}{"\n"}{end}' | \
  sort | uniq -c
```

#### Spoke Metrics

**Agent Health**:
```bash
kubectl --context=$SPOKE_CTX logs -n argocd -l app.kubernetes.io/name=argocd-agent --tail=10 | grep "connected\|error"
```

**Application Controller**:
```bash
kubectl --context=$SPOKE_CTX logs -n argocd -l app.kubernetes.io/name=argocd-application-controller | grep "reconciliation"
kubectl --context=$SPOKE_CTX get applications -n argocd \
  -o jsonpath='{range .items[?(@.status.sync.status=="OutOfSync")]}{.metadata.name}{"\n"}{end}'
```

---

### Prometheus Metrics

ArgoCD exposes metrics on `argocd-metrics:8082/metrics`.

**Key Metrics**:
```promql
# Agent connection count
argocd_agent_principal_connections_total

# Application sync status
argocd_app_info{sync_status="Synced"}

# Reconciliation duration
argocd_app_reconcile_bucket
```

**Scrape Config**:
```yaml
scrape_configs:
- job_name: 'argocd'
  kubernetes_sd_configs:
  - role: endpoints
    namespaces:
      names: [argocd]
  relabel_configs:
  - source_labels: [__meta_kubernetes_service_name]
    regex: argocd-metrics|argocd-server-metrics
    action: keep
```

---

### Alerting Rules

```yaml
groups:
- name: argocd-agent
  rules:
  - alert: ArgoCDAgentDisconnected
    expr: argocd_agent_principal_connections_total == 0
    for: 5m
    labels:
      severity: critical
    annotations:
      summary: "No agents connected to principal"

  - alert: ArgoCDApplicationOutOfSync
    expr: argocd_app_info{sync_status!="Synced"} > 0
    for: 15m
    labels:
      severity: warning
    annotations:
      summary: "Application {{ $labels.name }} out of sync"

  - alert: ArgoCDPrincipalDown
    expr: up{job="argocd-agent-principal"} == 0
    for: 2m
    labels:
      severity: critical
    annotations:
      summary: "ArgoCD Principal is down"
```

---

## Backup and Recovery

### What to Backup

**Critical** (cannot be regenerated):
1. PKI CA Certificate + Private Key
2. Terraform State (contains secrets)

**Recommended** (can be recreated from Git):
3. ArgoCD Applications
4. ArgoCD Projects
5. RBAC Policies

**Not Critical** (regenerate with Terraform):
- Agent client certificates
- Redis cache
- Application sync state

---

### Backup Procedures

#### 1. Backup PKI CA (Critical)

```bash
# Backup Hub CA
kubectl --context=$HUB_CTX get secret -n argocd argocd-agent-ca \
  -o yaml > backups/argocd-agent-ca-$(date +%Y%m%d).yaml

# Encrypt backup
gpg --encrypt --recipient ops@example.com backups/argocd-agent-ca-*.yaml

# Store in secure location
aws s3 cp backups/argocd-agent-ca-*.yaml.gpg s3://secure-backups/argocd/
```

**Frequency**: After initial deployment, then before certificate rotation

---

#### 2. Backup Applications

```bash
# All applications
kubectl --context=$HUB_CTX get applications -A -o yaml > backups/applications-$(date +%Y%m%d).yaml

# By namespace
for ns in $(kubectl --context=$HUB_CTX get ns -o name | grep agent); do
  kubectl --context=$HUB_CTX get applications -n ${ns#namespace/} -o yaml > backups/apps-${ns#namespace/}-$(date +%Y%m%d).yaml
done
```

**Frequency**: Daily (or use GitOps - store Applications in Git)

---

#### 3. Backup Terraform State

```bash
# For local state
cp terraform.tfstate backups/terraform.tfstate.$(date +%Y%m%d)

# For remote state (GCS)
gsutil cp gs://your-tf-state-bucket/argocd-agent/default.tfstate \
  backups/terraform.tfstate.$(date +%Y%m%d)
```

**Warning**: Terraform state contains private keys. Encrypt before storing.

**Frequency**: After every `terraform apply`

---

### Recovery Procedures

#### Recover from Lost Hub

**Scenario**: Hub cluster destroyed

**Steps**:

1. **Restore Terraform State**:
```bash
cp backups/terraform.tfstate.YYYYMMDD terraform.tfstate
```

2. **Recreate Hub** (without touching spokes):
```bash
deploy_hub = true
deploy_spokes = false

terraform apply
```

3. **Restore CA Certificate**:
```bash
gpg --decrypt backups/argocd-agent-ca-YYYYMMDD.yaml.gpg > ca-restore.yaml
kubectl --context=$HUB_CTX apply -f ca-restore.yaml
```

4. **Restore Applications**:
```bash
kubectl --context=$HUB_CTX apply -f backups/applications-YYYYMMDD.yaml
```

5. **Verify Spokes Reconnect**:
```bash
kubectl --context=$SPOKE_CTX logs -n argocd -l app.kubernetes.io/name=argocd-agent
```

**Duration**: ~30 minutes

---

#### Recover from Lost Spoke

**Steps**:

```bash
# Terraform will detect missing spoke and recreate
terraform apply
```

Applications automatically re-sync after agent reconnects.

**Duration**: ~10 minutes

---

#### Recover from Lost CA Certificate

**Critical**: If CA lost with no backup, regenerate (breaks all agent connections):

```bash
# Regenerate CA
terraform taint 'module.hub_cluster[0].tls_self_signed_cert.hub_ca[0]'
terraform apply

# Regenerate all client certificates
for agent in agent-1 agent-2 agent-3; do
  terraform taint "module.spoke_cluster[\"$agent\"].tls_locally_signed_cert.spoke_client[0]"
done
terraform apply

# Restart all agents
for ctx in spoke-1-ctx spoke-2-ctx spoke-3-ctx; do
  kubectl --context=$ctx delete pod -n argocd -l app.kubernetes.io/name=argocd-agent
done
```

**Duration**: ~30 minutes | **Impact**: All agents disconnected during regeneration

---

## Certificate Management

### Certificate Hierarchy

```
Hub CA (Self-Signed)
├── RSA 4096-bit
├── Validity: 10 years
├── Stored: Hub cluster secret `argocd-agent-ca`
│
└── Spoke Client Certificates
    ├── agent-1 (RSA 4096, 1 year validity)
    ├── agent-2 (RSA 4096, 1 year validity)
    └── agent-N (RSA 4096, 1 year validity)
    └── Stored: Spoke cluster secret `argocd-agent-client-cert`
```

All PKI operations fully automated via Terraform. No manual `argocd-agentctl` commands required.

---

### Certificate Inspection

**View Hub CA**:
```bash
kubectl --context=$HUB_CTX get secret -n argocd argocd-agent-ca \
  -o jsonpath='{.data.ca\.crt}' | base64 -d > hub-ca.crt

openssl x509 -in hub-ca.crt -text -noout
openssl x509 -in hub-ca.crt -noout -dates
```

**View Spoke Client Certificate**:
```bash
kubectl --context=$SPOKE_CTX get secret -n argocd argocd-agent-client-cert \
  -o jsonpath='{.data.tls\.crt}' | base64 -d > spoke-client.crt

openssl x509 -in spoke-client.crt -text -noout

# Verify signed by Hub CA
openssl verify -CAfile hub-ca.crt spoke-client.crt
```

---

### Certificate Rotation

**When to Rotate**:
- Client certs: < 30 days until expiry
- CA cert: < 1 year until expiry
- Security incident (compromise suspected)
- Regular schedule (annually for client certs)

**Rotation Process**:

```bash
# Rotate specific spoke certificate
terraform taint 'module.spoke_cluster["agent-1"].tls_locally_signed_cert.spoke_client[0]'
terraform apply

# Rotate all spoke certificates
for agent in agent-1 agent-2 agent-3; do
  terraform taint "module.spoke_cluster[\"$agent\"].tls_locally_signed_cert.spoke_client[0]"
done
terraform apply
```

**Impact**: Brief agent reconnection (10-30 seconds per spoke)

---

### Expiration Monitoring

**Check Expiration Dates**:
```bash
# Hub CA
kubectl --context=$HUB_CTX get secret -n argocd argocd-agent-ca \
  -o jsonpath='{.data.ca\.crt}' | base64 -d | openssl x509 -noout -enddate

# Spoke client cert
kubectl --context=$SPOKE_CTX get secret -n argocd argocd-agent-client-cert \
  -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -enddate
```

**Automated Monitoring CronJob**:
```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: cert-expiry-check
  namespace: argocd
spec:
  schedule: "0 0 * * *"  # Daily
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: check
            image: alpine/openssl
            command:
            - sh
            - -c
            - |
              CERT_FILE="/certs/tls.crt"
              EXPIRY=$(openssl x509 -in $CERT_FILE -noout -enddate | cut -d= -f2)
              EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s)
              NOW_EPOCH=$(date +%s)
              DAYS_LEFT=$(( ($EXPIRY_EPOCH - $NOW_EPOCH) / 86400 ))
              
              if [ $DAYS_LEFT -lt 30 ]; then
                echo "WARNING: Certificate expires in $DAYS_LEFT days!"
                exit 1
              else
                echo "Certificate valid for $DAYS_LEFT more days"
              fi
            volumeMounts:
            - name: cert
              mountPath: /certs
          volumes:
          - name: cert
            secret:
              secretName: argocd-agent-client-cert
          restartPolicy: OnFailure
```

---

### Certificate Security

**Terraform State Security**: Certificates stored in Terraform state. Use encrypted remote state:

```hcl
terraform {
  backend "gcs" {
    bucket = "my-terraform-state"
    prefix = "argocd-agent"
    encryption_key = "projects/my-project/locations/global/keyRings/terraform/cryptoKeys/state"
  }
}
```

**Rotation Schedule**:

| Certificate | Recommended Rotation |
|-------------|---------------------|
| Hub CA | Every 5-10 years |
| Spoke Client Certs | Every 1 year |
| JWT Keys | Every 2 years |

---

## Performance Tuning

### Timeout Configuration

**When to Adjust**: API discovery timeouts, slow spoke cluster APIs, high-latency networks

```hcl
# terraform.tfvars

# Repository server timeout (default: 300s)
argocd_repo_server_timeout = "600s"

# Reconciliation timeout (default: 600s)
argocd_reconciliation_timeout = "900s"

# Connection status cache (default: 1h)
argocd_connection_status_cache = "30m"
```

---

### Resource Tuning

**For high-load environments**:

```yaml
# Hub Principal
resources:
  requests:
    cpu: "500m"      # Increase from default 100m
    memory: "512Mi"  # Increase from default 256Mi
  limits:
    cpu: "2000m"
    memory: "2Gi"

# Spoke Application Controller
resources:
  requests:
    cpu: "500m"      # Increase from default 250m
    memory: "1Gi"    # Increase from default 512Mi
  limits:
    cpu: "2000m"
    memory: "2Gi"
```

---

## Teardown & Cleanup

### Full Teardown

```bash
cd argocd-agent/terraform/environments/prod
terraform destroy
```

**Destruction Order**:

| Phase | Resources | Duration |
|-------|-----------|----------|
| 1. Applications | Keycloak users, groups, clients | ~30s |
| 2. Agent Resources | Agent configs, PKI, credentials | ~60s |
| 3. Namespaces | agent-1, agent-2, ..., argocd | ~90s |
| 4. Infrastructure | cert-manager, ingress-nginx | ~60s |

**Total Time**: ~5-7 minutes

---

### What Gets Deleted

| Resource Type | Auto-Deleted | Manual Cleanup |
|---------------|--------------|----------------|
| Kubernetes namespaces | Yes | - |
| Kubernetes resources | Yes | - |
| Helm releases | Yes | - |
| cert-manager CRDs | Yes | - |
| Keycloak realm/users | Yes | - |
| **GCP LoadBalancers** | Usually | Sometimes orphaned |

---

### LoadBalancer Cleanup

GCP LoadBalancer deletion is asynchronous. Terraform may exit before GCP finishes cleanup.

**Check for Orphaned LoadBalancers**:
```bash
gcloud compute forwarding-rules list \
  --filter="name~'^a[a-f0-9]{31}$'" \
  --format="table(name,region,IPAddress)"

gcloud compute target-pools list \
  --filter="name~'^a[a-f0-9]{31}$'" \
  --format="table(name,region)"
```

**Cleanup**:
```bash
cd argocd-agent/scripts
./cleanup-gcp-lb.sh

# Or manual
gcloud compute forwarding-rules delete <name> --region=<region> --quiet
gcloud compute target-pools delete <name> --region=<region> --quiet
```

---

### Namespace Troubleshooting

**Namespace Stuck in "Terminating"**:

```bash
# Check finalizers
kubectl get namespace <namespace> -o yaml | grep finalizers -A 5

# Remove finalizers
kubectl patch namespace <namespace> \
  -p '{"metadata":{"finalizers":[]}}' \
  --type=merge

# Or use cleanup script
cd argocd-agent/scripts
./cleanup-namespaces.sh
```

---

### Verification Checklist

After `terraform destroy`:

```bash
# Namespaces
kubectl get ns | grep -E 'argocd|agent|cert-manager|ingress-nginx'
# Expected: No output

# Helm releases
helm list -A | grep -E 'cert-manager|nginx-ingress'
# Expected: No output

# CRDs
kubectl get crd | grep cert-manager
# Expected: No output

# LoadBalancers
gcloud compute forwarding-rules list --filter="name~'^a[a-f0-9]{31}$'"
# Expected: No output

# Full verification script
cd argocd-agent/scripts
./verify-destroy.sh
```

---

## Incident Response

### Common Incidents

#### 1. All Agents Disconnected

**Symptoms**: No agents connected, applications show "Unknown"

**Triage**:
```bash
kubectl --context=$HUB_CTX get pods -n argocd -l app.kubernetes.io/name=argocd-agent-principal
kubectl --context=$HUB_CTX logs -n argocd -l app.kubernetes.io/name=argocd-agent-principal --tail=100
```

**Likely Causes**:
1. Principal pod crashed → Restart: `kubectl delete pod -n argocd -l app.kubernetes.io/name=argocd-agent-principal`
2. Principal LoadBalancer/Ingress down → Check service/ingress
3. Network partition → Check cloud provider status
4. Certificate expired → Check cert expiry, rotate if needed

**Resolution Time**: 5-15 minutes

---

#### 2. Single Spoke Agent Disconnected

**Triage**:
```bash
kubectl --context=$SPOKE_CTX logs -n argocd -l app.kubernetes.io/name=argocd-agent --tail=100
```

**Likely Causes**:
1. Network connectivity issue → Test: `curl https://principal-host:443`
2. Certificate expired → Check cert expiry
3. Agent pod crashed → Restart: `kubectl delete pod -n argocd -l app.kubernetes.io/name=argocd-agent`

**Resolution Time**: 2-10 minutes

---

#### 3. Applications Not Syncing

**Triage**:
```bash
kubectl --context=$HUB_CTX get application -n agent-1 <app-name> -o yaml
kubectl --context=$SPOKE_CTX logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=100
```

**Likely Causes**:
1. Git repository unreachable → Test git clone
2. Kubernetes API timeout → Check spoke cluster health
3. Insufficient RBAC → Check application controller permissions
4. Resource validation failed → Check application manifests

**Resolution Time**: 10-30 minutes

---

## Operational Best Practices

1. **GitOps for Applications**: Store Application manifests in Git, not directly in cluster
2. **Automate Backups**: Daily automated backups of CA certs and applications
3. **Monitor Certificate Expiry**: Alert 30 days before client cert expiry
4. **Test Disaster Recovery**: Quarterly DR drills
5. **Document Custom Changes**: Track any manual changes outside Terraform
6. **Regular Upgrades**: Stay within 2 minor versions of latest ArgoCD release
7. **Staging Environment**: Always test changes in staging first
8. **Incident Postmortems**: Document and learn from incidents

---

**Related Guides**:
- [Deployment](argocd-agent-terraform-deployment.md) - Initial setup
- [Configuration](argocd-agent-configuration.md) - All Terraform variables
- [Troubleshooting](argocd-agent-troubleshooting.md) - Issue resolution
- [RBAC](argocd-agent-rbac.md) - Keycloak SSO and permissions
- [Architecture](argocd-agent-architecture.md) - Hub-spoke design
