#!/bin/bash
set -uo pipefail

# Remove Grafana resources from Terraform state to allow clean recreation
# This fixes state drift issues where Terraform state doesn't match actual Grafana resources

TENANTS="${TENANTS:-webank}"

echo "🧹 Removing Grafana resources from Terraform state..."
echo "  Tenants: ${TENANTS}"

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

echo ""
echo "✅ Grafana resources removed from state. Terraform will now import or create them."
