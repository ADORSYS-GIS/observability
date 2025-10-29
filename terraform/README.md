<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.8 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 6.0 |
| <a name="requirement_google-beta"></a> [google-beta](#requirement\_google-beta) | ~> 6.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | ~> 2.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | ~> 2.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.0 |
| <a name="requirement_tls"></a> [tls](#requirement\_tls) | ~> 4.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | 6.50.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_dns"></a> [dns](#module\_dns) | ./modules/dns/ | n/a |
| <a name="module_gke_auth"></a> [gke\_auth](#module\_gke\_auth) | terraform-google-modules/kubernetes-engine/google//modules/auth | ~> 38.0 |
| <a name="module_ip"></a> [ip](#module\_ip) | ./modules/ip/ | n/a |
| <a name="module_k8s"></a> [k8s](#module\_k8s) | ./modules/k8s/ | n/a |
| <a name="module_monitoring"></a> [monitoring](#module\_monitoring) | ./modules/monitoring/ | n/a |
| <a name="module_project"></a> [project](#module\_project) | ./modules/project | n/a |
| <a name="module_project_services"></a> [project\_services](#module\_project\_services) | terraform-google-modules/project-factory/google//modules/project_services | ~> 18.1 |
| <a name="module_storage"></a> [storage](#module\_storage) | ./modules/storage/ | n/a |
| <a name="module_vpc"></a> [vpc](#module\_vpc) | ./modules/vpc/ | n/a |
| <a name="module_wazuh"></a> [wazuh](#module\_wazuh) | ./modules/wazuh/ | n/a |

## Resources

| Name | Type |
|------|------|
| [google_client_config.default](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/client_config) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_api_enabled_services"></a> [api\_enabled\_services](#input\_api\_enabled\_services) | The list of apis necessary for the project | `list(string)` | <pre>[<br/>  "compute.googleapis.com",<br/>  "gkehub.googleapis.com",<br/>  "cloudresourcemanager.googleapis.com",<br/>  "serviceusage.googleapis.com",<br/>  "servicenetworking.googleapis.com",<br/>  "cloudkms.googleapis.com",<br/>  "logging.googleapis.com",<br/>  "cloudbilling.googleapis.com",<br/>  "iam.googleapis.com",<br/>  "admin.googleapis.com",<br/>  "storage-api.googleapis.com",<br/>  "monitoring.googleapis.com",<br/>  "securitycenter.googleapis.com",<br/>  "billingbudgets.googleapis.com",<br/>  "vpcaccess.googleapis.com",<br/>  "dns.googleapis.com",<br/>  "containerregistry.googleapis.com",<br/>  "eventarc.googleapis.com",<br/>  "run.googleapis.com",<br/>  "container.googleapis.com",<br/>  "dns.googleapis.com",<br/>  "deploymentmanager.googleapis.com",<br/>  "artifactregistry.googleapis.com",<br/>  "cloudbuild.googleapis.com",<br/>  "file.googleapis.com",<br/>  "certificatemanager.googleapis.com",<br/>  "domains.googleapis.com"<br/>]</pre> | no |
| <a name="input_billing_account"></a> [billing\_account](#input\_billing\_account) | Billing account id for the project | `string` | `""` | no |
| <a name="input_create_project"></a> [create\_project](#input\_create\_project) | Should we create a project? | `bool` | `false` | no |
| <a name="input_credentials"></a> [credentials](#input\_credentials) | File path to the credentials file. Keep in mind that the user or service account associated to this credentials file must have the necessary permissions to create the resources defined in this module. | `string` | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | n/a | `string` | n/a | yes |
| <a name="input_folder_id"></a> [folder\_id](#input\_folder\_id) | Folder ID in the folder in which project | `string` | `null` | no |
| <a name="input_name"></a> [name](#input\_name) | base name of this deployment | `string` | `"monitoring"` | no |
| <a name="input_org_id"></a> [org\_id](#input\_org\_id) | Google Organization ID | `string` | `null` | no |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The ID of the project where this VPC will be created | `string` | `""` | no |
| <a name="input_region"></a> [region](#input\_region) | The region where to deploy resources | `string` | n/a | yes |
| <a name="input_root_domain_name"></a> [root\_domain\_name](#input\_root\_domain\_name) | n/a | `string` | `"observability.adorsys.team"` | no |
| <a name="input_subject"></a> [subject](#input\_subject) | n/a | <pre>object({<br/>    country      = string<br/>    locality     = string<br/>    organization = string<br/>    common_name  = string<br/>  })</pre> | n/a | yes |
| <a name="input_wazuh_helm_chart_pass"></a> [wazuh\_helm\_chart\_pass](#input\_wazuh\_helm\_chart\_pass) | n/a | `string` | n/a | yes |
| <a name="input_wazuh_helm_chart_user"></a> [wazuh\_helm\_chart\_user](#input\_wazuh\_helm\_chart\_user) | n/a | `string` | n/a | yes |
| <a name="input_wazuh_helm_chart_version"></a> [wazuh\_helm\_chart\_version](#input\_wazuh\_helm\_chart\_version) | n/a | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_dns_ns"></a> [dns\_ns](#output\_dns\_ns) | The Zone NS |
| <a name="output_k8s_host"></a> [k8s\_host](#output\_k8s\_host) | n/a |
| <a name="output_k8s_name"></a> [k8s\_name](#output\_k8s\_name) | n/a |
| <a name="output_wazuh_domains"></a> [wazuh\_domains](#output\_wazuh\_domains) | n/a |
<!-- END_TF_DOCS -->