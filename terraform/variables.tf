variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "il-central-1"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "yo-nginx"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

