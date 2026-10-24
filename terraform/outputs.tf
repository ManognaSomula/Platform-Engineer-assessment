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

output "load_balancer_ip" {
  description = "Static IPv4 address for the optional external load balancer. For HTTPS, create a DNS A record pointing your domain here."
  value       = local.enable_external_lb ? google_compute_global_address.api_lb[0].address : null
}

output "load_balancer_url" {
  description = "Customer API URL through the optional external load balancer."
  value       = var.enable_external_https_lb ? "https://${var.lb_domain}" : (var.enable_external_http_lb ? "http://${google_compute_global_address.api_lb[0].address}" : null)
}
