output "alb_dns_name" {
  description = "ALB DNS name"
  value       = module.alb.dns_name
}

output "app_url" {
  description = "Application URL"
  value       = "http://${module.alb.dns_name}"
}

output "cicd_access_key_id" {
  description = "CI/CD IAM user access key ID"
  value       = module.cicd_user.access_key_id
}

output "cicd_secret_access_key" {
  description = "CI/CD IAM user secret access key"
  value       = module.cicd_user.access_key_secret
}
