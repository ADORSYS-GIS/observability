region           = "europe-west3"
name             = "observe"
root_domain_name = "observe.camer.digital"
environment      = "prod"

project_id = "observe-472521"

wazuh_helm_chart_version = "0.6.0-rc.18"

subject = {
  country = "CM"
  locality = "Douala"
  organization = "BVMAC"
  common_name = "root-ca"
}
