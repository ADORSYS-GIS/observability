# NGINX Ingress Controller Manual Deployment

Direct Helm-based deployment for command-line control.

Recommended for local development environments, learning, or clusters without CI/CD infrastructure. This method provides step-by-step control over Layer 7 load balancing deployment.

**Official Documentation**: [NGINX Inc. Ingress Controller](https://docs.nginx.com/nginx-ingress-controller/) | **GitHub**: [nginxinc/kubernetes-ingress](https://github.com/nginxinc/kubernetes-ingress) | **Helm Repository**: `https://helm.nginx.com/stable` | **Version**: `2.4.2`

---

## Prerequisites

Required tools and versions:

| Tool | Version | Verification Command |
|------|---------|---------------------|
| kubectl | ≥ 1.24 | `kubectl version --client` |
| Helm | ≥ 3.12 | `helm version` |
| Kubernetes cluster | ≥ 1.24 | `kubectl version` |

**Cloud Provider Requirements:**
- LoadBalancer support: Cluster must provision external IPs (GKE, EKS, AKS, or on-premise with MetalLB)
- Cluster access: `kubectl cluster-info` returns cluster information

**Note:** The ingress controller requires an external IP to route internet traffic to services. Cloud providers (GKE, EKS, AKS) automatically provision LoadBalancers. On-premise clusters require MetalLB or similar LoadBalancer implementation.

---

## Installation

### Step 1: Verify Cluster Context

Confirm connection to the correct cluster:

```bash
kubectl config current-context

kubectl cluster-info

kubectl get nodes
```

To switch to a different cluster context:
```bash
kubectl config get-contexts
kubectl config use-context <context-name>
```

---

### Step 2: Add Helm Repository

Add the official NGINX Inc. stable Helm repository:

```bash
helm repo add nginx-stable https://helm.nginx.com/stable
helm repo update
```

Verify repository addition:
```bash
helm search repo nginx-stable/nginx-ingress
```

---

### Step 3: Install NGINX Ingress Controller

Deploy with recommended configuration:

```bash
helm install nginx-monitoring nginx-stable/nginx-ingress \
  --namespace ingress-nginx \
  --create-namespace \
  --version 2.4.2 \
  --set controller.ingressClass.name=nginx \
  --set controller.service.type=LoadBalancer
```

This command:
- Creates `ingress-nginx` namespace
- Deploys NGINX controller (2 replicas by default for high availability)
- Creates LoadBalancer service to obtain external IP from cloud provider
- Registers `nginx` IngressClass for routing
- Configures RBAC and service accounts

Installation typically completes in 1-3 minutes, depending on LoadBalancer provisioning time.

**Note:** The release name `nginx-monitoring` allows for multiple ingress controller deployments if needed.

---

### Step 4: Verify Installation

Check pod status:

```bash
kubectl get pods -n ingress-nginx
```

All pods should be in Running status:

![NGINX Ingress Controller pods running](img/ingress-nginx-pods.png)

Wait for pods to reach ready state:
```bash
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=nginx-ingress \
  -n ingress-nginx \
  --timeout=300s
```

---

Check LoadBalancer service status:

```bash
kubectl get svc -n ingress-nginx
```

The `EXTERNAL-IP` field should show a public IP address (not `<pending>`):

![NGINX Ingress Controller LoadBalancer service](img/ingress-nginx-loadbalancer.png)

**If still pending:**
- Allow 2-3 minutes for cloud provider provisioning
- Check cloud provider quotas for external IPs and load balancers
- Verify IAM permissions for LoadBalancer creation

Save the external IP for DNS configuration:
```bash
EXTERNAL_IP=$(kubectl get svc -n ingress-nginx \
  nginx-monitoring-ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
  
echo "External IP: $EXTERNAL_IP"
```

---

Verify IngressClass creation:

```bash
kubectl get ingressclass nginx
```

You should see the IngressClass:

![NGINX IngressClass created](img/ingress-nginx-ingressclass.png)

---

## Usage

For usage examples and Ingress configuration, see [NGINX Ingress Controller README](../ingress-controller/README.md#usage-examples).

---

## DNS Configuration

Point your domain to the LoadBalancer external IP.

**Step 1: Get external IP**
```bash
kubectl get svc -n ingress-nginx \
  nginx-monitoring-ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

**Step 2: Create DNS A records**

Configure DNS records in your DNS provider (Cloudflare, Route53, Google Domains, etc.):

| Type | Name | Value |
|------|------|-------|
| A | `myapp.example.com` | `<EXTERNAL-IP>` |
| A | `*.example.com` | `<EXTERNAL-IP>` (wildcard for subdomains) |

**Step 3: Wait for DNS propagation**

DNS propagation typically takes 5-30 minutes.

Test DNS resolution:
```bash
dig myapp.example.com
nslookup myapp.example.com
```

**Step 4: Test connectivity**
```bash
curl -v http://myapp.example.com
```

---

## Upgrading Ingress Controller

Update to a newer version:

```bash
# Update Helm repository
helm repo update

# Check available versions
helm search repo nginx-stable/nginx-ingress --versions

# Upgrade to new version
helm upgrade nginx-monitoring nginx-stable/nginx-ingress \
  --namespace ingress-nginx \
  --version 2.5.0
```

Helm performs a rolling update with zero downtime.

---

## Uninstalling

**Warning:** Uninstalling removes the LoadBalancer and breaks all Ingress-based routing.

```bash
# Uninstall Helm release
helm uninstall nginx-monitoring -n ingress-nginx

# Delete namespace
kubectl delete namespace ingress-nginx
```

The LoadBalancer external IP is released. All Ingress resources become non-functional.

---

## Troubleshooting

For detailed troubleshooting, see [Troubleshooting Guide](troubleshooting-ingress-controller.md).

**Quick verification:**
```bash
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx nginx-monitoring-ingress-nginx-controller
kubectl get ingress -A
```

---

## Related Documentation

- [GitHub Actions Deployment](ingress-controller-github-actions.md) - Automated CI/CD deployment
- [Terraform CLI Deployment](ingress-controller-terraform-deployment.md) - Infrastructure as Code deployment
- [cert-manager Manual Deployment](cert-manager-manual-deployment.md) - TLS automation
- [Troubleshooting Guide](troubleshooting-ingress-controller.md) - Advanced debugging
- [Adopting Existing Installation](adopting-ingress-controller.md) - Migration guide

---

**Official Documentation**: [NGINX Inc. Ingress Controller](https://docs.nginx.com/nginx-ingress-controller/) | **Helm Repository**: `https://helm.nginx.com/stable`
