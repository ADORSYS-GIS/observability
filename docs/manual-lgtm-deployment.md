# LGTM Stack Manual Deployment

Docker Compose configuration for local development, testing, and proof-of-concept environments.

**Official Documentation**: [Grafana Loki](https://grafana.com/docs/loki/latest/) | [Grafana Mimir](https://grafana.com/docs/mimir/latest/) | [Grafana Tempo](https://grafana.com/docs/tempo/latest/) | [Grafana](https://grafana.com/docs/grafana/latest/)

> **Looking for Production?** Use the [Terraform Kubernetes Deployment](lgtm-stack-terraform-deployment.md).

---

## Prerequisites

| Requirement | Details |
|-------------|---------|
| **Docker Engine** | ≥ 20.10 |
| **Docker Compose** | ≥ 2.0 |
| **Resources** | 4GB RAM, 10GB Disk (Minimum) |

### Network Configuration
This deployment connects to an external `netbird_netbird` network (common in this environment).

```bash
# Create if missing
docker network create netbird_netbird
```

---

## Deployment

### Step 1: Start Services
```bash
cd lgtm-stack/manual
docker compose up -d
```

### Step 2: Components Overview

| Service | Port | Purpose |
|---------|------|---------|
| **Grafana** | `3000` | Visualization |
| **Loki** | `3100` | Log Aggregation |
| **Prometheus**| `9090` | Metrics |
| **Alloy** | `12345`| Telemetry Collector |

---

## Verification

### Check Status
```bash
docker compose ps
# Verify all services are "Up" and "healthy"
```

### Access Grafana
- **URL**: `http://localhost:3000`
- **User**: `admin`
- **Pass**: `admin` (Change on first login)

### Verify Datasources
Navigate to **Connections > Data Sources** in Grafana:
1. **Prometheus**: Click **Save & test**. Expect: *"Successfully queried the Prometheus API"*.
2. **Loki**: Click **Save & test**. Expect: *"Data source connected"*.

---

## Testing Connectivity

### Send Manual Logs (Loki)
```bash
TIMESTAMP=$(date +%s)000000000
curl -H "Content-Type: application/json" \
  -XPOST http://localhost:3100/loki/api/v1/push \
  --data-raw "{\"streams\":[{\"stream\":{\"job\":\"test\"},\"values\":[[\"$TIMESTAMP\",\"manual test log\"]]}]}"
```
Query in Grafana: `{job="test"}`

### Query Metrics (Prometheus)
```bash
curl -G http://localhost:9090/api/v1/query --data-urlencode 'query=up'
```

---

## Management Operations

| Action | Command | Note |
|--------|---------|------|
| **Stop** | `docker compose stop` | Preserves containers |
| **Restart** | `docker compose restart` | Quick reboot |
| **Destroy** | `docker compose down` | Removes containers |
| **Reset** | `docker compose down -v` | **DELETES ALL DATA** |

---

## Configuration

Key files in `lgtm-stack/manual/`:
- `docker-compose.yaml`: Service definitions
- `alloy-config.yaml`: Collector config
- `loki-config.yaml`: Log retention (`retention_period: 168h`)
- `prometheus.yml`: Scrape targets (`retention: 15d`)

---

## Troubleshooting

### "Network netbird_netbird not found"
**Fix**: `docker network create netbird_netbird`

### "Bind: address already in use"
**Fix**: Modify host port in `docker-compose.yaml`.
```yaml
ports:
  - "3001:3000" # Map host 3001 to container 3000
```

### Datasource Errors
**Fix**: Ensure standard service names are used (e.g., `loki`, `prometheus`) within the Docker network context.
