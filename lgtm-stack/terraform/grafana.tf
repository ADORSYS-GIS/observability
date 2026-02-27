# ============================================================
# Grafana Multi-Tenancy Configuration
# ============================================================
# Tenant lifecycle (teams, datasources, folders, permissions)
# is managed DYNAMICALLY by the grafana-team-sync CronJob.
#
# To add a new tenant:
#   1. Create a `<name>-team` group in Keycloak
#   2. Add users to that group
#   3. Wait up to 5 minutes for the sync job to run
#
# NO Terraform changes are needed to add tenants.
# ============================================================

# ---- Wait for Grafana to be accessible -----------------------

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

# ---- Global Data Sources (Cluster Admins) -----------------------
# These point to the "default" tenant where infrastructure
# metrics and logs are stored. Visible only to admin users
# (Grafana Admins can see all datasources by default).

resource "grafana_data_source" "global_loki" {
  name         = "Global-Loki"
  type         = "loki"
  url          = "http://monitoring-loki-gateway:80"
  http_headers = { "X-Scope-OrgID" = "default" }
  depends_on   = [helm_release.grafana, null_resource.wait_for_grafana]
}

resource "grafana_data_source" "global_mimir" {
  name         = "Global-Mimir"
  type         = "prometheus"
  url          = "http://monitoring-mimir-nginx:80/prometheus"
  http_headers = { "X-Scope-OrgID" = "default" }
  depends_on   = [helm_release.grafana, null_resource.wait_for_grafana]
}

# ---- Bootstrap K8s Secrets for the sync script ----------------
# The sync script writes to these Secrets. Terraform creates
# them empty so the Loki gateway and script can start cleanly.
# lifecycle.ignore_changes = [data] ensures Terraform never
# overwrites what the script has written.

resource "kubernetes_secret" "loki_tenant_htpasswd" {
  metadata {
    name      = "loki-tenant-htpasswd"
    namespace = var.namespace
    labels = {
      "managed-by" = "grafana-team-sync"
    }
  }

  # Empty on bootstrap; populated dynamically by the sync script
  data = {
    ".htpasswd" = ""
  }

  lifecycle {
    # Never overwrite — the sync script owns this secret's content
    ignore_changes = [data]
  }

  depends_on = [kubernetes_namespace.observability]
}

resource "kubernetes_secret" "grafana_tenant_passwords" {
  metadata {
    name      = "grafana-tenant-passwords"
    namespace = var.namespace
    labels = {
      "managed-by" = "grafana-team-sync"
    }
  }

  # Empty on bootstrap; populated dynamically by the sync script
  data = {}

  lifecycle {
    ignore_changes = [data]
  }

  depends_on = [kubernetes_namespace.observability]
}

# ---- OSS Team Sync CronJob -----------------------------------
# Runs every 5 minutes. Discovers all *-team groups in Keycloak,
# provisions Grafana resources (team + 4 datasources + folder +
# folder permissions) for each, and syncs users.

# Read the Python sync script
data "local_file" "grafana_sync_script" {
  filename = "${path.module}/scripts/grafana-team-sync.py"
}

# Template the K8s manifests (ConfigMap + RBAC + CronJob)
locals {
  grafana_sync_job_yaml = templatefile("${path.module}/values/grafana-team-sync-job.yaml", {
    keycloak_url            = var.keycloak_url
    keycloak_realm          = var.keycloak_realm
    keycloak_admin_user     = var.keycloak_admin_user
    keycloak_admin_password = var.keycloak_admin_password
    grafana_admin_password  = var.grafana_admin_password
    script_content          = indent(4, data.local_file.grafana_sync_script.content)
  })
}

# Split the YAML into multiple documents
data "kubectl_file_documents" "grafana_sync_manifests" {
  content = local.grafana_sync_job_yaml
}

# Deploy the ConfigMap, RBAC resources, and CronJob to the cluster
resource "kubectl_manifest" "grafana_sync" {
  for_each  = data.kubectl_file_documents.grafana_sync_manifests.manifests
  yaml_body = each.value

  depends_on = [
    helm_release.grafana,
    kubernetes_secret.loki_tenant_htpasswd,
    kubernetes_secret.grafana_tenant_passwords,
  ]
}
