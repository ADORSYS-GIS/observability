# Cert-Manager Certificate Automation

Automated TLS certificate management and issuance for Kubernetes workloads.

**Official Documentation**: [cert-manager.io/docs](https://cert-manager.io/docs/)  
**GitHub Repository**: [cert-manager/cert-manager](https://github.com/cert-manager/cert-manager)

## Features

- **Automated Issuance**: Certificate provisioning from Let's Encrypt and other ACME providers
- **Automatic Renewal**: Certificates renewed before expiration with zero downtime
- **Ingress Integration**: Seamless TLS termination for Ingress resources
- **Multiple Issuers**: Support for production and staging Let's Encrypt environments

## Deployment

### Automated (Terraform)
Recommended approach with infrastructure-as-code management.

See [Terraform deployment guide](../docs/cert-manager-terraform-deployment.md)

### Manual (Helm & kubectl)
Command-line deployment with manual configuration.

See [Manual deployment guide](../docs/cert-manager-manual-deployment.md)

## Operations

- **Adopting Existing Installation**: [Adoption guide](../docs/adopting-cert-manager.md)
- **Troubleshooting**: [Troubleshooting guide](../docs/troubleshooting-cert-manager.md)

