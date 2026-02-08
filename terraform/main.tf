terraform {
  required_version = "~> 1.14.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

/*
Fetch the public IP addresses of cloudflare to allow requests to our ALB 
(and the nginx service) to be avaiable only from Cloudflare network
Thus not allow users to bypass Cloudflare protection
 */
data "http" "cloudflare_ipv4" {
  url = "https://www.cloudflare.com/ips-v4"
}

locals {
  tags = {
    Terraform   = "true"
    Environment = "prod"
    Project     = var.project_name
  }
  cloudflare_ipv4_cidrs = [for cidr in split("\n", trimspace(data.http.cloudflare_ipv4.response_body)) : cidr if cidr != ""]
}

resource "aws_acm_certificate" "main" {
  domain_name       = "tomerc.com"
  validation_method = "DNS"
  tags              = local.tags

  lifecycle {
    create_before_destroy = true
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = "${var.project_name}-vpc"
  cidr = var.vpc_cidr

  azs             = ["${var.aws_region}a", "${var.aws_region}b"]
  public_subnets  = [cidrsubnet(var.vpc_cidr, 8, 1), cidrsubnet(var.vpc_cidr, 8, 2)]
  private_subnets = [cidrsubnet(var.vpc_cidr, 8, 3)]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  tags = local.tags
}

module "alb_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name        = "${var.project_name}-alb-sg"
  description = "ALB security group"
  vpc_id      = module.vpc.vpc_id

  ingress_with_cidr_blocks = [
    for cidr in local.cloudflare_ipv4_cidrs : {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      description = "Cloudflare"
      cidr_blocks = cidr
    }
  ]

  egress_with_cidr_blocks = [
    {
      from_port   = 8080
      to_port     = 8080
      protocol    = "tcp"
      description = "To EC2"
      cidr_blocks = var.vpc_cidr
    }
  ]

  tags = local.tags
}

module "ec2_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name        = "${var.project_name}-ec2-sg"
  description = "EC2 security group"
  vpc_id      = module.vpc.vpc_id

  ingress_with_source_security_group_id = [
    {
      from_port                = 8080
      to_port                  = 8080
      protocol                 = "tcp"
      description              = "From ALB"
      source_security_group_id = module.alb_sg.security_group_id
    }
  ]

  egress_cidr_blocks = ["0.0.0.0/0"]
  egress_rules       = ["http-80-tcp", "https-443-tcp"]

  tags = local.tags
}

module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 10.0"

  name               = "${var.project_name}-alb"
  load_balancer_type = "application"
  vpc_id             = module.vpc.vpc_id
  subnets            = module.vpc.public_subnets
  security_groups    = [module.alb_sg.security_group_id]

  listeners = {
    https = {
      port            = 443
      protocol        = "HTTPS"
      ssl_policy      = "ELBSecurityPolicy-TLS13-1-2-2021-06"
      certificate_arn = aws_acm_certificate.main.arn
      forward = {
        target_group_key = "nginx"
      }
    }
  }

  target_groups = {
    nginx = {
      name_prefix = "nginx-"
      protocol    = "HTTP"
      port        = 8080
      target_type = "instance"
      target_id   = aws_instance.nginx.id
    }
  }

  tags = local.tags
}

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "ec2_ssm" {
  name               = "${var.project_name}-ec2-ssm-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "ssm_attach" {
  role       = aws_iam_role.ec2_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_ssm" {
  name = "${var.project_name}-ec2-ssm-profile"
  role = aws_iam_role.ec2_ssm.name

  tags = local.tags
}

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "nginx" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t3.micro"
  subnet_id              = module.vpc.private_subnets[0]
  vpc_security_group_ids = [module.ec2_sg.security_group_id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_ssm.name

  root_block_device {
    encrypted = true
  }

  user_data = <<-EOF
    #!/bin/bash
    dnf update -y && dnf upgrade -y
    dnf install -y docker
    systemctl enable --now docker
  EOF

  tags = merge(local.tags, { Name = "${var.project_name}-nginx" })
}

module "cicd_policy" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-policy"
  version = "~> 6.0"

  name        = "${var.project_name}-cicd-policy"
  description = "Least-privilege policy for GitHub Actions CI/CD deployment"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DescribeInstances"
        Effect   = "Allow"
        Action   = ["ec2:DescribeInstances"]
        Resource = "*"
      },
      {
        Sid    = "SSMDeploy"
        Effect = "Allow"
        Action = [
          "ssm:SendCommand",
          "ssm:GetCommandInvocation"
        ]
        Resource = "*"
      }
    ]
  })

  tags = local.tags
}

module "cicd_user" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-user"
  version = "~> 6.0"

  name = "${var.project_name}-cicd"

  create_access_key  = true
  create_login_profile = false

  tags = local.tags
}

resource "aws_iam_user_policy_attachment" "cicd" {
  user       = module.cicd_user.name
  policy_arn = module.cicd_policy.arn
}
