# ArgoCD Agent (Hub-and-Spoke)

Multi-cluster GitOps with centralized control plane and distributed agents. Single ArgoCD UI manages applications across unlimited Kubernetes clusters.

**Official Documentation**: [argocd-agent.readthedocs.io](https://argocd-agent.readthedocs.io/)  
**GitHub Repository**: [argoproj-labs/argocd-agent](https://github.com/argoproj-labs/argocd-agent)

## Architecture

Hub-and-spoke pattern where hub cluster runs ArgoCD control plane (UI + Principal), spoke clusters run lightweight agents that connect via gRPC to deploy applications.

**Use ArgoCD Agent when**:
- Managing 5+ clusters across networks/clouds
- Clusters behind NAT/firewalls need centralized GitOps
- Need local repo servers per cluster for compliance

**Use Standard ArgoCD when**:
- < 5 clusters in same VPC with full mesh connectivity
- Need full UI features (terminal, pod logs, tree view)

See [Architecture guide](../docs/argocd-agent-architecture.md) for detailed comparison.

## Deployment

### Automated (Terraform)
Recommended for production with infrastructure-as-code.

See [Terraform deployment guide](../docs/argocd-agent-terraform-deployment.md)

### Manual (Shell Scripts)
Step-by-step deployment using `scripts/01-hub-setup.sh` through `05-verify.sh`.

See [Terraform deployment guide](../docs/argocd-agent-terraform-deployment.md#manual-deployment-scripts) for script usage.

## Configuration & Operations

- **Configuration Reference**: [All Terraform variables](../docs/argocd-agent-configuration.md)
- **Operations Guide**: [Day-2 ops, scaling, upgrades, certificates, teardown](../docs/argocd-agent-operations.md)
- **RBAC & SSO**: [Keycloak integration](../docs/argocd-agent-rbac.md)
- **Troubleshooting**: [Common issues and solutions](../docs/argocd-agent-troubleshooting.md)

## Version Compatibility

- ArgoCD Agent: v0.5.3
- Kubernetes: 1.24-1.28
- Terraform: >= 1.0
