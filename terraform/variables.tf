variable "project_id" {
  description = "Google Cloud project in which to create the platform."
  type        = string
}

variable "region" {
  description = "Region shared by Cloud Run, Cloud Storage, and Artifact Registry."
  type        = string
  default     = "europe-west2"
}

variable "container_image" {
  description = "Image to deploy. Nginx is the initial assessment placeholder."
  type        = string
  default     = "nginx:stable-alpine"
}

variable "container_port" {
  description = "Container port (80 for Nginx, 8080 for the Python service)."
  type        = number
  default     = 80
}

variable "bucket_name" {
  description = "Optional globally unique bucket name. Defaults to a project-specific name."
  type        = string
  default     = ""
}

variable "min_instance_count" {
  description = "Minimum Cloud Run instances."
  type        = number
  default     = 1
}

variable "max_instance_count" {
  description = "Maximum Cloud Run instances. Tune after load testing and quota review."
  type        = number
  default     = 100
}

variable "max_instance_request_concurrency" {
  description = "Maximum concurrent requests per Cloud Run instance. Tune after load testing."
  type        = number
  default     = 80
}

variable "allow_unauthenticated" {
  description = "Grant allUsers Cloud Run invoker access. Use only for the temporary Nginx placeholder."
  type        = bool
  default     = true
}

variable "api_token_secret_name" {
  description = "Name of a Secret Manager secret created outside Terraform. Empty disables secret injection."
  type        = string
  default     = ""
}

variable "api_token_secret_version" {
  description = "Secret Manager version injected as API_TOKEN. Pin a numeric version for production."
  type        = string
  default     = "latest"
}

variable "api_token_customer_id" {
  description = "Customer ID this exercise API token is authorized to access."
  type        = string
  default     = "demo-customer"
}

variable "enable_external_https_lb" {
  description = "Create a global external HTTPS load balancer with Cloud Armor in front of Cloud Run. Requires a domain you control and DNS update access."
  type        = bool
  default     = false
}

variable "enable_external_http_lb" {
  description = "Create an HTTP-only external load balancer with Cloud Armor for a temporary demo. HTTP traffic is unencrypted; use only with test credentials and data."
  type        = bool
  default     = false
}

variable "lb_domain" {
  description = "Fully qualified domain name for the managed HTTPS certificate, for example files.example.com."
  type        = string
  default     = ""

  validation {
    condition     = length(var.lb_domain) == 0 || can(regex("^[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.lb_domain))
    error_message = "lb_domain must be a fully qualified domain name such as files.example.com."
  }
}
