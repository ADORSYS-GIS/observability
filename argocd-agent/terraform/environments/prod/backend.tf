# =============================================================================
# TERRAFORM BACKEND CONFIGURATION
# =============================================================================
# This file configures where Terraform stores its state.
#
# IMPORTANT: State files contain sensitive information. Choose your backend carefully!
#
# WORKSPACE STRATEGY (M5):
# ------------------------
# This infrastructure supports Terraform workspaces for managing multiple
# environments (dev, staging, prod) using the same codebase.
#
# Backend Options:
# ================
#
# 1. LOCAL BACKEND (Development/Testing)
# ---------------------------------------
# terraform {
#   backend "local" {
#     path = "terraform.tfstate"
#   }
# }
#
# Pros: Simple, no setup required
# Cons: Not suitable for team collaboration, no locking, state stored locally
# Use case: Development and testing
#
#
# 2. S3 BACKEND (Recommended for Production)
# -------------------------------------------
# terraform {
#   backend "s3" {
#     bucket         = "my-terraform-state-bucket"
#     key            = "argocd-agent/prod/terraform.tfstate"
#     region         = "us-east-1"
#     encrypt        = true
#     dynamodb_table = "terraform-state-lock"
#     
#     # Workspace support
#     workspace_key_prefix = "workspaces"
#   }
# }
#
# Setup requirements:
# - Create S3 bucket with versioning enabled
# - Create DynamoDB table for state locking (primary key: LockID, type: String)
# - Configure appropriate IAM permissions
#
# Pros: Team collaboration, state locking, versioning, encryption
# Cons: Requires AWS infrastructure
# Use case: Production environments, team workflows
#
#
# 3. TERRAFORM CLOUD (SaaS Option)
# ---------------------------------
# terraform {
#   cloud {
#     organization = "my-org"
#     workspaces {
#       name = "argocd-agent-prod"
#     }
#   }
# }
#
# Pros: Managed backend, built-in UI, RBAC, cost estimation
# Cons: External dependency, pricing for teams
# Use case: Teams preferring managed infrastructure
#
#
# WORKSPACE USAGE:
# ================
# 
# Create and use workspaces:
#   terraform workspace new staging
#   terraform workspace select prod
#   terraform workspace list
#
# Access current workspace in code:
#   terraform.workspace
#
# Example workspace-aware configuration:
#   locals {
#     environment = terraform.workspace
#     ha_enabled  = terraform.workspace == "prod" ? true : false
#   }
#
#
# MIGRATION FROM LOCAL TO REMOTE:
# ================================
# 
# 1. Apply with local backend first
# 2. Add remote backend configuration
# 3. Run: terraform init -migrate-state
# 4. Verify: terraform state list
# 5. Delete local state files after verification
#
#
# CURRENT CONFIGURATION:
# ======================
# By default, this uses local backend. Uncomment and configure
# one of the options above for production use.
# =============================================================================

# Default local backend (uncomment for explicit configuration)
# terraform {
#   backend "local" {
#     path = "terraform.tfstate"
#   }
# }

# Production S3 backend (uncomment and configure for production)
# terraform {
#   backend "s3" {
#     bucket         = "CHANGEME-terraform-state"
#     key            = "argocd-agent/prod/terraform.tfstate"
#     region         = "us-east-1"
#     encrypt        = true
#     dynamodb_table = "terraform-state-lock"
#     workspace_key_prefix = "workspaces"
#   }
# }
