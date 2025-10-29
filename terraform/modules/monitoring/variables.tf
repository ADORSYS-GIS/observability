####

variable "loki_bucket" {
  type = string
}

variable "loki_s3_access_key" {
  type = string
  sensitive = true
}

variable "loki_s3_secret_key" {
  type = string
  sensitive = true
}

####

variable "tempo_bucket" {
  type = string
}

variable "tempo_s3_access_key" {
  type = string
  sensitive = true
}

variable "tempo_s3_secret_key" {
  type = string
  sensitive = true
}

