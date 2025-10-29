provider "google" {
  credentials = file(var.credentials)

  region = var.region
}

provider "google-beta" {
  credentials = file(var.credentials)

  region = var.region
}

provider "helm" {
  kubernetes {
    cluster_ca_certificate = module.gke_auth.cluster_ca_certificate
    host                   = module.gke_auth.host
    token                  = module.gke_auth.token
  }
}

provider "kubernetes" {
  cluster_ca_certificate = module.gke_auth.cluster_ca_certificate
  host                   = module.gke_auth.host
  token                  = module.gke_auth.token
}

provider "random" {
}

provider "tls" {
}
