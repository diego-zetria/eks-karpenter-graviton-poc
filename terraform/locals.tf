locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)

  # Three-tier subnet architecture:
  #   Public   /24  → ALB, NAT Gateway (internet-facing)
  #   Private  /20  → EKS compute nodes (application tier)
  #   Database /24  → Aurora, Redis (secure/isolated data tier)
  private_subnets  = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 4, k)]       # 10.0.{0,16,32}.0/20
  public_subnets   = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k + 48)]  # 10.0.{48,49,50}.0/24
  database_subnets = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k + 64)]  # 10.0.{64,65,66}.0/24
}

data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.virginia
}
