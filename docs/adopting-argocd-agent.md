# Adopting Existing ArgoCD Agent Installation

This guide walks you through adopting an existing ArgoCD Agent (Hub-and-Spoke) installation into Terraform management.

## Prerequisites

- Existing ArgoCD Agent installation (Hub and/or Spoke clusters)
- Terraform >= 1.0
- `kubectl` configured for all relevant clusters
- `argocd-agentctl` CLI installed
- Access to PKI certificates (if rotating)

---

## Step 1: Discover Existing Installation

Run these commands to gather information about your current ArgoCD Agent setup.

### 1. Hub Cluster Resources

```bash
# Set hub context
export HUB_CTX="your-hub-context"

# Check namespace
kubectl get ns argocd --context=$HUB_CTX

# Check Principal deployment
kubectl get deployment argocd-agent-principal -n argocd --context=$HUB_CTX

# Check resource-proxy service
kubectl get svc argocd-agent-resource-proxy -n argocd --context=$HUB_CTX

# Check agent namespaces
kubectl get ns --context=$HUB_CTX | grep agent

# List PKI secrets
kubectl get secrets -n argocd --context=$HUB_CTX | grep -E "pki|tls|ca"
```

### 2. Spoke Cluster Resources

```bash
# For each spoke cluster
export SPOKE_CTX="your-spoke-context"

# Check namespace
kubectl get ns argocd --context=$SPOKE_CTX

# Check agent deployment
kubectl get deployment argocd-agent-agent -n argocd --context=$SPOKE_CTX

# Check certificates
kubectl get secrets -n argocd --context=$SPOKE_CTX | grep -E "agent|tls|ca"
```

### 3. Agent Connections

```bash
# List connected agents
argocd-agentctl agent list \
  --principal-context $HUB_CTX \
  --principal-namespace argocd
```

**Record these values**:
- Hub cluster context
- Spoke cluster contexts
- Agent names
- Principal LoadBalancer IP/hostname
- ArgoCD UI hostname

---

## Step 2: Configure `terraform.tfvars`

Navigate to the Terraform directory:

```bash
cd argocd-agent/terraform
```

Copy the template:

```bash
cp terraform.tfvars.template terraform.tfvars
```

Update `terraform.tfvars` with your discovery values:

```hcl
# Deployment mode - set based on what you're adopting
deploy_hub    = true  # Set false if only adopting spokes
deploy_spokes = true  # Set false if only adopting hub

# Hub cluster configuration
hub_cluster_context = "your-hub-context"
hub_namespace       = "argocd"  # MUST match existing namespace
hub_argocd_url      = "https://argocd.example.com"
hub_principal_host  = "agent-principal.example.com"

# Spoke clusters (add all existing spokes)
workload_clusters = {
  "agent-1" = "spoke-1-context"
  "agent-2" = "spoke-2-context"
  "agent-3" = "spoke-3-context"
}

# Shared infrastructure (set to false if already managed)
install_cert_manager  = false
install_nginx_ingress = false

# Keycloak (if configured)
enable_keycloak = false  # Set true if Keycloak is configured
```

---

## Step 3: Initialize Terraform

```bash
terraform init
```

---

## Step 4: Import Existing Resources

You must import the existing resources into the Terraform state.

### 1. Import Hub Namespace

```bash
terraform import 'kubernetes_namespace.hub_argocd[0]' argocd
```

### 2. Import Agent Namespaces

```bash
# For each agent
terraform import 'kubernetes_namespace.agent_managed_namespace["agent-1"]' agent-1
terraform import 'kubernetes_namespace.agent_managed_namespace["agent-2"]' agent-2
terraform import 'kubernetes_namespace.agent_managed_namespace["agent-3"]' agent-3
```

### 3. Import Certificates (Optional)

> **Warning**: PKI secrets contain sensitive keys. Consider regenerating instead of importing.

If you want to preserve existing certificates:

```bash
# Backup existing PKI
kubectl get secret argocd-agent-pki-ca -n argocd --context=$HUB_CTX -o yaml > pki-backup.yaml

# Import if needed (complex - regeneration recommended)
```

**Recommended**: Let Terraform regenerate certificates and rotate them.

---

## Step 5: Handle Conflicting Resources

ArgoCD Agent creates many resources that Terraform will want to manage. You have two options:

### Option A: Clean Deployment (Recommended)

1. **Backup critical data**:
   ```bash
   # Backup PKI CA certificate
   kubectl get secret argocd-agent-pki-ca -n argocd --context=$HUB_CTX -o yaml > pki-ca-backup.yaml
   
   # Backup applications (if any)
   kubectl get applications -A --context=$HUB_CTX -o yaml > applications-backup.yaml
   ```

2. **Delete existing installation**:
   ```bash
   # Hub cleanup
   kubectl delete namespace argocd --context=$HUB_CTX
   kubectl delete namespace agent-1 agent-2 agent-3 --context=$HUB_CTX
   
   # Spoke cleanup (for each spoke)
   kubectl delete namespace argocd --context=$SPOKE_CTX
   ```

3. **Deploy with Terraform**:
   ```bash
   terraform plan
   terraform apply
   ```

### Option B: Selective Import (Advanced)

Import each resource individually:

```bash
# Example: Import principal deployment
terraform import 'kubernetes_deployment.principal[0]' argocd/argocd-agent-principal

# This is tedious and error-prone - Option A is recommended
```

---

## Step 6: Verify the Adoption

```bash
terraform plan
```

**Expected output**:
- **No changes** if all resources were imported correctly
- **Minor modifications** to align with Terraform-managed configuration
- **Additions** for any resources Terraform will create (like timeout configs)

---

## Step 7: Apply Configuration

```bash
terraform apply
```

This will:
- Configure timeout settings automatically
- Ensure all resources match desired state
- Apply any missing configurations

---

## Important: Timeout Configuration

The Terraform module automatically configures timeout settings required for the agent architecture:

- **Repository Server Timeout**: 300s (5 min) vs default 60s
- **Reconciliation Timeout**: 600s (10 min) vs default 180s  
- **Connection Status Cache**: 1h for reduced API load

These are essential for API discovery through the resource-proxy. See [argocd-agent-terraform-deployment.md](argocd-agent-terraform-deployment.md#important-timeout-configuration) for details.

---

## Post-Adoption Tasks

### 1. Verify Agent Connections

```bash
argocd-agentctl agent list \
  --principal-context $HUB_CTX \
  --principal-namespace argocd

# Should show all agents connected
```

### 2. Test Application Deployment

Create a test application on the Hub and verify it deploys to a spoke.

### 3. Backup PKI

```bash
# Backup the CA certificate (cannot be regenerated!)
kubectl get secret argocd-agent-pki-ca -n argocd --context=$HUB_CTX \
  -o yaml > pki-ca-backup-$(date +%Y%m%d).yaml

# Encrypt and store securely
gpg --encrypt --recipient admin@example.com pki-ca-backup-*.yaml
```

---

## Common Issues

### Error: "Resource already exists"

**Fix**: The resource needs to be imported. Use `terraform import` for that resource or delete and let Terraform recreate it.

### Agent Connection Failed After Adoption

**Fix**: Verify certificates are valid:
```bash
# Check agent logs
kubectl logs -n argocd deployment/argocd-agent-agent --context=$SPOKE_CTX

# Regenerate certificates if needed
terraform taint null_resource.agent_client_cert["agent-1"]
terraform apply
```

### Timeout Errors on Applications

**Fix**: The timeout configuration should be applied automatically. Verify:
```bash
kubectl get configmap argocd-cmd-params-cm -n argocd --context=$HUB_CTX -o yaml | grep timeout
kubectl get configmap argocd-cm -n argocd --context=$HUB_CTX -o yaml | grep timeout
```

If not present, run:
```bash
terraform apply -target=null_resource.hub_apps_any_namespace -target=null_resource.hub_argocd_timeouts
```

---

## Next Steps

1. **Monitor**: Watch agent connections and application sync status
2. **Documentation**: Update your runbooks with Terraform commands
3. **Certificate Rotation**: Plan certificate rotation schedule (see [Operations: Certificate Rotation](argocd-agent-operations.md#certificate-rotation))
4. **Scaling**: Add more spokes using Terraform (see [argocd-agent-terraform-deployment.md](argocd-agent-terraform-deployment.md#multi-spoke-scaling))

---

## Reference Documentation

- [Architecture](argocd-agent-architecture.md)
- [Terraform Deployment](argocd-agent-terraform-deployment.md)
- [Troubleshooting](argocd-agent-troubleshooting.md)
