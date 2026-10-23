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
