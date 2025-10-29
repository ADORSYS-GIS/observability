# Helm Module

<!-- BEGIN_TF_DOCS -->
## Requirements

No requirements.

## Providers

No providers.

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_gis_application_release"></a> [gis\_application\_release](#module\_gis\_application\_release) | blackbird-cloud/deployment/helm | ~> 1.0 |
| <a name="module_gis_sschool_release"></a> [gis\_sschool\_release](#module\_gis\_sschool\_release) | blackbird-cloud/deployment/helm | ~> 1.0 |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Cluster name | `string` | n/a | yes |
| <a name="input_db_host"></a> [db\_host](#input\_db\_host) | DB host | `string` | n/a | yes |
| <a name="input_db_password"></a> [db\_password](#input\_db\_password) | DB password | `string` | n/a | yes |
| <a name="input_db_username"></a> [db\_username](#input\_db\_username) | DB username | `string` | n/a | yes |
| <a name="input_gis_application_auth_secret"></a> [gis\_application\_auth\_secret](#input\_gis\_application\_auth\_secret) | GIS Application auth secret | `string` | n/a | yes |
| <a name="input_gis_application_bucket"></a> [gis\_application\_bucket](#input\_gis\_application\_bucket) | GIS Application bucket name | `string` | n/a | yes |
| <a name="input_gis_application_chart_version"></a> [gis\_application\_chart\_version](#input\_gis\_application\_chart\_version) | GIS Application Helm chart version | `string` | n/a | yes |
| <a name="input_gis_application_dns"></a> [gis\_application\_dns](#input\_gis\_application\_dns) | GIS Application DNS | `string` | n/a | yes |
| <a name="input_gis_application_oauth_client_id"></a> [gis\_application\_oauth\_client\_id](#input\_gis\_application\_oauth\_client\_id) | GIS Application OAuth client ID | `string` | n/a | yes |
| <a name="input_gis_application_oauth_client_secret"></a> [gis\_application\_oauth\_client\_secret](#input\_gis\_application\_oauth\_client\_secret) | GIS Application OAuth client secret | `string` | n/a | yes |
| <a name="input_gis_application_s3_access_key"></a> [gis\_application\_s3\_access\_key](#input\_gis\_application\_s3\_access\_key) | GIS Application S3 access key | `string` | n/a | yes |
| <a name="input_gis_application_s3_secret_key"></a> [gis\_application\_s3\_secret\_key](#input\_gis\_application\_s3\_secret\_key) | GIS Application S3 secret key | `string` | n/a | yes |
| <a name="input_labels"></a> [labels](#input\_labels) | Map of labels for project | `map(string)` | `{}` | no |
| <a name="input_name"></a> [name](#input\_name) | Deployment name | `string` | n/a | yes |
| <a name="input_openai_key"></a> [openai\_key](#input\_openai\_key) | OpenAI provider key | `string` | n/a | yes |
| <a name="input_openai_url"></a> [openai\_url](#input\_openai\_url) | OpenAI provider url | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | Google Project ID | `string` | n/a | yes |
| <a name="input_redis_host"></a> [redis\_host](#input\_redis\_host) | Redis host | `string` | n/a | yes |
| <a name="input_redis_port"></a> [redis\_port](#input\_redis\_port) | Redis port | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | Google Region | `string` | n/a | yes |
| <a name="input_repository_password"></a> [repository\_password](#input\_repository\_password) | Helm repository password | `string` | n/a | yes |
| <a name="input_repository_username"></a> [repository\_username](#input\_repository\_username) | Helm repository username | `string` | n/a | yes |
| <a name="input_sschool_auth_secret"></a> [sschool\_auth\_secret](#input\_sschool\_auth\_secret) | SSchool auth secret | `string` | n/a | yes |
| <a name="input_sschool_bucket"></a> [sschool\_bucket](#input\_sschool\_bucket) | SSchool bucket name | `string` | n/a | yes |
| <a name="input_sschool_chart_version"></a> [sschool\_chart\_version](#input\_sschool\_chart\_version) | SSchool Helm chart version | `string` | n/a | yes |
| <a name="input_sschool_dns"></a> [sschool\_dns](#input\_sschool\_dns) | SSchool DNS | `string` | n/a | yes |
| <a name="input_sschool_oauth_client_id"></a> [sschool\_oauth\_client\_id](#input\_sschool\_oauth\_client\_id) | SSchool OAuth client ID | `string` | n/a | yes |
| <a name="input_sschool_oauth_client_secret"></a> [sschool\_oauth\_client\_secret](#input\_sschool\_oauth\_client\_secret) | SSchool OAuth client secret | `string` | n/a | yes |
| <a name="input_sschool_s3_access_key"></a> [sschool\_s3\_access\_key](#input\_sschool\_s3\_access\_key) | SSchool S3 access key | `string` | n/a | yes |
| <a name="input_sschool_s3_secret_key"></a> [sschool\_s3\_secret\_key](#input\_sschool\_s3\_secret\_key) | SSchool S3 secret key | `string` | n/a | yes |

## Outputs

No outputs.
<!-- END_TF_DOCS -->