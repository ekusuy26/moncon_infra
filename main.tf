terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "5.1.0" //オプション。設定しないと常に最新版のプロバイダーを使用する
    }
  }
}

provider "google" { //上記の指定したプロバイダーを構成する
  credentials = file(var.credentials_file)

  project = var.project
  region  = var.region
  zone    = var.zone
}

// Create a secret containing the personal access token and grant permissions to the Service Agent
# シークレットマネージャーを設定
resource "google_secret_manager_secret" "github_token_secret" {
  project   = var.project
  secret_id = "github_pat"

  replication {
    auto {}
  }
}

# 設定したシークレットマネージャーにgithub tokenを設定
resource "google_secret_manager_secret_version" "github_token_secret_version" {
  secret      = google_secret_manager_secret.github_token_secret.id
  secret_data = var.github_pat
}

data "google_iam_policy" "serviceagent_secretAccessor" {
  binding {
    role = "roles/secretmanager.secretAccessor"
    members = [
      "serviceAccount:${var.service_account}",
      "serviceAccount:${var.service_account_cloudbuild}"
    ]
  }
}

# 設定したシークレットマネージャーにアクセス権を設定
resource "google_secret_manager_secret_iam_policy" "policy" {
  project     = google_secret_manager_secret.github_token_secret.project
  secret_id   = google_secret_manager_secret.github_token_secret.secret_id
  policy_data = data.google_iam_policy.serviceagent_secretAccessor.policy_data
}

// Create the GitHub connection
# hostとの接続
resource "google_cloudbuildv2_connection" "my_connection" {
  project  = var.project
  location = "us-central1"
  name     = "${var.app_name}-cloudbuild-connection"

  github_config {
    app_installation_id = var.github_cloub_build_id
    authorizer_credential {
      oauth_token_secret_version = google_secret_manager_secret_version.github_token_secret_version.id
    }
  }
  depends_on = [google_secret_manager_secret_iam_policy.policy]
}
# レポジトリとの接続
resource "google_cloudbuildv2_repository" "frontend_repository" {
  project           = var.project
  location          = "us-central1"
  name              = "${var.app_name}-frontend-repo"
  parent_connection = google_cloudbuildv2_connection.my_connection.name
  remote_uri        = var.github_frontend_repository_uri
}

resource "google_cloudbuildv2_repository" "backend_repository" {
  project           = var.project
  location          = "us-central1"
  name              = "${var.app_name}-backend-repo"
  parent_connection = google_cloudbuildv2_connection.my_connection.name
  remote_uri        = var.github_backend_repository_uri
}

# トリガーを設定する
resource "google_cloudbuild_trigger" "frontend-trigger" {
  name     = "${var.app_name}-frontend-push"
  location = "us-central1"

  repository_event_config {
    repository = google_cloudbuildv2_repository.frontend_repository.id
    push {
      branch = "main"
    }
  }

  substitutions = {
    _PROJECT    = var.project
    _REGION     = var.region
    _LOCATION   = var.location
    _REPOSITORY = google_artifact_registry_repository.my-repo.repository_id
    _IMAGE      = "moncon_frontend"
  }

  filename = "cloudbuild.yaml"
}
resource "google_cloudbuild_trigger" "backend-trigger" {
  name     = "${var.app_name}-backend-push"
  location = "us-central1"

  repository_event_config {
    repository = google_cloudbuildv2_repository.backend_repository.id
    push {
      branch = "main"
    }
  }

  substitutions = {
    _PROJECT    = var.project
    _REGION     = var.region
    _LOCATION   = var.location
    _REPOSITORY = google_artifact_registry_repository.my-repo.repository_id
    _IMAGE      = "moncon_backend"
  }

  filename = "cloudbuild.yaml"
}

# artifact repositoryの設定
resource "google_artifact_registry_repository" "my-repo" {
  location      = "asia-northeast1"
  repository_id = "${var.app_name}-repository"
  description   = "docker repository"
  format        = "DOCKER"

  docker_config {
    immutable_tags = false
  }
}

# cloudrunの設定
resource "google_cloud_run_v2_service" "frontend" {
  name     = "frontend"
  location = "asia-northeast1"

  template {
    containers {
      image = "us-docker.pkg.dev/cloudrun/container/hello"
    }
  }
}
resource "google_cloud_run_v2_service" "backend" {
  name     = "backend"
  location = "asia-northeast1"

  template {
    containers {
      image = "us-docker.pkg.dev/cloudrun/container/hello"
    }
  }
}
resource "google_cloud_run_service_iam_binding" "frontend" {
  location = google_cloud_run_v2_service.frontend.location
  service  = google_cloud_run_v2_service.frontend.name
  role     = "roles/run.invoker"
  members = [
    "allUsers"
  ]
}

# テストのためにallUser許可、最終的に閉じる
resource "google_cloud_run_service_iam_binding" "backend" {
  location = google_cloud_run_v2_service.backend.location
  service  = google_cloud_run_v2_service.backend.name
  role     = "roles/run.invoker"
  members = [
    "allUsers"
  ]
}

# create database
resource "google_sql_database_instance" "main" {
  name                = "${var.app_name}-db"
  database_version    = var.db_ver
  region              = var.region
  root_password       = var.db_root_pass
  deletion_protection = false

  settings {
    tier              = "db-f1-micro"
    edition           = "ENTERPRISE"
    availability_type = "ZONAL"
    disk_type         = "PD_HDD"
    disk_size         = 10
    backup_configuration {
      enabled = false
    }
  }
}
