# LGTM Stack

Comprehensive observability platform consisting of **L**oki, **G**rafana, **T**empo, and **M**imir.

This stack provides correlated logs, metrics, and traces with long-term object storage retention, fully integrated with NGINX Ingress and Cert-Manager for secure access.

**Official Documentation**: [Grafana Loki](https://grafana.com/docs/loki/latest/) | [Grafana Mimir](https://grafana.com/docs/mimir/latest/) | [Grafana Tempo](https://grafana.com/docs/tempo/latest/) | [Grafana](https://grafana.com/docs/grafana/latest/)  
**GitHub**: [grafana/loki](https://github.com/grafana/loki) | [grafana/mimir](https://github.com/grafana/mimir) | [grafana/tempo](https://github.com/grafana/tempo)

---

## Features

- **Unified Observability**: Seamless correlation between Logs (Loki), Metrics (Mimir), and Traces (Tempo).
- **Scalable Storage**: Cloud-native object storage backend (GCS, S3, Azure Blob) for cost-effective retention.
- **Multi-Cloud Ready**: Deploy on GKE, EKS, AKS, or any Kubernetes cluster.
- **Secure Access**: Automated TLS via cert-manager and NGINX Ingress integration.

---

## Deployment Options

Choose your preferred deployment approach:

| Method | Guide | Description |
|--------|-------|-------------|
| **Terraform CLI** | [Terraform Deployment](../docs/lgtm-stack-terraform-deployment.md) | **Recommended**. Complete Infrastructure-as-Code with remote state management. |
| **GitHub Actions** | [Automated CI/CD](../docs/lgtm-stack-github-actions.md) | Fully automated deployment pipelines triggered by pull requests. |
| **Manual** | [Manual Deployment](../docs/manual-lgtm-deployment.md) | Local development and testing using Docker Compose. |

---

## Components

| Component | Purpose | URL (Default) |
|-----------|---------|---------------|
| **Grafana** | Visualization & Dashboards | `https://grafana.example.com` |
| **Loki** | Log Aggregation | `https://loki.example.com` |
| **Mimir** | Metrics Storage (Prometheus) | `https://mimir.example.com` |
| **Tempo** | Distributed Tracing | `https://tempo.example.com` |
| **Prometheus** | Metrics Collection | `https://prometheus.example.com` |

---

## Operations

- [Adopting Existing Stack](../docs/adopting-lgtm-stack.md) - Migrate existing monitoring stacks to Terraform management.
- [Troubleshooting Guide](../docs/troubleshooting-lgtm-stack.md) - Common issues and resolutions.
- [Alloy Configuration](../docs/alloy-config.md) - Configure the OpenTelemetry collector.
- [Testing & Verification](../docs/testing-monitoring-stack-deployment.md) - Validation procedures.

---

## Usage Example

### Accessing Dashboards

1.  **Login**: Navigate to your Grafana URL (e.g., `https://grafana.example.com`).
2.  **Credentials**: Log in with `admin` and the password configured in `terraform.tfvars`.
3.  **Explore**: Go to **Explore** in the sidebar.

### Sample Queries

**Logs (Loki):**
```logql
{namespace="lgtm"} |= "error"
```

**Metrics (Mimir):**
```promql
sum(rate(container_cpu_usage_seconds_total{namespace="lgtm"}[5m])) by (pod)
```

**Traces (Tempo):**
Select "Tempo" datasource and enter a Trace ID to visualize the request path.

---

## Additional Resources

- [Terraform State Management](../docs/terraform-state-management.md)
