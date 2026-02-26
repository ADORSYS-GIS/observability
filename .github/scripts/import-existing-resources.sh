#!/bin/bash
set -uo pipefail

# Import existing Kubernetes resources into Terraform state
# This prevents conflicts when deploying to an existing cluster

NAMESPACE="${NAMESPACE:-observability}"
REPORT_FILE="import-report.json"
FAILURE_COUNT=0
FAILED_OPERATIONS=()

echo "🔍 Scanning for existing resources to import..."

# Initialize report
cat > "$REPORT_FILE" <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "imports": [],
  "skipped": [],
  "errors": []
}
EOF

echo "🧹 Cleaning up conflicting cluster-scoped resources..."

# Function to clean up cluster-scoped resources owned by other namespaces
cleanup_conflicting_resources() {
  local resource_type="$1"
  local keywords="$2" # comma-separated keywords
  local deleted_any=false
  
  echo "  🔍 Scanning $resource_type..."
  
  # Get all resources of this type that match any of the keywords
  local pattern=$(echo "$keywords" | sed 's/,/|/g')
  local resources=$(kubectl get "$resource_type" -o name 2>/dev/null | grep -E "$pattern" || true)
  
  for res in $resources; do
    # Get owner using multiple methods
    local ns_owner=""
    ns_owner=$(kubectl get "$res" -o jsonpath='{.metadata.annotations.meta\.helm\.sh/release-namespace}' 2>/dev/null || echo "")
    
    if [ -z "$ns_owner" ]; then
      ns_owner=$(kubectl get "$res" -o json 2>/dev/null | jq -r '.metadata.annotations["meta.helm.sh/release-namespace"] // ""' 2>/dev/null || echo "")
    fi
    
    if [ -n "$ns_owner" ] && [ "$ns_owner" != "$NAMESPACE" ]; then
      echo "    ⚠️  CONFLICT: $res owned by '$ns_owner'. Deleting..."
      if ! kubectl delete "$res" --ignore-not-found --timeout=30s 2>/dev/null; then
        echo "    ❌ Failed to delete $res (continuing anyway)"
        FAILURE_COUNT=$((FAILURE_COUNT+1))
        FAILED_OPERATIONS+=("cleanup: kubectl delete $res")
      fi
      deleted_any=true
    elif [ -z "$ns_owner" ]; then
      # Special case: Resource exists but no Helm owner. 
      # If it matches our exact release names, it's a "zombie" resource from a failed/partial manual install
      if [[ "$res" =~ monitoring-loki|monitoring-mimir|monitoring-tempo|monitoring-grafana|monitoring-prometheus ]]; then
        echo "    ⚠️  ZOMBIE RESOURCE: $res has no owner but matches stack pattern. Deleting to ensure clean install..."
        if ! kubectl delete "$res" --ignore-not-found --timeout=30s 2>/dev/null; then
          echo "    ❌ Failed to delete zombie resource $res (continuing anyway)"
          FAILURE_COUNT=$((FAILURE_COUNT+1))
          FAILED_OPERATIONS+=("cleanup: kubectl delete zombie $res")
        fi
        deleted_any=true
      fi
    fi
  done
  
  [ "$deleted_any" = true ] && sleep 5 || true
}

# Deep Scan for all LGTM related cluster-scoped components
KEYWORDS="loki,mimir,tempo,prometheus,grafana,monitoring"
cleanup_conflicting_resources "clusterrole" "$KEYWORDS"
cleanup_conflicting_resources "clusterrolebinding" "$KEYWORDS"
cleanup_conflicting_resources "validatingwebhookconfigurations" "$KEYWORDS"
cleanup_conflicting_resources "mutatingwebhookconfigurations" "$KEYWORDS"

# Helper function to attempt terraform import
import_resource() {
  local tf_address="$1"
  local resource_id="$2"
  local description="$3"
  
  echo "  📦 Importing: $description"
  
  if terraform import "$tf_address" "$resource_id" 2>&1 | tee /tmp/import.log; then
    echo "    ✅ Import successful"
    # Add to report
    jq --arg addr "$tf_address" --arg id "$resource_id" --arg desc "$description" \
      '.imports += [{"address": $addr, "id": $id, "description": $desc}]' \
      "$REPORT_FILE" > /tmp/report.tmp && mv /tmp/report.tmp "$REPORT_FILE"
    return 0
  else
    if grep -q "Resource already managed" /tmp/import.log; then
      echo "    ℹ️  Already managed by Terraform"
      jq --arg addr "$tf_address" --arg reason "already_managed" \
        '.skipped += [{"address": $addr, "reason": $reason}]' \
        "$REPORT_FILE" > /tmp/report.tmp && mv /tmp/report.tmp "$REPORT_FILE"
    else
      echo "    ⚠️  Import failed (resource may not exist)"
      jq --arg addr "$tf_address" --arg error "$(cat /tmp/import.log | tail -5)" \
        '.errors += [{"address": $addr, "error": $error}]' \
        "$REPORT_FILE" > /tmp/report.tmp && mv /tmp/report.tmp "$REPORT_FILE"
    fi
    return 1
  fi
}

# Check if namespace exists
if kubectl get namespace "$NAMESPACE" &>/dev/null; then
  echo "📂 Found existing namespace: $NAMESPACE"
  import_resource \
    "kubernetes_namespace.observability" \
    "$NAMESPACE" \
    "Namespace: $NAMESPACE"
else
  echo "  ℹ️  Namespace $NAMESPACE does not exist (will be created)"
fi

# Check for cert-manager
if kubectl get namespace cert-manager &>/dev/null; then
  echo "🔐 Found existing cert-manager installation"
  
  # Import cert-manager namespace
  import_resource \
    "module.cert_manager.kubernetes_namespace.cert_manager[0]" \
    "cert-manager" \
    "Cert-Manager namespace"
  
  # Check for ClusterIssuer
  if kubectl get clusterissuer letsencrypt-prod &>/dev/null; then
    echo "  📜 Found ClusterIssuer: letsencrypt-prod"
    # Note: ClusterIssuers are managed by cert-manager, not typically imported
  fi
fi

# Check for ingress-nginx
if kubectl get namespace ingress-nginx &>/dev/null; then
  echo "🌐 Found existing nginx-ingress installation"
  
  import_resource \
    "module.ingress_nginx.kubernetes_namespace.ingress_nginx[0]" \
    "ingress-nginx" \
    "Ingress-NGINX namespace"
fi

# Check for existing service accounts
if kubectl get serviceaccount -n "$NAMESPACE" observability-sa &>/dev/null; then
  echo "👤 Found existing service account: observability-sa"
  import_resource \
    "kubernetes_service_account.observability_sa" \
    "$NAMESPACE/observability-sa" \
    "Kubernetes Service Account"
fi

# GKE Specific Imports (GCP Service Account and Buckets)
if [ "${CLOUD_PROVIDER:-}" == "gke" ]; then
  GCP_PROJECT_ID="${GCP_PROJECT_ID:-}"
  if [ -z "$GCP_PROJECT_ID" ]; then
    echo "⚠️  GCP_PROJECT_ID not set, skipping GCP-level imports"
  else
    SA_NAME="gke-observability-sa"
    SA_EMAIL="${SA_NAME}@${GCP_PROJECT_ID}.iam.gserviceaccount.com"
    
    if gcloud iam service-accounts describe "$SA_EMAIL" --project="$GCP_PROJECT_ID" &>/dev/null; then
      echo "👤 Found existing GCP Service Account: $SA_NAME"
      import_resource \
        "module.cloud_gke[0].google_service_account.observability_sa" \
        "projects/${GCP_PROJECT_ID}/serviceAccounts/${SA_EMAIL}" \
        "GCP Service Account: $SA_NAME"
    fi

    for bucket in loki-chunks loki-ruler mimir-blocks mimir-ruler tempo-traces; do
      BUCKET_NAME="${GCP_PROJECT_ID}-${bucket}-v1"
      if gsutil ls -p "$GCP_PROJECT_ID" "gs://${BUCKET_NAME}" &>/dev/null; then
        echo "🪣  Found existing bucket: $BUCKET_NAME"
        import_resource \
          "module.cloud_gke[0].google_storage_bucket.observability_buckets[\"${bucket}\"]" \
          "$BUCKET_NAME" \
          "GCS Bucket: $BUCKET_NAME"
      fi
    done
  fi
fi

# ── Grafana Imports ─────────────────────────────────────────────────
# IMPORTANT: This section MUST run after terraform.tfvars is created in the
# workflow so the Grafana provider has credentials to authenticate during import.
#
# If a grafana_team or grafana_data_source already exists in Grafana but NOT
# in the Terraform state, `terraform apply` would try to CREATE it → 409 Conflict.
# We prevent this by importing the existing resource IDs into state first.
#
# This section ALWAYS executes regardless of any prior failures in cleanup.
# ─────────────────────────────────────────────────────────────────────

echo "📈 Scanning for existing Grafana resources to import into state..."

if [ -n "${GRAFANA_URL:-}" ] && [ -n "${GRAFANA_ADMIN_PASSWORD:-}" ]; then
  GRAFANA_AUTH="admin:${GRAFANA_ADMIN_PASSWORD}"
  TENANTS="${TENANTS:-webank}"

  for TENANT in $(echo "$TENANTS" | tr ',' ' '); do

    # ── Import team if it exists ──────────────────────────────────────
    TEAM_NAME="${TENANT}-team"
    echo "  🔍 Looking up Grafana team: $TEAM_NAME"

    TEAM_ID=$(curl -sf --user "$GRAFANA_AUTH" \
      "${GRAFANA_URL}/api/teams/search?name=${TEAM_NAME}" \
      2>/dev/null | jq -r ".teams[]? | select(.name == \"${TEAM_NAME}\") | .id" 2>/dev/null || true)

    if [ -n "$TEAM_ID" ] && [ "$TEAM_ID" != "null" ]; then
      echo "    Found team '$TEAM_NAME' (id=$TEAM_ID) — importing into state..."
      if ! import_resource \
        "grafana_team.tenants[\"${TENANT}\"]" \
        "$TEAM_ID" \
        "Grafana Team: $TEAM_NAME"; then
        echo "    ⚠️  Import failed for team $TEAM_NAME (continuing anyway)"
        FAILURE_COUNT=$((FAILURE_COUNT+1))
        FAILED_OPERATIONS+=("grafana: import team $TEAM_NAME")
      fi
    else
      echo "    ℹ️  Team '$TEAM_NAME' does not exist yet (will be created)"
    fi

    # ── Import datasources if they exist ─────────────────────────────
    TENANT_TITLE=$(echo "$TENANT" | awk '{print toupper(substr($0,1,1)) tolower(substr($0,2))}')
    for DS_KEY in loki mimir prometheus tempo; do
      DS_TYPE_UPPER=$(echo "$DS_KEY" | awk '{print toupper(substr($0,1,1)) tolower(substr($0,2))}')
      DS_NAME="${TENANT_TITLE}-${DS_TYPE_UPPER}"

      echo "  🔍 Looking up datasource: $DS_NAME"
      DS_UID=$(curl -sf --user "$GRAFANA_AUTH" \
        "${GRAFANA_URL}/api/datasources/name/${DS_NAME}" \
        2>/dev/null | jq -r '.uid // empty' 2>/dev/null || true)

      if [ -n "$DS_UID" ] && [ "$DS_UID" != "null" ]; then
        echo "    Found datasource '$DS_NAME' (uid=$DS_UID) — importing into state..."
        if ! import_resource \
          "grafana_data_source.${DS_KEY}[\"${TENANT}\"]" \
          "$DS_UID" \
          "Grafana Datasource: $DS_NAME"; then
          echo "    ⚠️  Import failed for datasource $DS_NAME (continuing anyway)"
          FAILURE_COUNT=$((FAILURE_COUNT+1))
          FAILED_OPERATIONS+=("grafana: import datasource $DS_NAME")
        fi
      else
        echo "    ℹ️  Datasource '$DS_NAME' does not exist yet (will be created)"
      fi
    done

  done
else
  echo "⏭️  Skipping Grafana imports: GRAFANA_URL or GRAFANA_ADMIN_PASSWORD not set"
fi

# Summary
echo ""
echo "📊 Import Summary:"
IMPORTED=$(jq '.imports | length' "$REPORT_FILE")
SKIPPED=$(jq '.skipped | length' "$REPORT_FILE")
ERRORS=$(jq '.errors | length' "$REPORT_FILE")

echo "  ✅ Imported: $IMPORTED"
echo "  ⏭️  Skipped: $SKIPPED"
echo "  ❌ Errors: $ERRORS"

# Report any failures that occurred during execution
if [ "$FAILURE_COUNT" -gt 0 ]; then
  echo ""
  echo "⚠️  Failure Summary: $FAILURE_COUNT operation(s) failed but script continued"
  echo "Failed operations:"
  for op in "${FAILED_OPERATIONS[@]}"; do
    echo "  - $op"
  done
  echo ""
  echo "ℹ️  These failures were logged but did not prevent other imports from executing."
  echo "ℹ️  Terraform apply will proceed and create any resources that failed to import."
fi

echo ""
echo "📄 Full report saved to: $REPORT_FILE"
cat "$REPORT_FILE" | jq '.'

# Exit successfully even if some imports failed
# This allows the workflow to continue
exit 0
