# Cert-Manager Certificate Automation

Automated TLS certificate management and issuance for Kubernetes workloads with multi-cloud support.

**Official Documentation**: [cert-manager.io/docs](https://cert-manager.io/docs/)  
**GitHub Repository**: [cert-manager/cert-manager](https://github.com/cert-manager/cert-manager)

## Features

- **Multi-Cloud Support**: Deploy on GKE, EKS, AKS, or any Kubernetes cluster
- **Automated Issuance**: Certificate provisioning from Let's Encrypt and other ACME providers
- **Automatic Renewal**: Certificates renewed before expiration with zero downtime
- **Ingress Integration**: Seamless TLS termination for Ingress resources
- **Multiple Issuers**: Support for production and staging Let's Encrypt environments
- **CI/CD Ready**: GitHub Actions workflows for automated multi-cloud deployments

## Deployment

### Automated (Terraform + GitHub Actions)
Recommended approach with infrastructure-as-code and CI/CD automation.

**Supports:** GKE, EKS, AKS  
**Features:** Multi-cloud backend, automated authentication, zero-downtime upgrades

See [Terraform deployment guide](../docs/cert-manager-terraform-deployment.md)

### Manual (Helm & kubectl)
Command-line deployment with manual configuration.

See [Manual deployment guide](../docs/cert-manager-manual-deployment.md)

## Operations

- **Adopting Existing Installation**: [Adoption guide](../docs/adopting-cert-manager.md)
- **Troubleshooting**: [Troubleshooting guide](../docs/troubleshooting-cert-manager.md)

