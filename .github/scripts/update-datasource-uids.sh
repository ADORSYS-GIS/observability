#!/bin/bash
set -euo pipefail

# Update existing Grafana datasources to use predictable UIDs
# This allows Terraform to manage them without conflicts

GRAFANA_URL="${GRAFANA_URL:-}"
GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-}"
TENANTS="${TENANTS:-webank}"

if [ -z "$GRAFANA_URL" ] || [ -z "$GRAFANA_ADMIN_PASSWORD" ]; then
  echo "❌ Error: GRAFANA_URL and GRAFANA_ADMIN_PASSWORD must be set"
  exit 1
fi

GRAFANA_AUTH="admin:${GRAFANA_ADMIN_PASSWORD}"

echo "🔧 Updating Grafana datasource UIDs to match Terraform configuration..."
echo "  Grafana URL: ${GRAFANA_URL}"
echo "  Tenants: ${TENANTS}"

# Test Grafana connectivity
if ! curl -sf --user "$GRAFANA_AUTH" "${GRAFANA_URL}/api/health" >/dev/null 2>&1; then
  echo "❌ Cannot reach Grafana API at ${GRAFANA_URL}"
  exit 1
fi

for TENANT in $(echo "$TENANTS" | tr ',' ' '); do
  echo ""
  echo "Processing tenant: $TENANT"
  
  TENANT_TITLE=$(echo "$TENANT" | awk '{print toupper(substr($0,1,1)) tolower(substr($0,2))}')
  TENANT_LOWER=$(echo "$TENANT" | tr '[:upper:]' '[:lower:]')
  
  for DS_KEY in loki mimir prometheus tempo; do
    DS_TYPE_UPPER=$(echo "$DS_KEY" | awk '{print toupper(substr($0,1,1)) tolower(substr($0,2))}')
    DS_NAME="${TENANT_TITLE}-${DS_TYPE_UPPER}"
    NEW_UID="${TENANT_LOWER}-${DS_KEY}"
    
    echo "  🔍 Checking datasource: $DS_NAME"
    
    # Get existing datasource
    DS_NAME_ENCODED=$(echo "$DS_NAME" | sed 's/ /%20/g')
    DS_RESPONSE=$(curl -sf --user "$GRAFANA_AUTH" \
      "${GRAFANA_URL}/api/datasources/name/${DS_NAME_ENCODED}" \
      2>/dev/null || true)
    
    if [ -z "$DS_RESPONSE" ]; then
      echo "    ℹ️  Datasource '$DS_NAME' does not exist (will be created by Terraform)"
      continue
    fi
    
    CURRENT_UID=$(echo "$DS_RESPONSE" | jq -r '.uid // empty' 2>/dev/null || true)
    DS_ID=$(echo "$DS_RESPONSE" | jq -r '.id // empty' 2>/dev/null || true)
    
    if [ -z "$CURRENT_UID" ] || [ -z "$DS_ID" ]; then
      echo "    ⚠️  Could not parse datasource response"
      continue
    fi
    
    if [ "$CURRENT_UID" == "$NEW_UID" ]; then
      echo "    ✓ UID already correct: $NEW_UID"
      continue
    fi
    
    echo "    🔄 Updating UID: $CURRENT_UID → $NEW_UID"
    
    # Update the datasource with new UID
    UPDATED_DS=$(echo "$DS_RESPONSE" | jq --arg uid "$NEW_UID" '.uid = $uid')
    
    UPDATE_RESPONSE=$(curl -sf -X PUT \
      --user "$GRAFANA_AUTH" \
      -H "Content-Type: application/json" \
      -d "$UPDATED_DS" \
      "${GRAFANA_URL}/api/datasources/${DS_ID}" \
      2>/dev/null || true)
    
    if echo "$UPDATE_RESPONSE" | jq -e '.datasource.uid' >/dev/null 2>&1; then
      echo "    ✅ Successfully updated UID to: $NEW_UID"
    else
      echo "    ❌ Failed to update UID"
      echo "    Response: $UPDATE_RESPONSE"
    fi
  done
done

echo ""
echo "✅ Datasource UID update complete"
