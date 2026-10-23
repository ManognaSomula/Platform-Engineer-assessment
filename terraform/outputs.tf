output "service_url" {
  description = "Cloud Run service URL."
  value       = google_cloud_run_v2_service.api.uri
}

output "storage_bucket" {
  description = "Private customer file bucket name."
  value       = google_storage_bucket.files.name
}

output "runtime_service_account" {
  description = "Cloud Run runtime service account email."
  value       = google_service_account.runtime.email
}

output "artifact_registry_repository" {
  description = "Docker repository URL for the service image."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.service.repository_id}"
}
