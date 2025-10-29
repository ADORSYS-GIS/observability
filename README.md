# GIS Apps Deployment

[![Terraform Deployment](https://github.com/ADORSYS-GIS/moodle-terraform/actions/workflows/checks.yaml/badge.svg)](https://github.com/ADORSYS-GIS/moodle-terraform/actions/workflows/checks.yaml)

## Non-Sensitive informations

```bash
#export TF_VAR_project_id="your_digital_ocean_token" ## Only if we wanna fix on this project
export TF_VAR_org_id="your_digital_ocean_token"
export TF_VAR_folder_id="your_digital_ocean_token"
```

## Sensitive informations

```bash
export TF_VAR_credentials="./dev.json"
export TF_VAR_billing_account="some-secret"
export TF_VAR_repository_username="some-secret"
export TF_VAR_repository_password="some-secret"
export TF_VAR_db_username="some-secret"
export TF_VAR_db_password="some-secret"
```

## Setup

1. **Backend config**: You'll need to have an external backend for better security.
   ```bash
   export BACKEND_BUCKET_STATE="your-backend-bucket"
   export BACKEND_CREDENTIAL_FILE_PATH="./credentials.json"
   ```
   
   Then, run the following command to initialize the backend:
   ```bash
   tf init -var-file=prod.tfvars \
    -backend-config="bucket=$BACKEND_BUCKET_STATE" \
    -backend-config="prefix=terraform/state" \
    -backend-config="credentials=$BACKEND_CREDENTIAL_FILE_PATH" \
    -reconfigure
   ```
   
2. (Optional) First create the project. To do that, run the corresponding TF Module
   ```bash
   tf apply -auto-approve -var-file=prod.tfvars -target=module.project
   ```
   
3. Then create the repository. To do that, run the corresponding TF Module
   ```bash
   tf apply -auto-approve -var-file=prod.tfvars
   ```


## Terraform modules

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.8 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 6.0 |
| <a name="requirement_google-beta"></a> [google-beta](#requirement\_google-beta) | ~> 6.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | ~> 2.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | ~> 2.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | 6.26.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_db"></a> [db](#module\_db) | ./modules/db/ | n/a |
| <a name="module_dns"></a> [dns](#module\_dns) | ./modules/dns/ | n/a |
| <a name="module_helm"></a> [helm](#module\_helm) | ./modules/helm/ | n/a |
| <a name="module_k8s"></a> [k8s](#module\_k8s) | ./modules/k8s/ | n/a |
| <a name="module_project"></a> [project](#module\_project) | ./modules/project | n/a |
| <a name="module_redis"></a> [redis](#module\_redis) | ./modules/redis/ | n/a |
| <a name="module_storage"></a> [storage](#module\_storage) | ./modules/storage/ | n/a |
| <a name="module_vpc"></a> [vpc](#module\_vpc) | ./modules/vpc/ | n/a |

## Resources

| Name | Type |
|------|------|
| [google_client_config.default](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/client_config) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_api_enabled_services"></a> [api\_enabled\_services](#input\_api\_enabled\_services) | The list of apis necessary for the project | `list(string)` | <pre>[<br/>  "compute.googleapis.com",<br/>  "gkehub.googleapis.com",<br/>  "cloudresourcemanager.googleapis.com",<br/>  "serviceusage.googleapis.com",<br/>  "servicenetworking.googleapis.com",<br/>  "cloudkms.googleapis.com",<br/>  "logging.googleapis.com",<br/>  "cloudbilling.googleapis.com",<br/>  "iam.googleapis.com",<br/>  "admin.googleapis.com",<br/>  "storage-api.googleapis.com",<br/>  "monitoring.googleapis.com",<br/>  "securitycenter.googleapis.com",<br/>  "billingbudgets.googleapis.com",<br/>  "vpcaccess.googleapis.com",<br/>  "dns.googleapis.com",<br/>  "containerregistry.googleapis.com",<br/>  "eventarc.googleapis.com",<br/>  "run.googleapis.com",<br/>  "container.googleapis.com",<br/>  "dns.googleapis.com",<br/>  "deploymentmanager.googleapis.com",<br/>  "artifactregistry.googleapis.com",<br/>  "cloudbuild.googleapis.com",<br/>  "file.googleapis.com",<br/>  "certificatemanager.googleapis.com",<br/>  "domains.googleapis.com",<br/>  "redis.googleapis.com"<br/>]</pre> | no |
| <a name="input_billing_account"></a> [billing\_account](#input\_billing\_account) | Billing account id for the project | `string` | n/a | yes |
| <a name="input_credentials"></a> [credentials](#input\_credentials) | File path to the credentials file. Keep in mind that the user or service account associated to this credentials file must have the necessary permissions to create the resources defined in this module. | `string` | n/a | yes |
| <a name="input_db_password"></a> [db\_password](#input\_db\_password) | DB password | `string` | n/a | yes |
| <a name="input_db_username"></a> [db\_username](#input\_db\_username) | DB username | `string` | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | n/a | `string` | n/a | yes |
| <a name="input_folder_id"></a> [folder\_id](#input\_folder\_id) | Folder ID in the folder in which project | `string` | `null` | no |
| <a name="input_gis_application_auth_secret"></a> [gis\_application\_auth\_secret](#input\_gis\_application\_auth\_secret) | GIS Application auth secret | `string` | n/a | yes |
| <a name="input_gis_application_chart_version"></a> [gis\_application\_chart\_version](#input\_gis\_application\_chart\_version) | GIS Application Helm chart version | `string` | n/a | yes |
| <a name="input_gis_application_dns_prefix"></a> [gis\_application\_dns\_prefix](#input\_gis\_application\_dns\_prefix) | GIS Application DNS prefix. Final DNS name will be <prefix>.<root\_domain\_name> | `string` | n/a | yes |
| <a name="input_gis_application_oauth_client_id"></a> [gis\_application\_oauth\_client\_id](#input\_gis\_application\_oauth\_client\_id) | GIS Application OAuth client ID | `string` | n/a | yes |
| <a name="input_gis_application_oauth_client_secret"></a> [gis\_application\_oauth\_client\_secret](#input\_gis\_application\_oauth\_client\_secret) | GIS Application OAuth client secret | `string` | n/a | yes |
| <a name="input_iam_principals"></a> [iam\_principals](#input\_iam\_principals) | List of role (key) names to grant permissions to | `list(string)` | n/a | yes |
| <a name="input_machine_type"></a> [machine\_type](#input\_machine\_type) | Machine type | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | base name of this deployment | `string` | `"learn"` | no |
| <a name="input_openai_key"></a> [openai\_key](#input\_openai\_key) | OpenAI application Secure Key | `string` | n/a | yes |
| <a name="input_openai_url"></a> [openai\_url](#input\_openai\_url) | OpenAI provider url | `string` | n/a | yes |
| <a name="input_org_id"></a> [org\_id](#input\_org\_id) | Google Organization ID | `string` | `null` | no |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The ID of the project where this VPC will be created | `string` | `""` | no |
| <a name="input_region"></a> [region](#input\_region) | The region where to deploy resources | `string` | n/a | yes |
| <a name="input_repository_password"></a> [repository\_password](#input\_repository\_password) | Helm chart Repository Password | `string` | n/a | yes |
| <a name="input_repository_username"></a> [repository\_username](#input\_repository\_username) | Helm chart Repository Username | `string` | n/a | yes |
| <a name="input_root_domain_name"></a> [root\_domain\_name](#input\_root\_domain\_name) | n/a | `string` | `"learn.adorsys.team"` | no |
| <a name="input_sschool_auth_secret"></a> [sschool\_auth\_secret](#input\_sschool\_auth\_secret) | SSchool auth secret | `string` | n/a | yes |
| <a name="input_sschool_chart_version"></a> [sschool\_chart\_version](#input\_sschool\_chart\_version) | SSchool Helm chart version | `string` | n/a | yes |
| <a name="input_sschool_dns_prefix"></a> [sschool\_dns\_prefix](#input\_sschool\_dns\_prefix) | SSchool DNS prefix. Final DNS name will be <prefix>.<root\_domain\_name> | `string` | n/a | yes |
| <a name="input_sschool_oauth_client_id"></a> [sschool\_oauth\_client\_id](#input\_sschool\_oauth\_client\_id) | SSchool OAuth client ID | `string` | n/a | yes |
| <a name="input_sschool_oauth_client_secret"></a> [sschool\_oauth\_client\_secret](#input\_sschool\_oauth\_client\_secret) | SSchool OAuth client secret | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_dns_ns"></a> [dns\_ns](#output\_dns\_ns) | The Zone NS |
<!-- END_TF_DOCS -->