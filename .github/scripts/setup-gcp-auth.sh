#!/bin/bash

# ========================================================================================
# GCP Auth & Infrastructure Setup Script
# ========================================================================================
# This script automates the setup of Google Cloud resources required for the ArgoCD Agent
# CI/CD pipeline. It handles:
# 1. Bucket Creation (for Terraform backend)
# 2. Service Account Creation
# 3. Workload Identity Federation (WIF) Setup (Security Best Practice)
# 4. IAM Permission Assignment
#
# Usage: ./setup-gcp-auth.sh
# Check requirements: gcloud installed and authenticated (gcloud auth login)
# ========================================================================================

set -e

# --- Configuration (Change these if needed, or pass as env vars) ---
GITHUB_REPO="${GITHUB_REPO:-owner/repo}" # Format: owner/repo
PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project)}"
REGION="${REGION:-us-central1}"
SERVICE_ACCOUNT_NAME="${SERVICE_ACCOUNT_NAME:-github-actions-argocd}"
WIF_POOL_NAME="${WIF_POOL_NAME:-github-pool}"
WIF_PROVIDER_NAME="${WIF_PROVIDER_NAME:-github-provider}"
BUCKET_NAME="${BUCKET_NAME:-${PROJECT_ID}-terraform-state-argocd}"

# --- Colors ---
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=== GCP Setup for ArgoCD Agent Pipeline ===${NC}"
echo "Project ID: $PROJECT_ID"
echo "GitHub Repo: $GITHUB_REPO (Ensure this is correct!)"
echo "Region: $REGION"
echo "Bucket Name: $BUCKET_NAME"
echo "Service Account: $SERVICE_ACCOUNT_NAME"
echo ""

read -p "Are these values correct? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${RED}Aborted. Please export variables (GITHUB_REPO, etc.) and run again.${NC}"
    exit 1
fi

# 1. Create Terraform State Bucket
echo -e "\n${BLUE}--- 1. Checking/Creating Terraform State Bucket ---${NC}"
if ! gsutil ls -b "gs://${BUCKET_NAME}" &>/dev/null; then
    echo "Creating bucket: gs://${BUCKET_NAME}..."
    gsutil mb -p "$PROJECT_ID" -l "$REGION" "gs://${BUCKET_NAME}"
    gsutil versioning set on "gs://${BUCKET_NAME}"
    echo -e "${GREEN}✅ Bucket created and versioning enabled.${NC}"
else
    echo -e "${GREEN}✅ Bucket gs://${BUCKET_NAME} already exists.${NC}"
fi

# 2. Enable Required APIs
echo -e "\n${BLUE}--- 2. Enabling Required APIs ---${NC}"
gcloud services enable \
    iam.googleapis.com \
    iamcredentials.googleapis.com \
    container.googleapis.com \
    storage-api.googleapis.com \
    --project "$PROJECT_ID"

# 3. Create Service Account
echo -e "\n${BLUE}--- 3. Creating Service Account ---${NC}"
SA_EMAIL="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
if ! gcloud iam service-accounts describe "$SA_EMAIL" --project "$PROJECT_ID" &>/dev/null; then
    gcloud iam service-accounts create "$SERVICE_ACCOUNT_NAME" \
        --display-name "GitHub Actions for ArgoCD Agent" \
        --project "$PROJECT_ID"
    echo -e "${GREEN}✅ Service Account created: $SA_EMAIL${NC}"
else
    echo -e "${GREEN}✅ Service Account already exists: $SA_EMAIL${NC}"
fi

# 4. Grant Permissions
echo -e "\n${BLUE}--- 4. Granting IAM Permissions ---${NC}"
# Container Admin (for GKE interaction)
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/container.admin" \
    --condition=None --quiet >/dev/null

# Storage Admin (for Terraform backend access)
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/storage.admin" \
    --condition=None --quiet >/dev/null

echo -e "${GREEN}✅ Permissions granted (roles/container.admin, roles/storage.admin).${NC}"

# 5. Workload Identity Federation (The "Workload IDP" part)
echo -e "\n${BLUE}--- 5. Configuring Workload Identity Federation ---${NC}"

# Create Pool
if ! gcloud iam workload-identity-pools describe "$WIF_POOL_NAME" --project "$PROJECT_ID" --location="global" &>/dev/null; then
    echo "Creating Workload Identity Pool: $WIF_POOL_NAME..."
    gcloud iam workload-identity-pools create "$WIF_POOL_NAME" \
        --project="$PROJECT_ID" \
        --location="global" \
        --display-name="GitHub Actions Pool"
else
    echo "Pool $WIF_POOL_NAME already exists."
fi

# Create Provider
if ! gcloud iam workload-identity-pools providers describe "$WIF_PROVIDER_NAME" --project "$PROJECT_ID" --location="global" --workload-identity-pool="$WIF_POOL_NAME" &>/dev/null; then
    echo "Creating Workload Identity Provider: $WIF_PROVIDER_NAME..."
    gcloud iam workload-identity-pools providers create-oidc "$WIF_PROVIDER_NAME" \
        --project="$PROJECT_ID" \
        --location="global" \
        --workload-identity-pool="$WIF_POOL_NAME" \
        --display-name="GitHub Actions Provider" \
        --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository" \
        --issuer-uri="https://token.actions.githubusercontent.com"
else
    echo "Provider $WIF_PROVIDER_NAME already exists."
fi

# Get the full Provider ID
WORKLOAD_IDENTITY_POOL_ID=$(gcloud iam workload-identity-pools describe "$WIF_POOL_NAME" --project="$PROJECT_ID" --location="global" --format="value(name)")
PROVIDER_NAME="${WORKLOAD_IDENTITY_POOL_ID}/providers/${WIF_PROVIDER_NAME}"

echo -e "${GREEN}✅ Workload Identity Provider ready: $PROVIDER_NAME${NC}"

# 6. Allow GitHub Repo to impersonate Service Account
echo -e "\n${BLUE}--- 6. Binding GitHub Repo to Service Account ---${NC}"
# Allow the specific repo to impersonate the SA
gcloud iam service-accounts add-iam-policy-binding "$SA_EMAIL" \
    --project="$PROJECT_ID" \
    --role="roles/iam.workloadIdentityUser" \
    --member="principalSet://iam.googleapis.com/${WORKLOAD_IDENTITY_POOL_ID}/attribute.repository/${GITHUB_REPO}" \
    --condition=None --quiet >/dev/null

echo -e "${GREEN}✅ Binding created for repo: $GITHUB_REPO${NC}"

# --- Summary Output ---
echo -e "\n${BLUE}======================================================${NC}"
echo -e "${GREEN}🎉 SETUP COMPLETE!${NC}"
echo -e "${BLUE}======================================================${NC}"
echo "Add the following secrets to your GitHub Repository ($GITHUB_REPO):"
echo ""
echo "GCP_PROJECT_ID               : $PROJECT_ID"
echo "GCP_SERVICE_ACCOUNT          : $SA_EMAIL"
echo "GCP_WORKLOAD_IDENTITY_PROVIDER : $PROVIDER_NAME"
echo "TF_STATE_BUCKET_ARGOCD       : $BUCKET_NAME"
echo "REGION                       : $REGION"
echo ""
echo "--------------------------------------------------------"
echo "Run this locally or copy values manually."
