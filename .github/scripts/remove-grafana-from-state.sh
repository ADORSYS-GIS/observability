#!/bin/bash
set -uo pipefail

# Import existing Grafana resources into Terraform state
# This prevents 409 conflicts when resources already exist in Grafana

TENANTS="${TENANTS:-webank}"
GRAFANA_URL="${GRAFANA_URL:-}"
GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-}"

echo "📥 Importing existing Grafana resources into Terraform state..."
echo "  Tenants: ${TENANTS}"
echo "  Grafana URL: ${GRAFANA_URL:-NOT SET}"
echo "  Grafana Password: ${GRAFANA_ADMIN_PASSWORD:+SET}"

# Helper function to attempt terraform import
import_resource() {
  local tf_address="$1"
  local resource_id="$2"
  local description="$3"
  
  echo "  📦 Importing: $description"
  
  if terraform import "$tf_address" "$resource_id" 2>&1 | tee /tmp/import.log; then
    echo "    ✅ Import successful"
    return 0
  else
    if grep -q "Resource already managed" /tmp/import.log; then
      echo "    ℹ️  Already managed by Terraform"
    else
      echo "    ⚠️  Import failed (resource may not exist or import not supported)"
    fi
    return 1
  fi
}

if [ -n "$GRAFANA_URL" ] && [ -n "$GRAFANA_ADMIN_PASSWORD" ]; then
  GRAFANA_AUTH="admin:${GRAFANA_ADMIN_PASSWORD}"
  
  # Test connectivity
  if ! curl -sf --user "$GRAFANA_AUTH" "${GRAFANA_URL}/api/health" >/dev/null 2>&1; then
    echo "⚠️  Cannot reach Grafana API at ${GRAFANA_URL} - skipping imports"
    exit 0
  fi
  
  for TENANT in $(echo "$TENANTS" | tr ',' ' '); do
    echo ""
    echo "Processing tenant: $TENANT"
    
    # Import team if it exists
    TEAM_NAME="${TENANT}-team"
    echo "  🔍 Looking up Grafana team: $TEAM_NAME"
    
    TEAM_ID=$(curl -sf --user "$GRAFANA_AUTH" \
      "${GRAFANA_URL}/api/teams/search?name=${TEAM_NAME}" \
      2>/dev/null | jq -r ".teams[]? | select(.name == \"${TEAM_NAME}\") | .id" 2>/dev/null || true)
    
    if [ -n "$TEAM_ID" ] && [ "$TEAM_ID" != "null" ] && [ "$TEAM_ID" != "" ]; then
      import_resource \
        "grafana_team.tenants[\"${TENANT}\"]" \
        "$TEAM_ID" \
        "Grafana Team: $TEAM_NAME"
    else
      echo "    ℹ️  Team '$TEAM_NAME' does not exist yet (will be created)"
    fi
    
    # Import datasources if they exist
    TENANT_TITLE=$(echo "$TENANT" | awk '{print toupper(substr($0,1,1)) tolower(substr($0,2))}')
    for DS_KEY in loki mimir prometheus tempo; do
      DS_TYPE_UPPER=$(echo "$DS_KEY" | awk '{print toupper(substr($0,1,1)) tolower(substr($0,2))}')
      DS_NAME="${TENANT_TITLE}-${DS_TYPE_UPPER}"
      
      echo "  🔍 Looking for datasource: $DS_NAME"
      DS_NAME_ENCODED=$(echo "$DS_NAME" | sed 's/ /%20/g')
      DS_UID=$(curl -sf --user "$GRAFANA_AUTH" \
        "${GRAFANA_URL}/api/datasources/name/${DS_NAME_ENCODED}" \
        2>/dev/null | jq -r '.uid // empty' 2>/dev/null || true)
      
      if [ -n "$DS_UID" ] && [ "$DS_UID" != "null" ] && [ "$DS_UID" != "" ]; then
        import_resource \
          "grafana_data_source.${DS_KEY}[\"${TENANT}\"]" \
          "$DS_UID" \
          "Grafana Datasource: $DS_NAME"
      else
        echo "    ℹ️  Datasource '$DS_NAME' does not exist yet (will be created)"
      fi
    done
    
    # Import folder if it exists
    FOLDER_TITLE="${TENANT_TITLE} Dashboards"
    echo "  🔍 Looking for folder: $FOLDER_TITLE"
    
    FOLDER_UID=$(curl -sf --user "$GRAFANA_AUTH" \
      "${GRAFANA_URL}/api/folders" \
      2>/dev/null | jq -r ".[] | select(.title == \"${FOLDER_TITLE}\") | .uid" 2>/dev/null || true)
    
    if [ -n "$FOLDER_UID" ] && [ "$FOLDER_UID" != "null" ] && [ "$FOLDER_UID" != "" ]; then
      import_resource \
        "grafana_folder.tenants[\"${TENANT}\"]" \
        "$FOLDER_UID" \
        "Grafana Folder: $FOLDER_TITLE"
    else
      echo "    ℹ️  Folder '$FOLDER_TITLE' does not exist yet (will be created)"
    fi
  done
else
  echo ""
  echo "ℹ️  Grafana credentials not provided - skipping imports"
fi

echo ""
echo "✅ Import complete. Terraform will now manage existing resources without conflicts."
