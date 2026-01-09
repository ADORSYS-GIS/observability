# --- Keycloak Settings ---
variable "keycloak_url" {
  description = "The URL of your existing Keycloak (e.g., https://auth.example.com)"
  type        = string
}

variable "keycloak_user" {
  description = "Keycloak Admin Username"
  type        = string
}

variable "keycloak_password" {
  description = "Keycloak Admin Password"
  type        = string
  sensitive   = true
}

variable "target_realm" {
  description = "The Keycloak Realm where ArgoCD will be registered"
  default     = "argocd" # Change if using a specific realm
}

# --- ArgoCD Settings ---
variable "argocd_url" {
  description = "The final URL where you will access ArgoCD (e.g., https://argocd.example.com)"
  type        = string
}

variable "kube_context" {
  description = "The context name in your kubeconfig (run 'kubectl config current-context')"
  type        = string
  default     = "" # If empty, uses current context
}