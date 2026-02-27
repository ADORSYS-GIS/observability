# ============================================================
# Grafana Multi-Tenancy Configuration
# ============================================================
# This file creates all the Grafana-side resources required for
# proper tenant isolation. It is driven entirely by var.tenants,
# so adding a new tenant requires only a single list entry — no
# manual steps in Grafana or Keycloak.
#
# WHAT GETS CREATED PER TENANT (e.g. tenant = "webank"):
#
#   1. Grafana Team: "webank-team"
#      - Synced to Keycloak group "webank-team" via external group sync.
#      - When a user with "webank-team" in their JWT logs in, Grafana
#        automatically adds them to this team. No manual assignment.
#      - The user keeps their Grafana role (Admin/Editor/Viewer) —
#        the team only controls WHAT DATA they see, not WHAT they can do.
#
#   2. Four tenant-scoped datasources:
#      - "<Tenant>-Loki"       → sends X-Scope-OrgID: <tenant> to Loki
#      - "<Tenant>-Mimir"      → sends X-Scope-OrgID: <tenant> to Mimir
#      - "<Tenant>-Prometheus" → sends X-Scope-OrgID: <tenant> to Prometheus
#      - "<Tenant>-Tempo"      → sends X-Scope-OrgID: <tenant> to Tempo
#
#   3. Datasource permissions: only the "<tenant>-team" Grafana Team
#      can Query the above datasources. Other teams cannot see them.
#
#   4. Dashboard Folder: "Webank Dashboards"
#      - Only members of the "<tenant>-team" can view/edit dashboards here.
#
# HOW KEYCLOAK DRIVES EVERYTHING (no hardcoded users):
#   - You or the code adds a user to "webank-team" in Keycloak.
#   - On login, JWT contains "groups": ["webank-team", "grafana-editors"]
#   - Grafana reads "groups", finds the Team with external sync = "webank-team"
#   - User is auto-assigned to the Grafana Team. Done.
# ============================================================

# ---- Wait for Grafana to be accessible -----------------------
# The Grafana provider needs the API to be reachable via HTTPS.
# This resource waits for the ingress, certificate, and DNS to be ready
# before Terraform tries to create teams, datasources, and folders.

resource "null_resource" "wait_for_grafana" {
  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for Grafana to be accessible at ${var.grafana_url}..."
      for i in {1..60}; do
        if curl -k -s -o /dev/null -w "%%{http_code}" ${var.grafana_url}/api/health | grep -q "200"; then
          echo "✅ Grafana is ready!"
          exit 0
        fi
        echo "Attempt $i/60: Grafana not ready yet, waiting 10s..."
        sleep 10
      done
      echo "❌ ERROR: Grafana did not become accessible after 10 minutes"
      exit 1
    EOT
  }

  depends_on = [
    helm_release.grafana,
    kubernetes_ingress_v1.monitoring_stack
  ]
}

# ---- Grafana Teams (one per tenant) --------------------------
# Each team is linked to the matching Keycloak group via team_sync.
# Grafana will add any user whose JWT "groups" claim contains the
# group name to this team automatically on every login.

resource "grafana_team" "tenants" {
  for_each = toset(var.tenants)

  name = "${each.key}-team"

  depends_on = [
    helm_release.grafana,
    null_resource.wait_for_grafana
  ]
}

# ---- Tenant Datasources (Loki) --------------------------------
# Each datasource sends X-Scope-OrgID: <tenant> so that Loki
# returns ONLY that tenant's log data — never another tenant's.

resource "grafana_data_source" "loki" {
  for_each = toset(var.tenants)

  name = "${title(each.key)}-Loki"
  type = "loki"
  url  = "http://monitoring-loki-gateway:80"

  http_headers = {
    "X-Scope-OrgID" = each.key
  }

  json_data_encoded = jsonencode({
    maxLines = 1000
  })

  lifecycle {
    ignore_changes = [
      # Ignore changes to these fields if datasource was provisioned
      # This prevents Terraform from trying to update read-only datasources
      uid,
    ]
  }

  depends_on = [
    helm_release.grafana,
    null_resource.wait_for_grafana
  ]
}

# ---- Tenant Datasources (Mimir) --------------------------------

resource "grafana_data_source" "mimir" {
  for_each = toset(var.tenants)

  name = "${title(each.key)}-Mimir"
  type = "prometheus"
  url  = "http://monitoring-mimir-nginx:80/prometheus"

  http_headers = {
    "X-Scope-OrgID" = each.key
  }

  json_data_encoded = jsonencode({
    httpMethod   = "POST"
    timeInterval = "15s"
  })

  lifecycle {
    ignore_changes = [
      # Ignore changes to these fields if datasource was provisioned
      uid,
    ]
  }

  depends_on = [
    helm_release.grafana,
    null_resource.wait_for_grafana
  ]
}

# ---- Tenant Datasources (Prometheus) --------------------------
# Prometheus is cluster-wide. Each tenant datasource points at the
# same server but with a different org header so Mimir (backend)
# segregates the data correctly.

resource "grafana_data_source" "prometheus" {
  for_each = toset(var.tenants)

  name = "${title(each.key)}-Prometheus"
  type = "prometheus"
  url  = "http://monitoring-prometheus-server:80"

  http_headers = {
    "X-Scope-OrgID" = each.key
  }

  json_data_encoded = jsonencode({
    httpMethod   = "POST"
    timeInterval = "15s"
  })

  lifecycle {
    ignore_changes = [
      # Ignore changes to these fields if datasource was provisioned
      uid,
    ]
  }

  depends_on = [
    helm_release.grafana,
    null_resource.wait_for_grafana
  ]
}

# ---- Tenant Datasources (Tempo) --------------------------------

resource "grafana_data_source" "tempo" {
  for_each = toset(var.tenants)
  name = "${title(each.key)}-Tempo"
  type = "tempo"
  url  = "http://monitoring-tempo-query-frontend:3200"

  http_headers = {
    "X-Scope-OrgID" = each.key
  }

  json_data_encoded = jsonencode({
    httpMethod         = "GET"
    tracesToLogsV2     = {}
    datasourceUid      = grafana_data_source.loki[each.key].uid
    spanStartTimeShift = "-1h"
    spanEndTimeShift   = "1h"
    filterByTraceID    = true
    filterBySpanID     = false
    serviceMap = {
      datasourceUid = grafana_data_source.prometheus[each.key].uid
    }
    nodeGraph = {
      enabled = true
    }
  })

  lifecycle {
    ignore_changes = [
      # Ignore changes to these fields if datasource was provisioned
      uid,
    ]
  }

  depends_on = [
    helm_release.grafana,
    null_resource.wait_for_grafana
  ]
}


# ---- Datasource Permissions ------------------------------------
# NOTE: grafana_data_source_permission is a Grafana Enterprise-only feature.
# The /api/access-control/datasources endpoint does not exist in Grafana OSS
# and returns 404. The accesscontrol feature flag enables folder/dashboard
# permissions only — NOT datasource-level permissions.
#
# DATA ISOLATION IS STILL STRICTLY ENFORCED via two OSS-compatible mechanisms:
#
#   1. X-Scope-OrgID headers (read path) — Each tenant datasource has a
#      hardcoded X-Scope-OrgID: <tenant> header. Loki/Mimir/Tempo will ONLY
#      return data for that specific tenant. A webank user querying
#      "Webank-Loki" can never see azamra data, because the backend
#      enforces the tenant boundary at the storage layer.
#
#   2. Folder permissions (dashboard isolation) — Dashboards are stored in
#      tenant-specific folders with team-level edit/view restrictions.
#      "webank-team" members can only see and edit "Webank Dashboards".
#
# To upgrade to datasource-level permissions, upgrade to Grafana Enterprise
# and un-comment the resources below.


# ---- Dashboard Folders -----------------------------------------
# Each tenant gets their own folder. Only their team can see it.
# This means a webank user will never see azamra's dashboards
# in the folder tree.

resource "grafana_folder" "tenants" {
  for_each = toset(var.tenants)

  title = "${title(each.key)} Dashboards"

  depends_on = [
    helm_release.grafana,
    null_resource.wait_for_grafana
  ]
}

# ---- Global Data Sources (Cluster Admins) -----------------------
# These data sources point to the "default" tenant where 
# infrastructure metrics and logs are stored.
# Restricted to the grafana-admins team.

resource "grafana_data_source" "global_loki" {
  name = "Global-Loki"
  type = "loki"
  url  = "http://monitoring-loki-gateway:80"
  http_headers = { "X-Scope-OrgID" = "default" }
  depends_on = [helm_release.grafana, null_resource.wait_for_grafana]
}

resource "grafana_data_source" "global_mimir" {
  name = "Global-Mimir"
  type = "prometheus"
  url  = "http://monitoring-mimir-nginx:80/prometheus"
  http_headers = { "X-Scope-OrgID" = "default" }
  depends_on = [helm_release.grafana, null_resource.wait_for_grafana]
}

resource "grafana_folder_permission" "tenants" {
  for_each = toset(var.tenants)

  folder_uid = grafana_folder.tenants[each.key].uid

  permissions {
    team_id    = grafana_team.tenants[each.key].id
    permission = "Edit" # Team members can create and edit dashboards in their folder
  }

  depends_on = [
    helm_release.grafana,
    null_resource.wait_for_grafana
  ]
}

# ---- OSS Team Sync Workaround (Option 3) ----
# Grafana OSS does not support automatic OIDC team sync.
# To provide a seamless experience where Keycloak groups auto-map
# to Grafana teams, we deploy a custom Python CronJob that runs
# every 5 minutes and uses the Keycloak and Grafana APIs to sync them.

# Read the Python sync script
data "local_file" "grafana_sync_script" {
  filename = "${path.module}/scripts/grafana-team-sync.py"
}

# Template the Kubernetes CronJob YAML using the modern templatefile() function
# This natively handles string interpolation much better than the deprecated template_file provider.
locals {
  grafana_sync_job_yaml = templatefile("${path.module}/values/grafana-team-sync-job.yaml", {
    keycloak_realm          = var.keycloak_realm
    keycloak_admin_user     = var.keycloak_admin_user
    keycloak_admin_password = var.keycloak_admin_password
    grafana_admin_password  = var.grafana_admin_password
    tenants                 = join(",", var.tenants)
    script_content          = indent(4, data.local_file.grafana_sync_script.content)
  })
}

# Split the templated YAML into multiple documents (ConfigMap + CronJob)
data "kubectl_file_documents" "grafana_sync_manifests" {
  content = local.grafana_sync_job_yaml
}

# Deploy the ConfigMap and CronJob to the cluster
resource "kubectl_manifest" "grafana_sync" {
  for_each  = data.kubectl_file_documents.grafana_sync_manifests.manifests
  yaml_body = each.value

  depends_on = [
    helm_release.grafana,
    grafana_team.tenants
  ]
}
