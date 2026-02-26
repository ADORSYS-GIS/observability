# Bugfix Requirements Document

## Introduction

The GitHub Actions workflow for deploying the LGTM stack fails during the terraform apply step due to 409 conflict errors when attempting to create Grafana resources (teams, datasources) that already exist. The root cause is that the import script `.github/scripts/import-existing-resources.sh` exits prematurely when the clusterrole cleanup command fails, preventing the Grafana resource import section from executing. This leaves existing Grafana resources unimported in the Terraform state, causing terraform apply to attempt creating them again, resulting in conflicts.

## Bug Analysis

### Current Behavior (Defect)

1.1 WHEN the import script encounters a failed kubectl command during clusterrole cleanup THEN the system exits immediately with code 1 due to `set -euo pipefail`

1.2 WHEN the import script exits early during cleanup THEN the system never reaches the Grafana resource import section

1.3 WHEN Grafana resources exist in the live system but not in Terraform state THEN the system attempts to CREATE them during terraform apply

1.4 WHEN terraform apply attempts to create existing Grafana teams THEN the system returns error "Team name taken" with 409 status code

1.5 WHEN terraform apply attempts to create existing Grafana datasources THEN the system returns error "data source with the same name already exists" with 409 status code

1.6 WHEN the workflow uses `continue-on-error: true` on the import step THEN the system proceeds to terraform apply with incomplete state imports

### Expected Behavior (Correct)

2.1 WHEN the import script encounters a failed kubectl command during cleanup THEN the system SHALL log the error and continue executing subsequent import operations

2.2 WHEN individual resource cleanup commands fail THEN the system SHALL continue to the Grafana resource import section

2.3 WHEN Grafana teams exist in the live system THEN the system SHALL import them into Terraform state before apply

2.4 WHEN Grafana datasources exist in the live system THEN the system SHALL import them into Terraform state before apply

2.5 WHEN terraform apply runs after successful imports THEN the system SHALL recognize existing resources in state and not attempt to recreate them

2.6 WHEN all import operations complete (with or without individual failures) THEN the system SHALL exit with code 0 to allow the workflow to proceed

### Unchanged Behavior (Regression Prevention)

3.1 WHEN resources are successfully imported into Terraform state THEN the system SHALL CONTINUE TO report them in the import summary

3.2 WHEN resources do not exist in the live system THEN the system SHALL CONTINUE TO skip import and allow terraform apply to create them

3.3 WHEN the import report is generated THEN the system SHALL CONTINUE TO include counts of imported, skipped, and errored resources

3.4 WHEN GCP-specific resources need importing THEN the system SHALL CONTINUE TO import service accounts and storage buckets

3.5 WHEN Kubernetes namespace and service account resources exist THEN the system SHALL CONTINUE TO import them correctly

3.6 WHEN the script completes THEN the system SHALL CONTINUE TO generate the JSON import report file
