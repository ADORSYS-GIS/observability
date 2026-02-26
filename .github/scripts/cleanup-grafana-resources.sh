#!/bin/bash
set -uo pipefail

# Cleanup existing Grafana resources that conflict with Terraform
# This script deletes teams and datasources from Grafana so Terraform can recreate them

GRAFANA_URL="${GRAFANA_URL:-}"
GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-}"
TENANTS="${TENANTS:-webank}"

if [ -z "$GRAFANA_URL" ] || [ -z "$GRAFANA_ADMIN_PASSWORD" ]; then
  echo "❌ GRAFANA_URL and GRAFANA_ADMIN_PASSWORD must be set"
  exit 1
fi

GRAFANA_AUTH="admin:${GRAFANA_ADMIN_PASSWORD}"

echo "🧹 Cleaning up existing Grafana resources..."
echo "  Grafana URL: ${GRAFANA_URL}"
echo "  Tenants: ${TENANTS}"

# Test connectivity
if ! curl -sf --user "$GRAFANA_AUTH" "${GRAFANA_URL}/api/health" >/dev/null 2>&1; then
  echo "❌ Cannot reach Grafana API at ${GRAFANA_URL}"
  exit 1
fi

echo "✓ Grafana API is reachable"

for TENANT in $(echo "$TENANTS" | tr ',' ' '); do
  echo ""
  echo "Processing tenant: $TENANT"
  
  # Delete team
  TEAM_NAME="${TENANT}-team"
  echo "  🔍 Looking for team: $TEAM_NAME"
  TEAM_ID=$(curl -sf --user "$GRAFANA_AUTH" \
    "${GRAFANA_URL}/api/teams/search?name=${TEAM_NAME}" \
    2>/dev/null | jq -r ".teams[]? | select(.name == \"${TEAM_NAME}\") | .id" 2>/dev/null || true)
  
  if [ -n "$TEAM_ID" ] && [ "$TEAM_ID" != "null" ] && [ "$TEAM_ID" != "" ]; then
    echo "    ✓ Found team (id=$TEAM_ID) - deleting..."
    if curl -sf -X DELETE --user "$GRAFANA_AUTH" "${GRAFANA_URL}/api/teams/${TEAM_ID}" >/dev/null 2>&1; then
      echo "    ✓ Deleted team $TEAM_NAME"
    else
      echo "    ⚠️  Failed to delete team $TEAM_NAME"
    fi
  else
    echo "    ℹ️  Team $TEAM_NAME does not exist"
  fi
  
  # Delete datasources
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
      echo "    ✓ Found datasource (uid=$DS_UID) - deleting..."
      if curl -sf -X DELETE --user "$GRAFANA_AUTH" "${GRAFANA_URL}/api/datasources/uid/${DS_UID}" >/dev/null 2>&1; then
        echo "    ✓ Deleted datasource $DS_NAME"
      else
        echo "    ⚠️  Failed to delete datasource $DS_NAME"
      fi
    else
      echo "    ℹ️  Datasource $DS_NAME does not exist"
    fi
  done
done

echo ""
echo "✅ Cleanup complete! Terraform can now create these resources cleanly."
