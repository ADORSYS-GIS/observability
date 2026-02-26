#!/bin/bash
set -euo pipefail

echo "🗑️ Removing Grafana and Keycloak resources from Terraform state..."

# Remove all Grafana provider resources from state
terraform state list | grep -E '^grafana_' | while read -r resource; do
  echo "  Removing: $resource"
  terraform state rm "$resource" || true
done

# Remove all Keycloak provider resources from state
terraform state list | grep -E '^keycloak_' | while read -r resource; do
  echo "  Removing: $resource"
  terraform state rm "$resource" || true
done

echo "✅ Grafana and Keycloak resources removed from state"
echo "📋 Remaining resources:"
terraform state list
