# TFLint Configuration for ArgoCD Agent Infrastructure
# https://github.com/terraform-linters/tflint

config {
  # Enable all rules by default
  call_module_type = "all"
  force            = false
}

# Terraform plugin for core validation rules
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# Enforce naming conventions
rule "terraform_naming_convention" {
  enabled = true
  format  = "snake_case"
}

# Require version constraints on providers
rule "terraform_required_providers" {
  enabled = true
}

# Require Terraform version constraint
rule "terraform_required_version" {
  enabled = true
}

# Ensure resources have descriptions
rule "terraform_documented_outputs" {
  enabled = true
}

rule "terraform_documented_variables" {
  enabled = true
}

# Enforce consistent resource naming
rule "terraform_standard_module_structure" {
  enabled = true
}

# Check for deprecated syntax
rule "terraform_deprecated_index" {
  enabled = true
}

rule "terraform_deprecated_interpolation" {
  enabled = true
}

# Type checking
rule "terraform_typed_variables" {
  enabled = true
}

# Unused declarations - disabled for legacy variables
rule "terraform_unused_declarations" {
  enabled = false
}

# Comment requirements
rule "terraform_comment_syntax" {
  enabled = true
}
