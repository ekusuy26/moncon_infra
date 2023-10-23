variable "app_name" {}
variable "project" {}
variable "credentials_file" {}
variable "github_pat" {}
variable "github_cloub_build_id" {}
variable "github_frontend_repository_uri" {}
variable "github_backend_repository_uri" {}
variable "service_account" {}
variable "service_account_cloudbuild" {}
variable "db_ver" {}
variable "db_root_pass" {}

variable "region" {
  default = "asia-northeast1"
}

variable "location" {
  default = "asia-northeast1"
}

variable "zone" {
  default = "asia-northeast1-c"
}
