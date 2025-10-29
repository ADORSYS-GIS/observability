module "project_services" {
  count = var.create_project ? 0 : 1

  source  = "terraform-google-modules/project-factory/google//modules/project_services"
  version = "~> 18.1"

  project_id    = local.project_id
  activate_apis = var.api_enabled_services
}

module "project" {
  source = "./modules/project"
  count  = var.create_project ? 1 : 0

  project_id           = var.project_id
  region               = var.region
  name                 = local.name
  billing_account      = var.billing_account
  org_id               = var.org_id
  api_enabled_services = var.api_enabled_services
  credentials          = var.credentials
  labels               = local.labels
  folder_id            = var.folder_id
}

module "ip" {
  for_each = local.wazuh_domains

  source = "./modules/ip/"

  name       = "${each.key}-${local.name}"
  region     = var.region
  project_id = local.project_id
  regional   = each.value.regional

  depends_on = [module.project, module.vpc, module.project_services]
}

module "dns" {
  source = "./modules/dns/"

  project_id        = local.project_id
  name              = local.name
  network_self_link = module.vpc.network_self_link
  root_domain_name  = var.root_domain_name
  labels            = local.labels

  records = {
    "siem" = {
      type = "A"
      ttl  = 300
      records = [
        module.ip["dashboard"].address,
      ]
    }
    "siem-events" = {
      type = "A"
      ttl  = 300
      records = [
        module.ip["manager"].address,
      ]
    }
  }

  depends_on = [module.project, module.project_services]
}

module "k8s" {
  source = "./modules/k8s/"

  project_id       = local.project_id
  name             = local.name
  region           = var.region
  network_name     = module.vpc.network_name
  sub_network_name = module.vpc.priv_sub_network_name

  ip_range_pod      = module.vpc.ip_range_pod
  ip_range_services = module.vpc.ip_range_services

  depends_on = [module.project, module.vpc, module.project_services]
}

module "vpc" {
  source = "./modules/vpc/"

  project_id = local.project_id
  name       = local.name
  region     = var.region

  depends_on = [module.project, module.project_services]
}

module "storage" {
  source = "./modules/storage/"

  project_id = local.project_id
  labels     = local.labels
  name       = local.name
  names = [
    "loki",
    "tempo",
  ]

  depends_on = [module.project, module.project_services]
}

module "gke_auth" {
  source  = "terraform-google-modules/kubernetes-engine/google//modules/auth"
  version = "~> 38.0"

  project_id           = local.project_id
  cluster_name         = module.k8s.cluster_name
  location             = module.k8s.cluster_location
  use_private_endpoint = false

  depends_on = [module.k8s.cluster_id]
}

module "monitoring" {
  source = "./modules/monitoring/"

  loki_bucket        = module.storage.buckets_map["loki"].name
  loki_s3_access_key = module.storage.access_ids["loki"]
  loki_s3_secret_key = module.storage.secrets["loki"]

  tempo_bucket        = module.storage.buckets_map["tempo"].name
  tempo_s3_access_key = module.storage.access_ids["tempo"]
  tempo_s3_secret_key = module.storage.secrets["tempo"]

  depends_on = [module.k8s, module.storage, module.dns]
}

module "wazuh" {
  source = "./modules/wazuh/"

  helm_chart_user    = var.wazuh_helm_chart_user
  helm_chart_pass    = var.wazuh_helm_chart_pass
  helm_chart_version = var.wazuh_helm_chart_version

  subject = var.subject

  ip_addresses = {
    for k, v in local.wazuh_domains :
    k => {
      domain  = v.domain
      ip_name = module.ip[k].address_name
      ip      = module.ip[k].address
    }
  }

  depends_on = [module.k8s, module.dns]
}
