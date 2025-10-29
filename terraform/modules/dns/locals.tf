locals {
  # https://build5nines.com/using-terraform-string-replace-function-for-regex-string-replacement/
  zone_name = replace("${var.name}-zone-${var.root_domain_name}", "/[.]/", "-")
}