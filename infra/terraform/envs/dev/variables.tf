variable "region" {
  type    = string
  default = "us-east-1"
}

variable "profile" {
  type    = string
  default = "default"
}

variable "project" {
  type    = string
  default = "atl-news"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "image_tag" {
  type        = string
  default     = "latest"
  description = "ECR image tag for both api and fetcher tasks"
}

variable "fetcher_schedule" {
  type        = string
  default     = "rate(10 minutes)"
  description = "EventBridge Scheduler schedule expression"
}
