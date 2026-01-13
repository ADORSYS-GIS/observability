# LGTM Observability Stack

Comprehensive observability platform providing correlated metrics, logs, and traces for complete system visibility.

## Components

| Component | Purpose | Official Docs |
|-----------|---------|---------------|
| **Grafana** | Visualization and analytics platform | [docs.grafana.com](https://grafana.com/docs/grafana/latest/) |
| **Loki** | Horizontally-scalable log aggregation | [grafana.com/docs/loki](https://grafana.com/docs/loki/latest/) |
| **Tempo** | High-volume distributed tracing backend | [grafana.com/docs/tempo](https://grafana.com/docs/tempo/latest/) |
| **Mimir** | Long-term Prometheus metrics storage | [grafana.com/docs/mimir](https://grafana.com/docs/mimir/latest/) |
| **Alloy** | OpenTelemetry collector for telemetry pipeline | [grafana.com/docs/alloy](https://grafana.com/docs/alloy/latest/) |

## Deployment

### Automated (Terraform)
Recommended for production environments.

See [Terraform deployment guide](../docs/kubernetes-observability.md)

### Manual (Helm)
For granular component control.

See [Manual deployment guide](../docs/manual-lgtm-deployment.md)

## Configuration & Operations

- **Alloy Configuration**: [Alloy configuration guide](../docs/alloy-config.md)
- **Testing & Verification**: [Testing guide](../docs/testing-monitoring-stack-deployment.md)
- **Adopting Existing Stack**: [Adoption guide](../docs/adopting-lgtm-stack.md)
- **Troubleshooting**: [Troubleshooting guide](../docs/troubleshooting-lgtm-stack.md)
