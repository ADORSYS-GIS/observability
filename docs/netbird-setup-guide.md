# Netbird Setup Guide

Complete guide for setting up Netbird infrastructure to enable secure access to local spoke Kubernetes clusters from GitHub Actions runners.

> [!IMPORTANT]
> This setup must be completed **BEFORE** running the GitHub Actions workflows. Spoke clusters must be pre-configured with Netbird and accessible via their Netbird IPs.

## Overview

Netbird creates a secure VPN mesh network that allows GitHub Actions runners to access local Kubernetes clusters without exposing them to the public internet. The architecture uses:

- **Spoke Clusters**: Persistent Netbird peers with stable IPs (pre-configured)
- **GitHub Runners**: Ephemeral Netbird peers (10-min auto-cleanup)
- **ACLs**: Fine-grained access control (runners → spokes, port 6443 only)

---

## 1. Netbird Account Setup

### Option A: Netbird Cloud (Recommended for Getting Started)

1. **Sign up**: Visit [https://netbird.io](https://netbird.io) and create an account
2. **Access Dashboard**: Log in to [https://app.netbird.io](https://app.netbird.io)
3. **Verify Account**: Complete email verification

### Option B: Self-Hosted Netbird

For production or on-premises deployments:

1. **Deploy Netbird Management**: Follow [self-hosting guide](https://docs.netbird.io/selfhosted/selfhosted-guide)
2. **Components Required**:
   - Management service (coordinates peers)
   - Signal server (establishes connections)
   - TURN/STUN server (NAT traversal)
   - Dashboard (web UI)

---

## 2. Installing Netbird on Spoke Cluster Nodes

> [!CAUTION]
> **This is the most critical step** - spoke clusters MUST be in the Netbird network before running workflows.

> [!NOTE]
> This guide assumes you're using Netbird's official installation script. If you've already installed Netbird using a different method, skip to the API server configuration section.

### Install Netbird Using Official Script

Use Netbird's installation script to install and connect nodes to the network:

```bash
# Install and connect Netbird in one command
curl -fsSL https://netbird.io/install.sh | sh

# Or download and inspect the script first
curl -fsSL https://netbird.io/install.sh -o install-netbird.sh
chmod +x install-netbird.sh
./install-netbird.sh
```

### Connect to Netbird Network

After installation, connect using your spoke cluster setup key (created in section 3):

```bash
# Connect using setup key
netbird up --setup-key <YOUR_SPOKE_SETUP_KEY>

# Enable service to start on boot
sudo systemctl enable netbird
sudo systemctl start netbird
```

### Verify Netbird Connection

```bash
# Check Netbird status
netbird status

# Expected output:
# Daemon status: Connected
# NetBird IP: 100.69.142.233
# Management: Connected
# Signal: Connected
# Relayed: false

# Save the Netbird IP - you'll need it!
# Example: 100.69.142.233
```

### Configure Kubernetes API Server for Netbird

**CRITICAL**: Configure your Kubernetes API server to advertise its Netbird IP so the GitHub runners can access it.

#### For K3s

Edit `/etc/systemd/system/k3s.service` and modify the `ExecStart` line to include your Netbird IP:

```bash
# Replace 100.69.142.233 with your actual Netbird IP
ExecStart=/usr/local/bin/k3s \
    server \
    --tls-san=100.69.142.233 \
    --bind-address=100.69.142.233 \
    --advertise-address=100.69.142.233 \
    --node-external-ip=100.69.142.233
```

**Apply changes**:
```bash
# Reload systemd
sudo systemctl daemon-reload

# Restart K3s
sudo systemctl restart k3s

# Verify API server is listening on Netbird IP
sudo netstat -tlnp | grep 6443
# Expected: tcp 0 0 100.69.142.233:6443 0.0.0.0:* LISTEN
```

#### For kubeadm/Standard Kubernetes

**Regenerate API server certificates** to include Netbird IP in SANs:

```bash
# Backup existing certs
sudo cp -r /etc/kubernetes/pki /etc/kubernetes/pki.backup

# Create config with your Netbird IP
cat > apiserver-cert-config.yaml <<EOF
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
apiServer:
  certSANs:
  - "100.69.142.233"  # Your Netbird IP
  - "kubernetes"
  - "kubernetes.default"
  - "kubernetes.default.svc"
  - "kubernetes.default.svc.cluster.local"
  - "10.96.0.1"  # Your cluster IP (check with kubectl get svc kubernetes)
  - "<your-node-hostname>"
  - "<your-node-ip>"
EOF

# Regenerate certs
sudo kubeadm init phase certs apiserver --config apiserver-cert-config.yaml

# Restart API server (it will auto-restart)
sudo pkill -f 'kube-apiserver'
```

Then add to `/etc/kubernetes/manifests/kube-apiserver.yaml`:
```yaml
- --advertise-address=100.69.142.233
- --bind-address=100.69.142.233
```

#### For RKE/RKE2

Edit `/etc/rancher/rke2/config.yaml`:

```yaml
tls-san:
  - "100.69.142.233"  # Your Netbird IP
advertise-address: "100.69.142.233"
bind-address: "100.69.142.233"
node-external-ip: "100.69.142.233"
```

Apply: `sudo systemctl restart rke2-server`

### Test API Server Access via Netbird

```bash
# Join Netbird temporarily
netbird up --setup-key <RUNNER_SETUP_KEY>

# Test API access (replace IP with your Netbird IP)
curl -k https://100.69.142.233:6443/version
# Should return Kubernetes version JSON

# Leave network
netbird down
```

### Extract Configuration for GitHub Secrets

```bash
# Get Netbird IP
netbird status | grep "NetBird IP"
# Save as: SPOKE_1_NETBIRD_IP

# Get Kubernetes credentials (already base64-encoded)
kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}'
# Save as: SPOKE_1_CA_CERT

kubectl config view --raw -o jsonpath='{.users[0].user.client-certificate-data}'
# Save as: SPOKE_1_CLIENT_CERT

kubectl config view --raw -o jsonpath='{.users[0].user.client-key-data}'
# Save as: SPOKE_1_CLIENT_KEY
```

---

## 3. Creating Setup Keys

Setup keys authenticate peers joining the Netbird network. You need two types:

### Setup Key for Spoke Clusters (Persistent)

Create this key FIRST to register spoke clusters:

1. **Navigate** to Netbird Dashboard → Setup Keys
2. **Click** "+ Add Key"
3. **Configure**:
   - Name: `spoke-clusters`
   - Type: **Persistent** (or Reusable if you want to reuse for multiple clusters)
   - Usage Limit: `10` (or number of spoke clusters you have)
   - Expires: `Never` (or set appropriate expiry)
   - Auto-assign Groups: `spoke-clusters` *(create group if doesn't exist)*
4. **Create Key** and **COPY IMMEDIATELY** (shown only once)
5. **Use** this key to install Netbird on spoke cluster nodes (see section 2)

### Setup Key for GitHub Runners (Ephemeral)

Create this key for GitHub Actions workflows:

1. **Navigate** to Netbird Dashboard → Setup Keys
2. **Click** "+ Add Key"
3. **Configure**:
   - Name: `github-runners`
   - Type: **Ephemeral**
   - Auto-cleanup after: `10 minutes` *(important for transient runners)*
   - Usage Limit: **Unlimited** *(reusable for all workflow runs)*
   - Expires: `Never` (or set appropriate expiry)
   - Auto-assign Groups: `github-runners` *(create group if doesn't exist)*
4. **Create Key** and **COPY IMMEDIATELY**
5. **Store** in GitHub Secrets as `NETBIRD_SETUP_KEY_RUNNERS`

> [!TIP]
> Ephemeral keys automatically remove runners from Netbird after inactivity, preventing clutter from short-lived workflow runs.

---

## 4. Configuring Access Control Lists (ACLs)

ACLs restrict which Netbird peers can communicate. Configure to allow only runners → spokes on port 6443.

### Create ACL Rule

1. **Navigate** to Netbird Dashboard → Access Control
2. **Click** "+ Add Rule"
3. **Configure**:
   - Name: `GitHub Runners to Spoke Clusters`
   - Source: `github-runners` (group)
   - Destination: `spoke-clusters` (group)
   - Protocol: `TCP`
   - Ports: `6443`
   - Action: `Allow`
   - Bidirectional: `false` *(one-way from runners to spokes)*
4. **Save**

### Verify ACL Configuration

```bash
# From a test Netbird peer in github-runners group
# Try accessing spoke cluster API
curl -k https://<SPOKE_NETBIRD_IP>:6443/version

# Expected: Kubernetes version JSON response
```

---

## 5. Extracting Spoke Cluster Netbird IPs

You need the Netbird IP of each spoke cluster to configure kubectl access:

### Method 1: Via Netbird Dashboard

1. **Navigate** to Netbird Dashboard → Peers
2. **Find** your spoke cluster nodes (filter by `spoke-clusters` group)
3. **Copy** the Netbird IP for each cluster
   - Example: `100.64.1.10` for spoke-1

### Method 2: Via CLI on Spoke Nodes

```bash
# SSH to spoke cluster node
ssh <spoke-node>

# Get Netbird IP
netbird status | grep "NetBird IP"

# Output: NetBird IP: 100.64.1.10
```

### Store in GitHub Secrets

For each spoke cluster, store:

| Secret Name | Example Value | Description |
|-------------|---------------|-------------|
| `SPOKE_1_NETBIRD_IP` | `100.64.1.10` | Netbird IP of spoke-1 API server |
| `SPOKE_1_CA_CERT` | `LS0tLS1CRUdJ...` | Kubernetes CA certificate (base64) |
| `SPOKE_1_CLIENT_CERT` | `LS0tLS1CRUdJ...` | Client certificate (base64) |
| `SPOKE_1_CLIENT_KEY` | `LS0tLS1CRUdJ...` | Client key (base64) |

**How to get Kubernetes credentials**:

```bash
# On spoke cluster (assuming you have kubectl access)

# 1. Get CA certificate
kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}'

# 2. Get client certificate
kubectl config view --raw -o jsonpath='{.users[0].user.client-certificate-data}'

# 3. Get client key
kubectl config view --raw -o jsonpath='{.users[0].user.client-key-data}'

# Already base64 encoded, copy directly to GitHub Secrets
```

---

## 6. GitHub Secrets Configuration

Complete list of secrets needed for the workflows:

### Netbird Secrets

| Secret | Value | Description |
|--------|-------|-------------|
| `NETBIRD_SETUP_KEY_RUNNERS` | From section 3 | Ephemeral setup key for runners |

### Hub Cluster Secrets (GKE)

| Secret | Value | Description |
|--------|-------|-------------|
| `GCP_SA_KEY` | GCP service account JSON | For GKE access |
| `GCP_PROJECT_ID` | `my-project-id` | GCP project |
| `HUB_CLUSTER_NAME` | `my-hub-cluster` | GKE cluster name |
| `HUB_CLUSTER_LOCATION` | `us-central1` | GKE region |
| `TF_STATE_BUCKET` | `my-terraform-state` | GCS bucket for state |
| `ARGOCD_HOST` | `argocd.example.com` | ArgoCD UI hostname |
| `LETSENCRYPT_EMAIL` | `admin@example.com` | For cert-manager |

### Spoke Cluster Secrets

| Secret | Value | Description |
|--------|-------|-------------|
| `SPOKE_CLUSTERS` | `spoke-1,spoke-2,spoke-3` | Comma-separated list |
| `HUB_PRINCIPAL_ADDRESS` | From hub deployment | Principal IP/hostname |
| `HUB_PRINCIPAL_PORT` | `443` | Principal port |

Per-cluster secrets (repeat for each spoke):

| Secret | Example | Description |
|--------|---------|-------------|
| `SPOKE_1_NETBIRD_IP` | `100.64.1.10` | From section 5 |
| `SPOKE_1_CA_CERT` | `LS0tLS...` | From section 5 |
| `SPOKE_1_CLIENT_CERT` | `LS0tLS...` | From section 5 |
| `SPOKE_1_CLIENT_KEY` | `LS0tLS...` | From section 5 |

---

## 7. Testing Netbird Connectivity

Before running workflows, test connectivity manually:

### Test 1: Verify Spoke Clusters in Netbird

```bash
# Check Netbird dashboard
# Go to Peers → Filter by "spoke-clusters" group
# Verify all spoke cluster nodes appear with "Connected" status
```

### Test 2: Test Connectivity from Another Netbird Peer

```bash
# Join Netbird from your local machine (for testing)
netbird up --setup-key <NETBIRD_SETUP_KEY_RUNNERS>

# Ping spoke cluster
ping <SPOKE_NETBIRD_IP>

# Test Kubernetes API access
curl -k https://<SPOKE_NETBIRD_IP>:6443/version

# Expected: Kubernetes version JSON
```

### Test 3: Test kubectl with Netbird IP

```bash
# Configure kubectl with Netbird IP
kubectl config set-cluster spoke-1 \
  --server=https://<SPOKE_NETBIRD_IP>:6443 \
  --certificate-authority=<path-to-ca-cert>

kubectl config set-credentials spoke-1-admin \
  --client-certificate=<path-to-client-cert> \
  --client-key=<path-to-client-key>

kubectl config set-context spoke-1 \
  --cluster=spoke-1 \
  --user=spoke-1-admin

# Test access
kubectl get nodes --context spoke-1

# Expected: List of cluster nodes
```

---

## 8. Troubleshooting

### Problem: Spoke cluster not appearing in Netbird dashboard

**Cause**: Netbird client not running or setup key incorrect

**Solution**:
```bash
# Check Netbird status on spoke node
netbird status

# If not connected, restart
sudo systemctl restart netbird

# Check logs
sudo journalctl -u netbird -f
```

### Problem: Cannot ping spoke cluster Netbird IP

**Cause**: ACL rules blocking traffic or firewall issues

**Solution**:
1. Check ACL rules in Netbird dashboard
2. Verify `github-runners` → `spoke-clusters` rule exists
3. Check local firewall:
   ```bash
   # On spoke node
   sudo iptables -L -n | grep 6443
   ```

### Problem: Kubernetes API not accessible via Netbird IP

**Cause**: API server not listening on Netbird interface

**Solution**:
```bash
# Check API server binding
sudo netstat -tlnp | grep 6443

# API server should listen on 0.0.0.0:6443 or Netbird IP

# If not, update kube-apiserver config to bind to all interfaces
# Location depends on your Kubernetes distribution:
# - kubeadm: /etc/kubernetes/manifests/kube-apiserver.yaml
# - k3s: /etc/rancher/k3s/config.yaml
# - kind: Not recommended for Netbird (uses Docker networking)
```

### Problem: Setup key expired or usage limit reached

**Solution**:
1. Go to Netbird Dashboard → Setup Keys
2. Create new setup key
3. Update GitHub Secrets or spoke cluster configuration

### Problem: Ephemeral runners not cleaning up

**Cause**: Auto-cleanup not configured

**Solution**:
1. Check setup key configuration
2. Verify "Ephemeral" type selected
3. Set "Auto-cleanup after" to 10 minutes
4. Existing peers can be manually removed from Dashboard → Peers

---

## Next Steps

Once Netbird setup is complete:

1. ✅ Spoke clusters registered in Netbird
2. ✅ Setup keys created and stored in GitHub Secrets
3. ✅ ACLs configured
4. ✅ Spoke Netbird IPs and credentials stored in GitHub Secrets

**You're ready to run the GitHub Actions workflows!**

See: [GitHub Actions Deployment Guide](github-actions-deployment-guide.md) for workflow usage.
