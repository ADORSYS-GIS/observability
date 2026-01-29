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
  type        = string
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

variable "install_nginx_ingress" {
  description = "Whether to install NGINX Ingress Controller"
  type        = bool
  default     = false
}

variable "nginx_ingress_version" {
  description = "Version of ingress-nginx chart"
  type        = string
  default     = "4.14.2"
}

variable "nginx_ingress_release_name" {
  description = "Helm release name for NGINX Ingress"
  type        = string
  default     = "nginx-monitoring"
}

variable "nginx_ingress_namespace" {
  description = "Namespace where NGINX Ingress is installed"
  type        = string
  default     = "ingress-nginx"
}

variable "ingress_class_name" {
  description = "Ingress class to use for all ingress resources (e.g., nginx, traefik, kong). Must match an existing IngressClass in the cluster."
  type        = string
  default     = "nginx"
}

variable "install_cert_manager" {
  description = "Whether to install cert-manager"
  type        = bool
  default     = false
}

variable "cert_manager_version" {
  description = "Version of cert-manager chart"
  type        = string
  default     = "v1.19.2"
}

variable "namespace" {
  description = "Namespace to install ArgoCD into"
  type        = string
  default     = "argocd"
}

variable "letsencrypt_email" {
  description = "Email address for Let's Encrypt certificate notifications"
  type        = string
}

variable "cert_issuer_name" {
  description = "Name of the ClusterIssuer or Issuer to create"
  type        = string
  default     = "letsencrypt-prod"
}

variable "cert_issuer_kind" {
  description = "Kind of Issuer to create (ClusterIssuer or Issuer)"
  type        = string
  default     = "ClusterIssuer"
  validation {
    condition     = contains(["ClusterIssuer", "Issuer"], var.cert_issuer_kind)
    error_message = "The cert_issuer_kind must be either 'ClusterIssuer' or 'Issuer'."
  }
}

variable "cert_manager_release_name" {
  description = "Helm release name for Cert-Manager"
  type        = string
  default     = "cert-manager"
}

variable "cert_manager_namespace" {
  description = "Namespace where Cert-Manager is installed"
  type        = string
  default     = "cert-manager"
}

variable "argocd_version" {
  description = "Version of ArgoCD Helm chart"
  type        = string
  default     = "7.7.12"
}
