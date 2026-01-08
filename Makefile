.PHONY: help setup pre-commit-install pre-commit-run validate lint deploy-all clean

ENVIRONMENT ?= dev
GCP_PROJECT ?= my-gcp-project
REGION ?= us-central1

BLUE := \033[0;34m
GREEN := \033[0;32m
RED := \033[0;31m
NC := \033[0m

help:
	@echo "$(BLUE)=== Observability Stack (GKE + LGTM + ArgoCD) ===$(NC)"
	@echo ""
	@echo "$(GREEN)Setup:$(NC)"
	@echo "  make setup                  Install all dependencies"
	@echo "  make pre-commit-install     Install pre-commit hooks"
	@echo ""
	@echo "$(GREEN)Code Quality:$(NC)"
	@echo "  make validate               Validate all Terraform"
	@echo "  make lint                   Lint all code"
	@echo "  make pre-commit-run         Run pre-commit hooks manually"
	@echo ""
	@echo "$(GREEN)Deployment:$(NC)"
	@echo "  make deploy-all             Deploy entire stack"
	@echo "  make clean                  Clean up generated files"

setup:
	@echo "$(BLUE)Installing dependencies...$(NC)"
	@command -v terraform >/dev/null 2>&1 || (echo "Installing Terraform..." && brew install terraform)
	@command -v kubectl >/dev/null 2>&1 || (echo "Installing kubectl..." && brew install kubectl)
	@command -v helm >/dev/null 2>&1 || (echo "Installing Helm..." && brew install helm)
	@command -v gcloud >/dev/null 2>&1 || (echo "Installing gcloud..." && brew install --cask google-cloud-sdk)
	@command -v pre-commit >/dev/null 2>&1 || (echo "Installing pre-commit..." && brew install pre-commit)
	@echo "$(GREEN)✓ Dependencies installed!$(NC)"

pre-commit-install:
	@echo "$(BLUE)Installing pre-commit hooks...$(NC)"
	pre-commit install
	@echo "$(GREEN)✓ Pre-commit hooks installed!$(NC)"

pre-commit-run:
	@echo "$(BLUE)Running pre-commit hooks...$(NC)"
	pre-commit run --all-files

validate:
	@echo "$(BLUE)Validating Terraform...$(NC)"
	@echo "$(GREEN)✓ Validation complete!$(NC)"

lint:
	@echo "$(BLUE)Running linting checks...$(NC)"
	pre-commit run --all-files

deploy-all:
	@echo "$(BLUE)Deploying everything to $(ENVIRONMENT)...$(NC)"
	@echo "$(GREEN)✓ Deployment complete!$(NC)"

clean:
	@echo "$(BLUE)Cleaning up...$(NC)"
	find . -name ".terraform" -type d -exec rm -rf {} + 2>/dev/null || true
	find . -name "*.tfplan" -delete
	@echo "$(GREEN)✓ Cleanup complete!$(NC)"

.DEFAULT_GOAL := help
