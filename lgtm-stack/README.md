# LGTM Observability Stack

Comprehensive observability platform providing correlated metrics, logs, and traces for complete system visibility.

**Official Documentation**: [Grafana Loki](https://grafana.com/docs/loki/latest/) | [Grafana Mimir](https://grafana.com/docs/mimir/latest/) | [Grafana Tempo](https://grafana.com/docs/tempo/latest/) | [Grafana](https://grafana.com/docs/grafana/latest/)  
**GitHub Repository**: [grafana/loki](https://github.com/grafana/loki) | [grafana/mimir](https://github.com/grafana/mimir) | [grafana/tempo](https://github.com/grafana/tempo)

## Features

- **Unified Observability**: Integrated logs (Loki), metrics (Mimir), and traces (Tempo) with correlation
- **Scalable Storage**: Cloud-native storage backends (GCS, S3, Azure Blob) or PersistentVolumes
- **Multi-Cloud Support**: Deploy on GKE, EKS, AKS, or any Kubernetes cluster
- **Production Ready**: High availability, auto-scaling, and long-term data retention
- **Grafana Integration**: Pre-configured dashboards and datasources for immediate insights

## Deployment

### Automated (Terraform)
Recommended approach with infrastructure-as-code management.

See [Terraform deployment guide](../docs/lgtm-stack-terraform-deployment.md)

### Manual (Docker Compose)
Local development and testing with Docker containers.

See [Manual deployment guide](../docs/manual-lgtm-deployment.md)

### GitHub Actions (CI/CD)
Fully automated deployment with GitHub Actions workflows.

See [GitHub Actions deployment guide](../docs/lgtm-stack-github-actions.md)

## Operations

- **Testing & Verification**: [Testing guide](../docs/testing-monitoring-stack-deployment.md)
- **Adopting Existing Stack**: [Adoption guide](../docs/adopting-lgtm-stack.md)
- **Troubleshooting**: [Troubleshooting guide](../docs/troubleshooting-lgtm-stack.md)
- **Alloy Configuration**: [Alloy configuration guide](../docs/alloy-config.md)

## Components

| Component | Purpose | Storage Backend |
|-----------|---------|----------------|
| **Grafana** | Visualization and analytics platform | - |
| **Loki** | Horizontally-scalable log aggregation | Cloud storage or PV |
| **Tempo** | High-volume distributed tracing backend | Cloud storage or PV |
| **Mimir** | Long-term Prometheus metrics storage | Cloud storage or PV |
| **Prometheus** | Metrics collection and scraping | Remote write to Mimir |
| **Alloy** | OpenTelemetry collector for telemetry pipeline | - |
