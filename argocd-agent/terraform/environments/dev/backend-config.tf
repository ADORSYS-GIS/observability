terraform {
  backend "gcs" {
    bucket = "observe-472521-terraform-state-argocd"
    prefix = "terraform/argocd-agent/dev"
  }
}
