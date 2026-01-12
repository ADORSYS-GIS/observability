# LGTM Stack Deployment

The **LGTM** stack is a comprehensive open-source observability platform powered by Grafana Labs. It provides unmatched correlation between metrics, logs, and traces, allowing complete visibility into your applications and infrastructure.

## Components

- **Loki**: Like Prometheus, but for logs. It is a horizontally-scalable, highly-available, multi-tenant log aggregation system.
- **Grafana**: The open observability platform for visualization and analytics.
- **Tempo**: A high-volume, minimal dependency distributed tracing backend.
- **Mimir**: Scalable long-term storage for Prometheus metrics.

## Deployment Guides

This repository provides two guides to help you deploy the stack:

### 1. Automated Deployment
For a fully automated deployment using this stack, please refer to the [observability guide](../docs/kubernetes-observability.md).

### 2. Manual Deployment
If you prefer to configure and deploy components manually, or need to understand the individual steps, please refer to the [Manual LGTM Deployment Guide](../docs/manual-lgtm-deployment.md).

## Testing & Verification
To verify that your deployment is working correctly, please refer to the [Testing Monitoring Stack Deployment Guide](../docs/testing-monitoring-stack-deployment.md).

## Configuration
For detailed configuration of the Alloy collector, please refer to the [Alloy Configuration Guide](../docs/alloy-config.md).
