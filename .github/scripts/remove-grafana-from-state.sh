#!/bin/bash
set -uo pipefail

# Remove Grafana resources from Terraform state AND delete datasources from Grafana
# This ensures a clean slate for Terraform to recreate everything

TENANTS="${TENANTS:-webank}"
GRAFANA_URL="${GRAFANA_URL:-}"
GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-}"

echo "🧹 Removing Grafana resources from Terraform state..."
echo "  Tenants: ${TENANTS}"
echo "  Grafana URL: ${GRAFANA_URL:-NOT SET}"
echo "  Grafana Password: ${GRAFANA_ADMIN_PASSWORD:+SET}"

for TENANT in $(echo "$TENANTS" | tr ',' ' '); do
  echo ""
  echo "Processing tenant: $TENANT"
  
  # Remove team from state
  echo "  🗑️  Removing team from state..."
  terraform state rm "grafana_team.tenants[\"${TENANT}\"]" 2>/dev/null || echo "    ℹ️  Team not in state"
  
  # Remove datasources from state
  for DS_KEY in loki mimir prometheus tempo; do
    echo "  🗑️  Removing ${DS_KEY} datasource from state..."
    terraform state rm "grafana_data_source.${DS_KEY}[\"${TENANT}\"]" 2>/dev/null || echo "    ℹ️  Datasource not in state"
  done
  
  # Remove datasource permissions from state
  for DS_KEY in loki mimir prometheus tempo; do
    echo "  🗑️  Removing ${DS_KEY} datasource permissions from state..."
    terraform state rm "grafana_data_source_permission.${DS_KEY}[\"${TENANT}\"]" 2>/dev/null || echo "    ℹ️  Permission not in state"
  done
  
  # Remove folder from state
  echo "  🗑️  Removing folder from state..."
  terraform state rm "grafana_folder.tenants[\"${TENANT}\"]" 2>/dev/null || echo "    ℹ️  Folder not in state"
  
  # Remove folder permissions from state
  echo "  🗑️  Removing folder permissions from state..."
  terraform state rm "grafana_folder_permission.tenants[\"${TENANT}\"]" 2>/dev/null || echo "    ℹ️  Folder permission not in state"
done

# Now delete the actual datasources from Grafana (since they're no longer protected by state)
if [ -n "$GRAFANA_URL" ] && [ -n "$GRAFANA_ADMIN_PASSWORD" ]; then
  echo ""
  echo "🗑️  Deleting datasources from Grafana..."
  GRAFANA_AUTH="admin:${GRAFANA_ADMIN_PASSWORD}"
  
  # Test connectivity
  if ! curl -sf --user "$GRAFANA_AUTH" "${GRAFANA_URL}/api/health" >/dev/null 2>&1; then
    echo "⚠️  Cannot reach Grafana API - skipping datasource deletion"
  else
    for TENANT in $(echo "$TENANTS" | tr ',' ' '); do
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
          echo "    ✓ Found datasource (uid=$DS_UID) - deleting from Grafana..."
          if curl -sf -X DELETE --user "$GRAFANA_AUTH" "${GRAFANA_URL}/api/datasources/uid/${DS_UID}" >/dev/null 2>&1; then
            echo "    ✅ Deleted datasource $DS_NAME from Grafana"
          else
            echo "    ⚠️  Failed to delete datasource $DS_NAME (will try to recreate anyway)"
          fi
        else
          echo "    ℹ️  Datasource $DS_NAME does not exist in Grafana"
        fi
      done
    done
  fi
else
  echo ""
  echo "ℹ️  Grafana credentials not provided - skipping datasource deletion from Grafana"
fi

echo ""
echo "✅ Cleanup complete. Terraform will now create resources cleanly."
