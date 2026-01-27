terraform {
  backend "gcs" {
    bucket = "observe-472521-terraform-state"
    prefix = "terraform/lgtm-stack"
  }
}
