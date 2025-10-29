terraform {
  backend "gcs" {
    bucket  = "observabilities-tool-tf-state-gis"
    prefix  = "terraform/state"
  }
}
