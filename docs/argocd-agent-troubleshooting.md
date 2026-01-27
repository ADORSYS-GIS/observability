# ArgoCD Agent - Troubleshooting

Solutions to common issues and production deployment problems.

---

## Quick Diagnostics

### Hub Cluster
```bash
export HUB_CTX="your-hub-context"

kubectl --context=$HUB_CTX get pods -n argocd
kubectl --context=$HUB_CTX logs -n argocd -l app.kubernetes.io/name=argocd-agent-principal --tail=50
kubectl --context=$HUB_CTX exec -n argocd deployment/argocd-agent-principal -- redis-cli -h argocd-redis ping
```

### Spoke Cluster
```bash
export SPOKE_CTX="your-spoke-context"

kubectl --context=$SPOKE_CTX get pods -n argocd
kubectl --context=$SPOKE_CTX logs -n argocd -l app.kubernetes.io/name=argocd-agent --tail=50 | grep "connected"
```

---

## Common Issues

### Apps Stuck "Unknown/Unknown"

**Symptoms**: Apps show Unknown status after agent/principal restart, logs show `EOF` errors

**Root cause**: Stale gRPC connections

**Solution**:
```bash
# Force reconnection (don't use rollout restart!)
kubectl --context=$SPOKE_CTX delete pod -l app.kubernetes.io/name=argocd-agent -n argocd

# Verify
kubectl --context=$SPOKE_CTX logs -n argocd -l app.kubernetes.io/name=argocd-agent | grep "connected"
```

**Why not `rollout restart`?** Creates new pods before terminating old ones, leaving stale connections active.

---

### UI "cache: key is missing" Error

**Symptoms**: Application detail view fails

**Root cause**: **Expected behavior**. Principal-only hub doesn't run application-controller (which populates cache).

**Workarounds**:
- Use list view (works)
- Use CLI: `kubectl get app -n <namespace> -o yaml`
- Access spoke ArgoCD directly for full tree view

**Not a bug** - [upstream issue #612](https://github.com/argoproj-labs/argocd-agent/issues/612)

---

### Agent Can't Connect to Principal

**Symptoms**: Agent logs show `connection refused` or `certificate verify failed`

| Check | Command | Fix |
|-------|---------|-----|
| Network | `kubectl --context=$SPOKE_CTX run -it --rm debug --image=curlimages/curl -- curl -v https://PRINCIPAL_IP:443` | Check firewall rules, verify Principal IP |
| Certificates | `kubectl --context=$SPOKE_CTX get secret argocd-agent-client-tls -n argocd` | Re-run `04-agent-connect.sh` to regenerate |
| Allowed namespaces | `kubectl --context=$HUB_CTX get configmap argocd-agent-params -n argocd -o yaml \| grep allowed-namespaces` | Should include agent name |

---

### Application Sync Timeout

**Symptoms**: `context deadline exceeded` during sync

**Root cause**: Hub-spoke adds 3-6x latency

**Solution**: Increase timeouts in `terraform.tfvars`:
```hcl
kubectl_timeout = "600s"  # From 300s
```

**Latency comparison**:

| Operation | Standard | Hub-Spoke |
|-----------|----------|-----------|
| API Discovery | 5s | 15-30s |
| App Sync | 30s | 45-90s |

---

### LoadBalancer Stuck Pending

**Symptoms**: Service stuck after `terraform apply`

**Root cause**: Orphaned cloud resources

**Solution (GCP)**:
```bash
# Clean orphaned LBs
cd argocd-agent/scripts
./cleanup-gcp-lb.sh

# Recreate
kubectl --context=$HUB_CTX delete svc argocd-agent-principal -n argocd
terraform apply
```

---

### Namespace Stuck Terminating

**Solution**:
```bash
kubectl get namespace <ns> -o yaml | grep finalizers -A 5
kubectl patch namespace <ns> -p '{"metadata":{"finalizers":[]}}' --type=merge

# Or use script
cd argocd-agent/scripts
./cleanup-namespaces.sh
```

---

### Keycloak SSO Login Fails

**5-point checklist**:

| Check | How | Required |
|-------|-----|----------|
| Direct Access Grants | Keycloak → Client → Settings | ON |
| Password not temporary | Keycloak → User → Credentials | `temporary=false` |
| ArgoCD insecure mode | `kubectl get deploy argocd-server -o yaml` | If ingress terminates TLS |
| External URL | `kubectl get cm argocd-cm -o yaml` | `url: https://argocd.example.com` |
| Groups match | JWT groups vs RBAC policy | Case-sensitive |

See [RBAC guide](argocd-agent-rbac.md#critical-keycloak-configuration-issues) for details.

---

## Known Limitations

### UI Features

| Feature | Status | Workaround |
|---------|--------|------------|
| Resource tree view | Not supported | Use list view or `kubectl get app` |
| Pod terminal | Not supported | Use `kubectl exec` |
| Live resource diff | Partial | Enable resource-proxy + enhanced RBAC |

### Performance

| Metric | Standard | Hub-Spoke | Factor |
|--------|----------|-----------|--------|
| API latency | ~5s | ~15-30s | 3-6x |
| Sync time | ~30s | ~45-90s | 1.5-3x |

Mitigated by pre-configured extended timeouts.

### Architecture

| Limitation | Mitigation |
|------------|-----------|
| Principal HA limited | Use 2+ replicas with PDB |
| ApplicationSet cluster generator won't discover spokes | Use list generator |
| Spoke requires outbound to hub:443 | Standard agent pattern |

---

## Debugging Commands

### Connectivity
```bash
# Principal IP
kubectl --context=$HUB_CTX get svc argocd-agent-principal -n argocd \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# Test from spoke
kubectl --context=$SPOKE_CTX run -it --rm debug --image=curlimages/curl -- \
  curl -v https://PRINCIPAL_IP:443
```

### Certificates
```bash
# Hub CA expiration
kubectl --context=$HUB_CTX get secret argocd-agent-ca -n argocd \
  -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -dates

# Agent cert expiration
kubectl --context=$SPOKE_CTX get secret argocd-agent-client-tls -n argocd \
  -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -dates
```

### Configuration
```bash
# Principal config
kubectl --context=$HUB_CTX get configmap argocd-agent-params -n argocd -o yaml

# Agent config
kubectl --context=$SPOKE_CTX get configmap argocd-agent-params -n argocd -o yaml
```

### Component Health
```bash
# Hub
kubectl --context=$HUB_CTX get pods -n argocd
kubectl --context=$HUB_CTX exec -n argocd deployment/argocd-agent-principal -- redis-cli -h argocd-redis ping

# Spoke
kubectl --context=$SPOKE_CTX get pods -n argocd
kubectl --context=$SPOKE_CTX exec -n argocd deployment/argocd-application-controller -- wget -O- http://localhost:8081/healthz
```

---

## Diagnostic Bundle

Collect logs for support:

```bash
#!/bin/bash
BUNDLE="argocd-diag-$(date +%Y%m%d-%H%M%S)"
mkdir -p $BUNDLE/{hub,spoke}

# Hub
kubectl --context=$HUB_CTX get all,cm,secret -n argocd > $BUNDLE/hub/resources.yaml
kubectl --context=$HUB_CTX logs -n argocd -l app.kubernetes.io/name=argocd-agent-principal --tail=1000 > $BUNDLE/hub/principal.log
kubectl --context=$HUB_CTX logs -n argocd -l app.kubernetes.io/name=argocd-server --tail=1000 > $BUNDLE/hub/server.log

# Spoke
kubectl --context=$SPOKE_CTX get all,cm,secret -n argocd > $BUNDLE/spoke/resources.yaml
kubectl --context=$SPOKE_CTX logs -n argocd -l app.kubernetes.io/name=argocd-agent --tail=1000 > $BUNDLE/spoke/agent.log
kubectl --context=$SPOKE_CTX logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=1000 > $BUNDLE/spoke/controller.log

tar -czf $BUNDLE.tar.gz $BUNDLE
echo "Bundle: $BUNDLE.tar.gz"
```

---

## Getting Help

- [Report Issues](https://github.com/argoproj-labs/argocd-agent/issues)
- [CNCF Slack #argo-cd-agent-plugin](https://cloud-native.slack.com)
