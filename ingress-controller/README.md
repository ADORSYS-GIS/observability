# NGINX Ingress Controller

External traffic management and load balancing for Kubernetes services with multi-cloud support.

**Official Documentation**: [kubernetes.github.io/ingress-nginx](https://kubernetes.github.io/ingress-nginx/)  
**GitHub Repository**: [kubernetes/ingress-nginx](https://github.com/kubernetes/ingress-nginx)

## Features

- **Multi-Cloud Support**: Deploy on GKE, EKS, AKS, or any Kubernetes cluster
- **Load Balancing**: Intelligent traffic distribution to backend services
- **SSL/TLS Termination**: HTTPS handling with cert-manager integration
- **Path-Based Routing**: Request routing based on hostnames and URL paths
- **WebSocket Support**: Real-time bidirectional communication
- **Rate Limiting**: Request throttling and DDoS protection
- **CI/CD Ready**: GitHub Actions workflows for automated multi-cloud deployments

## Deployment

### Automated (Terraform + GitHub Actions)
Recommended approach with infrastructure-as-code and CI/CD automation.

**Supports:** GKE, EKS, AKS  
**Features:** Multi-cloud backend, automated authentication, LoadBalancer provisioning, zero-downtime upgrades

See [Terraform deployment guide](../docs/ingress-controller-terraform-deployment.md)

### Manual (Helm)
Command-line deployment with manual configuration.

See [Manual deployment guide](../docs/ingress-controller-manual-deployment.md)

## Operations

- **Adopting Existing Installation**: [Adoption guide](../docs/adopting-ingress-controller.md)
- **Troubleshooting**: [Troubleshooting guide](../docs/troubleshooting-ingress-controller.md)

## Service Exposure

The controller provisions a LoadBalancer service that serves as the cluster's external entry point for HTTP/HTTPS traffic.