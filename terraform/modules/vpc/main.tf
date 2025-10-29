module "vpc" {
  source  = "terraform-google-modules/network/google"
  version = "~> 12.0"

  project_id   = var.project_id
  network_name = local.name
  routing_mode = "GLOBAL"

  subnets = [
    {
      subnet_name   = local.pub_sub_network_name
      subnet_ip     = "10.10.0.0/18"
      subnet_region = var.region
      auto_upgrade  = true
      auto_repair   = true
    },
    {
      subnet_name           = local.priv_sub_network_name
      subnet_ip             = "10.10.64.0/18"
      subnet_region         = var.region
      subnet_private_access = true
      auto_upgrade          = true
      auto_repair           = true
    },
  ]

  secondary_ranges = {
    (local.pub_sub_network_name) = [
      {
        range_name    = "ip-range-pods"
        ip_cidr_range = "10.11.0.0/18"
      },
      {
        range_name    = "ip-range-services"
        ip_cidr_range = "10.11.64.0/18"
      },
    ],
    (local.priv_sub_network_name) = [
      {
        range_name    = local.ip_range_name_pod
        ip_cidr_range = "10.23.0.0/18"
      },
      {
        range_name    = local.ip_range_name_services
        ip_cidr_range = "10.23.64.0/18"
      },
    ]
  }

  auto_create_subnetworks = false
}

module "cloud_router" {
  source  = "terraform-google-modules/cloud-router/google"
  version = "~> 7.0"

  name    = local.router_name
  project = var.project_id
  network = module.vpc.network_name
  region  = var.region

  nats = [{
    name                               = local.nat_name
    source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
  }]
}
