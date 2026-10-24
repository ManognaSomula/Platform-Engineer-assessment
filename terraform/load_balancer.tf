# Optional global external Application Load Balancer for the customer API.
# Enable it only after choosing a domain and preparing its DNS A record.
resource "google_compute_global_address" "api_lb" {
  count = local.enable_external_lb ? 1 : 0

  name         = "customer-file-service-ip"
  address_type = "EXTERNAL"
  ip_version   = "IPV4"
}

resource "google_compute_region_network_endpoint_group" "api" {
  count = local.enable_external_lb ? 1 : 0

  name                  = "customer-file-service-neg"
  network_endpoint_type = "SERVERLESS"
  region                = var.region

  cloud_run {
    service = google_cloud_run_v2_service.api.name
  }
}

resource "google_compute_security_policy" "api" {
  count = local.enable_external_lb ? 1 : 0

  name        = "customer-file-service-armor"
  description = "Cloud Armor WAF policy for the customer file API"
  type        = "CLOUD_ARMOR"

  # OWASP preconfigured protections. Sensitivity 1 reduces false positives for
  # a file retrieval API; inspect logs and tune exclusions before production.
  rule {
    action   = "deny(403)"
    priority = 1000
    preview  = false
    match {
      expr {
        expression = "evaluatePreconfiguredWaf('sqli-v33-stable', {'sensitivity': 1})"
      }
    }
    description = "Block SQL injection patterns"
  }

  rule {
    action   = "deny(403)"
    priority = 1100
    preview  = false
    match {
      expr {
        expression = "evaluatePreconfiguredWaf('xss-v33-stable', {'sensitivity': 1})"
      }
    }
    description = "Block cross-site scripting patterns"
  }

  rule {
    action   = "allow"
    priority = 2147483647
    match {
      expr {
        expression = "true"
      }
    }
    description = "Default allow; application authorization still applies"
  }
}

resource "google_compute_backend_service" "api" {
  count = local.enable_external_lb ? 1 : 0

  name                  = "customer-file-service-backend"
  protocol              = "HTTP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  security_policy       = google_compute_security_policy.api[0].id

  backend {
    group = google_compute_region_network_endpoint_group.api[0].id
  }

  log_config {
    enable      = true
    sample_rate = 1.0
  }
}

resource "google_compute_url_map" "api_https" {
  count = var.enable_external_https_lb ? 1 : 0

  name            = "customer-file-service-https-map"
  default_service = google_compute_backend_service.api[0].id
  host_rule {
    hosts        = [var.lb_domain]
    path_matcher = "all-paths"
  }
  path_matcher {
    name            = "all-paths"
    default_service = google_compute_backend_service.api[0].id
  }
}

# For the temporary no-domain mode, serve directly over HTTP. When HTTPS is
# enabled, the port-80 listener instead redirects to the HTTPS hostname.
resource "google_compute_url_map" "api_http" {
  count = var.enable_external_http_lb && !var.enable_external_https_lb ? 1 : 0

  name            = "customer-file-service-http-map"
  default_service = google_compute_backend_service.api[0].id
}

resource "google_compute_managed_ssl_certificate" "api" {
  count = var.enable_external_https_lb ? 1 : 0

  name = "customer-file-service-cert"
  managed {
    domains = [var.lb_domain]
  }

  lifecycle {
    precondition {
      condition     = length(var.lb_domain) > 0
      error_message = "Set lb_domain to a domain you control before enabling the HTTPS load balancer."
    }
  }
}

resource "google_compute_target_https_proxy" "api" {
  count = var.enable_external_https_lb ? 1 : 0

  name             = "customer-file-service-https-proxy"
  url_map          = google_compute_url_map.api_https[0].id
  ssl_certificates = [google_compute_managed_ssl_certificate.api[0].id]
}

resource "google_compute_global_forwarding_rule" "https" {
  count = var.enable_external_https_lb ? 1 : 0

  name                  = "customer-file-service-https-forwarding-rule"
  ip_address            = google_compute_global_address.api_lb[0].address
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_range            = "443"
  target                = google_compute_target_https_proxy.api[0].id
  network_tier          = "PREMIUM"
}

# Redirect clear-text HTTP to the managed HTTPS endpoint.
resource "google_compute_url_map" "http_redirect" {
  count = var.enable_external_https_lb ? 1 : 0

  name = "customer-file-service-http-redirect"
  default_url_redirect {
    https_redirect         = true
    strip_query            = false
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
  }
}

resource "google_compute_target_http_proxy" "http_redirect" {
  count = local.enable_external_lb ? 1 : 0

  name    = "customer-file-service-http-proxy"
  url_map = var.enable_external_https_lb ? google_compute_url_map.http_redirect[0].id : google_compute_url_map.api_http[0].id
}

resource "google_compute_global_forwarding_rule" "http" {
  count = local.enable_external_lb ? 1 : 0

  name                  = "customer-file-service-http-forwarding-rule"
  ip_address            = google_compute_global_address.api_lb[0].address
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_range            = "80"
  target                = google_compute_target_http_proxy.http_redirect[0].id
  network_tier          = "PREMIUM"
}
