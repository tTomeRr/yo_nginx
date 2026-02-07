# Deployment Guide

## Prerequisites

- AWS CLI configured with admin credentials (`aws configure`)
- Terraform
- Docker
- Cloudflare Account

## 1. Deploy Infrastructure

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

Save the outputs:

```bash
terraform output alb_dns_name          # For Cloudflare DNS
terraform output cicd_access_key_id    # For GitHub secret
terraform output cicd_secret_access_key  # For GitHub secret
```

## 2. Configure GitHub Secrets

Go to GitHub repo → Settings → Secrets and variables → Actions, and add:

| Secret | Value |
|---|---|
| `DOCKERHUB_USERNAME` | DockerHub username |
| `DOCKERHUB_TOKEN` | DockerHub access token |
| `AWS_ACCESS_KEY_ID` | From `terraform output cicd_access_key_id` |
| `AWS_SECRET_ACCESS_KEY` | From `terraform output cicd_secret_access_key` |

## 3. Deploy Application

Push to `main` branch. This will trigger the CI/CD pipeline automatically

## 4. Configure Cloudflare

Add a CNAME record:
   - **Name:** `@` or `www`
   - **Target:** ALB DNS name from terraform output
   - **Proxy:** Enabled

## 5. Verify

```bash
curl https://yourdomain.com
```

Expected response: `yo this is nginx`
