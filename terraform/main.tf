locals {
  bucket_name        = var.bucket_name != "" ? var.bucket_name : "${var.project_id}-customer-files"
  enable_external_lb = var.enable_external_http_lb || var.enable_external_https_lb
  labels = {
    application = "customer-file-service"
    managed_by  = "terraform"
  }
}

resource "google_project_service" "required" {
  for_each = toset([
    "artifactregistry.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "iam.googleapis.com",
    "run.googleapis.com",
    "secretmanager.googleapis.com",
    "storage.googleapis.com",
  ])

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_storage_bucket" "files" {
  name                        = local.bucket_name
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false
  labels                      = local.labels

  versioning {
    enabled = true
  }

  depends_on = [google_project_service.required]
}

resource "google_artifact_registry_repository" "service" {
  location      = var.region
  repository_id = "file-service"
  description   = "Container images for the customer file retrieval service"
  format        = "DOCKER"
  labels        = local.labels

  depends_on = [google_project_service.required]
}

resource "google_service_account" "runtime" {
  account_id   = "file-service-runtime"
  display_name = "Customer file service runtime"
  depends_on   = [google_project_service.required]
}

resource "google_storage_bucket_iam_member" "read_files" {
  bucket = google_storage_bucket.files.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.runtime.email}"
}

# The secret itself and its value are created separately with gcloud so the
# secret payload never enters Terraform state.
data "google_secret_manager_secret" "api_token" {
  count     = var.api_token_secret_name == "" ? 0 : 1
  secret_id = var.api_token_secret_name
  project   = var.project_id
}

resource "google_secret_manager_secret_iam_member" "api_token_accessor" {
  count     = var.api_token_secret_name == "" ? 0 : 1
  secret_id = data.google_secret_manager_secret.api_token[0].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.runtime.email}"
}

resource "google_cloud_run_v2_service" "api" {
  name                = "customer-file-service"
  location            = var.region
  ingress             = local.enable_external_lb ? "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER" : "INGRESS_TRAFFIC_ALL"
  deletion_protection = false
  labels              = local.labels

  template {
    service_account                  = google_service_account.runtime.email
    timeout                          = "30s"
    max_instance_request_concurrency = var.max_instance_request_concurrency
    labels                           = local.labels

    scaling {
      min_instance_count = var.min_instance_count
      max_instance_count = var.max_instance_count
    }

    containers {
      image = var.container_image

      ports {
        container_port = var.container_port
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        cpu_idle = true
      }

      env {
        name  = "GCS_BUCKET"
        value = google_storage_bucket.files.name
      }

      env {
        name  = "API_TOKEN_CUSTOMER_ID"
        value = var.api_token_customer_id
      }

      dynamic "env" {
        for_each = var.api_token_secret_name == "" ? [] : [true]
        content {
          name = "API_TOKEN"
          value_source {
            secret_key_ref {
              secret  = data.google_secret_manager_secret.api_token[0].secret_id
              version = var.api_token_secret_version
            }
          }
        }
      }
    }
  }

  depends_on = [
    google_project_service.required,
    google_storage_bucket_iam_member.read_files,
    google_secret_manager_secret_iam_member.api_token_accessor,
    google_artifact_registry_repository.service,
  ]
}

# This is intended only for the temporary Nginx placeholder. Set false when
# deploying the protected Python service.
resource "google_cloud_run_v2_service_iam_member" "public_invoker" {
  # Serverless NEG requests do not carry a caller's Cloud Run identity token.
  # When the LB is enabled, ingress is restricted to the LB, while the app's
  # own customer authorization remains responsible for allowing requests.
  count    = (var.allow_unauthenticated || local.enable_external_lb) ? 1 : 0
  name     = google_cloud_run_v2_service.api.name
  location = google_cloud_run_v2_service.api.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}
