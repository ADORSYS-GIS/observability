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

# ---- Grafana Teams (one per tenant) --------------------------
# Each team is linked to the matching Keycloak group via team_sync.
# Grafana will add any user whose JWT "groups" claim contains the
# group name to this team automatically on every login.

resource "grafana_team" "tenants" {
  for_each = toset(var.tenants)

  name = "${each.key}-team"

  # team_sync links this Grafana Team to the Keycloak group of the
  # same name. The group name MUST match what keycloak.tf creates
  # (which is "${each.key}-team" — set by Terraform, not manually).
  team_sync {
    groups = ["${each.key}-team"]
  }
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
  })
}

# ---- Datasource Permissions ------------------------------------
# Restricts each datasource to ONLY the matching team.
# Members of "webank-team" can query Webank-Loki but NOT Azamra-Loki.
#
# REQUIRES: Grafana OSS with accesscontrol feature flag enabled
# (set GF_FEATURE_TOGGLES_ENABLE: accesscontrol in grafana-values.yaml)
# OR Grafana Enterprise.

resource "grafana_data_source_permission" "loki" {
  for_each = toset(var.tenants)

  datasource_uid = grafana_data_source.loki[each.key].uid
  permissions {
    team_id    = grafana_team.tenants[each.key].id
    permission = "Query"
  }
}

resource "grafana_data_source_permission" "mimir" {
  for_each = toset(var.tenants)

  datasource_uid = grafana_data_source.mimir[each.key].uid
  permissions {
    team_id    = grafana_team.tenants[each.key].id
    permission = "Query"
  }
}

resource "grafana_data_source_permission" "prometheus" {
  for_each = toset(var.tenants)

  datasource_uid = grafana_data_source.prometheus[each.key].uid
  permissions {
    team_id    = grafana_team.tenants[each.key].id
    permission = "Query"
  }
}

resource "grafana_data_source_permission" "tempo" {
  for_each = toset(var.tenants)

  datasource_uid = grafana_data_source.tempo[each.key].uid
  permissions {
    team_id    = grafana_team.tenants[each.key].id
    permission = "Query"
  }
}

# ---- Dashboard Folders -----------------------------------------
# Each tenant gets their own folder. Only their team can see it.
# This means a webank user will never see azamra's dashboards
# in the folder tree.

resource "grafana_folder" "tenants" {
  for_each = toset(var.tenants)

  title = "${title(each.key)} Dashboards"
}

resource "grafana_folder_permission" "tenants" {
  for_each = toset(var.tenants)

  folder_uid = grafana_folder.tenants[each.key].uid

  permissions {
    team_id    = grafana_team.tenants[each.key].id
    permission = "Editor" # Team members can create and edit dashboards in their folder
  }
}
