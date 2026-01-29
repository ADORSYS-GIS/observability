#!/bin/bash
set -e

#===================================================================
# GCP LoadBalancer Cleanup Script
#===================================================================
# This script cleans up orphaned GCP load balancer resources that
# may be left behind after 'terraform destroy'.
#
# Run this AFTER 'terraform destroy' if you encounter LoadBalancer
# provisioning issues on the next deployment.
#===================================================================

PROJECT_ID="${PROJECT_ID:-observe-472521}"
REGION="${REGION:-europe-west3}"

echo "=========================================="
echo "GCP LoadBalancer Cleanup Script"
echo "=========================================="
echo ""
echo "Project: $PROJECT_ID"
echo "Region: $REGION"
echo ""

# List orphaned forwarding rules (LoadBalancers without associated services)
echo "[1/3] Checking for orphaned forwarding rules..."
FORWARDING_RULES=$(gcloud compute forwarding-rules list \
  --project="$PROJECT_ID" \
  --regions="$REGION" \
  --format="value(name)" \
  --filter="name~'^a[a-f0-9]{31}$'" 2>/dev/null || true)

if [ -z "$FORWARDING_RULES" ]; then
  echo "✓ No orphaned forwarding rules found"
else
  echo "Found orphaned forwarding rules:"
  echo "$FORWARDING_RULES"
  echo ""
  read -p "Delete these forwarding rules? (y/N): " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    for RULE in $FORWARDING_RULES; do
      echo "Deleting forwarding rule: $RULE..."
      gcloud compute forwarding-rules delete "$RULE" \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        --quiet || true
    done
    echo "✓ Forwarding rules deleted"
  fi
fi

# List orphaned target pools
echo ""
echo "[2/3] Checking for orphaned target pools..."
TARGET_POOLS=$(gcloud compute target-pools list \
  --project="$PROJECT_ID" \
  --regions="$REGION" \
  --format="value(name)" \
  --filter="name~'^a[a-f0-9]{31}$'" 2>/dev/null || true)

if [ -z "$TARGET_POOLS" ]; then
  echo "✓ No orphaned target pools found"
else
  echo "Found orphaned target pools:"
  echo "$TARGET_POOLS"
  echo ""
  read -p "Delete these target pools? (y/N): " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    for POOL in $TARGET_POOLS; do
      echo "Deleting target pool: $POOL..."
      gcloud compute target-pools delete "$POOL" \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        --quiet || true
    done
    echo "✓ Target pools deleted"
  fi
fi

# List in-use external IPs that might be orphaned
echo ""
echo "[3/3] Checking for orphaned external IPs..."
ORPHANED_IPS=$(gcloud compute addresses list \
  --project="$PROJECT_ID" \
  --filter="region:($REGION) AND status:IN_USE AND NOT users:*" \
  --format="value(name)" 2>/dev/null || true)

if [ -z "$ORPHANED_IPS" ]; then
  echo "✓ No orphaned external IPs found"
else
  echo "⚠ Found potentially orphaned external IPs (IN_USE but no users):"
  gcloud compute addresses list \
    --project="$PROJECT_ID" \
    --filter="region:($REGION) AND status:IN_USE AND NOT users:*" \
    --format="table(name,address,status,region)"
  echo ""
  echo "Note: These IPs are IN_USE but have no associated resources."
  echo "They may be safe to delete, but verify manually before proceeding."
fi

echo ""
echo "=========================================="
echo "✓ Cleanup completed"
echo "=========================================="
echo ""
echo "If you still encounter LoadBalancer issues, try:"
echo "1. Delete and recreate the stuck LoadBalancer service:"
echo "   kubectl delete svc <service-name> -n <namespace>"
echo "   kubectl rollout restart deployment/<deployment-name> -n <namespace>"
echo ""
echo "2. Check GCP Console > Network Services > Load Balancing"
echo "   for any stuck load balancer resources"
