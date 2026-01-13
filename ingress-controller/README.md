# NGINX Ingress Controller

External traffic management and load balancing for Kubernetes services.

**Official Documentation**: [kubernetes.github.io/ingress-nginx](https://kubernetes.github.io/ingress-nginx/)  
**GitHub Repository**: [kubernetes/ingress-nginx](https://github.com/kubernetes/ingress-nginx)

## Features

- **Load Balancing**: Intelligent traffic distribution to backend services
- **SSL/TLS Termination**: HTTPS handling with cert-manager integration
- **Path-Based Routing**: Request routing based on hostnames and URL paths
- **WebSocket Support**: Real-time bidirectional communication
- **Rate Limiting**: Request throttling and DDoS protection

## Deployment

### Automated (Terraform)
Recommended approach with infrastructure-as-code management.

See [Terraform deployment guide](../docs/ingress-controller-terraform-deployment.md)

### Manual (Helm)
Command-line deployment with manual configuration.

See [Manual deployment guide](../docs/ingress-controller-manual-deployment.md)

## Operations

- **Adopting Existing Installation**: [Adoption guide](../docs/adopting-ingress-controller.md)
- **Troubleshooting**: [Troubleshooting guide](../docs/troubleshooting-ingress-controller.md)

## Service Exposure

The controller provisions a LoadBalancer service that serves as the cluster's external entry point for HTTP/HTTPS traffic.