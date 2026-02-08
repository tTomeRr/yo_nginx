# yo_nginx

## TL;DR

- **Live at [tomerc.com](https://tomerc.com)**
- This repository deploys an nginx container running on AWS EC2 behind an ALB, with fully automated CI/CD via GitHub Actions. 
- See [docs/steps.md](docs/steps.md) for deployment instructions.

## Architecture
<img width="742" height="731" alt="aa" src="https://github.com/user-attachments/assets/b2aab283-a206-482c-8619-977caf2e166d" />


```
User -> Cloudflare (DNS + proxy) -> ALB -> EC2 -> nginx container
```

- **VPC** with 2 public subnets (ALB) and 1 private subnet (EC2), single NAT gateway
- **ALB** accepts HTTPS traffic only from Cloudflare IP ranges (ACM certificate for `tomerc.com`)
- **EC2** `t3.micro` in a private subnet, accessible only via SSM (no SSH), receives traffic only from the ALB on port 8080
- **Cloudflare** handles DNS, TLS termination to the ALB, and acts as a CDN/WAF layer

## CI/CD

Triggered on every push to `main`:

```
Checkout -> Gitleaks -> Docker Build -> Trivy (vuln scan) -> Smoke Test -> Push to DockerHub -> Deploy via SSM
```

- **Gitleaks** scans for leaked secrets in the repo
- **Trivy** enforces vulnerability thresholds (HIGH <= 5, CRITICAL <= 2)
- **Smoke test** runs the container and verifies the expected response
- **Deploy** uses AWS SSM `send-command` to pull and run the new image on EC2 — no SSH keys needed
- Image pushed to DockerHub as `ttomerr/yonginx`

## Tech Stack

| Layer | Technology |
|---|---|
| Web server | nginx |
| Compute | AWS EC2 |
| Networking | AWS VPC, ALB, ACM |
| DNS/CDN | Cloudflare |
| IaC | Terraform |
| CI/CD | GitHub Actions |
| Container registry | DockerHub |
| Security scanning | Gitleaks, Trivy |
| Remote access | AWS SSM |

## Project Structure

```
nginx/           # Dockerfile, nginx.conf, index.html
terraform/       # AWS infrastructure (VPC, ALB, EC2, IAM)
.github/workflows/cicd.yml  # CI/CD pipeline
docs/            # Deployment guide
```
