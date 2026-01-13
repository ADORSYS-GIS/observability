# Manual LGTM Stack Deployment

Guide for manually deploying the observability stack using Docker Compose for local development or testing environments.

## Overview

This deployment runs the LGTM stack in Docker containers with minimal external dependencies. Suitable for:

- Local development and testing
- Proof-of-concept deployments
- Learning the stack architecture
- NetBird network integration scenarios

**Not recommended for production use.** For production, use the [Terraform Kubernetes deployment](kubernetes-observability.md).

## Prerequisites

- Docker Engine ≥ 20.10
- Docker Compose ≥ 2.0
- 4GB available RAM minimum
- 10GB available disk space

## Network Dependency

This deployment expects an external Docker network named `netbird_netbird` (typically created by NetBird management stack).

### Create Network (if NetBird not present)

```bash
docker network create netbird_netbird
```

## Deployment

### Step 1: Navigate to Configuration Directory

```bash
cd lgtm-stack/manual
```

### Step 2: Start Services

```bash
docker compose up -d
```

### Deployed Components

| Service | Purpose | Port |
|---------|---------|------|
| **Grafana** | Visualization dashboard | 3000 |
| **Loki** | Log aggregation | 3100 |
| **Prometheus** | Metrics collection | 9090 |
| **Alloy** | Telemetry collector | 12345 |
| **Node Exporter** | Host metrics | 9100 |
| **cAdvisor** | Container metrics | 8080 |

## Verification

### Check Service Status

```bash
docker compose ps
```

Expected output: All services with status `Up` and health `healthy` (where applicable).

![Docker Compose Status](img/monitor-netbird-stack-ps.png)

### View Logs

```bash
# All services
docker compose logs

# Specific service
docker compose logs grafana

# Follow logs
docker compose logs -f
```

## Access & Configuration

### Grafana Access

**URL**: `http://localhost:3000`

**Default Credentials**:
- Username: `admin`
- Password: `admin`

You'll be prompted to change the password on first login.

### Verify Datasources

#### Prometheus Datasource

1. Navigate to **Connections** > **Data Sources**
2. Click **Prometheus**
3. Scroll down and click **Save & test**
4. Verify success message: *"Successfully queried the Prometheus API"*

![Prometheus Datasource](img/grafana-datasource-prometheus.png)

#### Loki Datasource

1. Navigate to **Connections** > **Data Sources**
2. Click **Loki**
3. Scroll down and click **Save & test**
4. Verify success message confirming connection

![Loki Datasource](img/grafana-datasource-loki.png)

## Testing Data Ingestion

### Send Test Logs to Loki

```bash
TIMESTAMP=$(date +%s)000000000
curl -H "Content-Type: application/json" \
  -XPOST http://localhost:3100/loki/api/v1/push \
  --data-raw "{\"streams\":[{\"stream\":{\"job\":\"test\"},\"values\":[[\"$TIMESTAMP\",\"test log message\"]]}]}"
```

Verify in Grafana Explore > Loki > Query: `{job="test"}`

### Query Prometheus Metrics

```bash
curl -G http://localhost:9090/api/v1/query \
  --data-urlencode 'query=up'
```

## Management

### Stop Services

```bash
docker compose stop
```

### Restart Services

```bash
docker compose restart
```

### Remove Stack

```bash
docker compose down
```

To also remove volumes (deletes all data):

```bash
docker compose down -v
```

## Troubleshooting

### Network Not Found Error

**Symptoms**:
```
Error: network netbird_netbird not found
```

**Fix**:
```bash
docker network create netbird_netbird
```

### Port Conflicts

**Symptoms**:
```
Error: bind: address already in use
```

**Diagnosis**:
```bash
# Check what's using the port
lsof -i :3000
# or
netstat -tulpn | grep 3000
```

**Fix**: Stop conflicting service or modify port mapping in `docker-compose.yml`:

```yaml
services:
  grafana:
    ports:
      - "3001:3000"  # Change host port
```

### Container Exits Immediately

**Diagnosis**:
```bash
docker compose logs <service_name>
```

**Common causes**:
- Permission issues on mounted volumes
- Configuration file syntax errors
- Memory constraints

**Fix for permission issues**:
```bash
# Adjust ownership of data directories
sudo chown -R 10001:10001 ./data/loki
sudo chown -R 472:472 ./data/grafana
```

### Grafana Not Loading

**Check container status**:
```bash
docker compose ps grafana
docker compose logs grafana
```

**Common fixes**:
- Wait 30-60 seconds for initialization
- Clear browser cache
- Check for port conflicts
- Verify container has sufficient memory

### Datasource Connection Failures

**Diagnosis**:
```bash
# Test from Grafana container
docker compose exec grafana curl -v http://loki:3100/ready
docker compose exec grafana curl -v http://prometheus:9090/-/ready
```

**Fix**: Verify service names in datasource configuration match `docker-compose.yml` service names.

## Configuration Files

### Key Files

- `docker-compose.yml` - Service definitions
- `alloy-config.yaml` - Telemetry collector configuration
- `prometheus.yml` - Prometheus scrape configuration
- `loki-config.yaml` - Loki configuration

### Customize Retention

Edit service-specific configuration files to adjust data retention:

**Loki** (`loki-config.yaml`):
```yaml
limits_config:
  retention_period: 168h  # 7 days
```

**Prometheus** (`prometheus.yml`):
```yaml
global:
  retention: 15d
```

## Resource Requirements

### Minimum

- CPU: 2 cores
- RAM: 4GB
- Disk: 10GB

### Recommended

- CPU: 4 cores
- RAM: 8GB
- Disk: 50GB (for longer retention)

## Limitations

- **Not production-ready**: No high availability or persistence guarantees
- **Local storage only**: No object storage backend
- **Single node**: Cannot scale horizontally
- **No authentication**: Services exposed without access control

For production deployments, use the [Terraform Kubernetes deployment](kubernetes-observability.md).

## Next Steps

- Explore Grafana dashboards at `http://localhost:3000`
- Send application logs and metrics to Loki/Prometheus
- Configure Alloy collector for custom telemetry pipelines
- Review [Alloy Configuration Guide](alloy-config.md)
