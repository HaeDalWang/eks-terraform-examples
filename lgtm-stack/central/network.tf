module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.5.1"

  name = local.project
  cidr = var.vpc_cidr

  azs             = data.aws_availability_zones.azs.names
  public_subnets  = [for idx, _ in data.aws_availability_zones.azs.names : cidrsubnet(var.vpc_cidr, 8, idx)]
  private_subnets = [for idx, _ in data.aws_availability_zones.azs.names : cidrsubnet(var.vpc_cidr, 8, idx + 10)]
  intra_subnets   = [for idx, _ in data.aws_availability_zones.azs.names : cidrsubnet(var.vpc_cidr, 8, idx + 20)]

  default_security_group_egress = [
    {
      cidr_blocks      = "0.0.0.0/0"
      ipv6_cidr_blocks = "::/0"
    }
  ]

  enable_nat_gateway = true
  single_nat_gateway = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    "karpenter.sh/discovery"          = local.project
  }
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id       = module.vpc.vpc_id
  service_name = "com.amazonaws.${data.aws_region.current.id}.s3"
  subnet_ids   = module.vpc.private_subnets

  tags = {
    Name = "${local.project}-s3-endpoint"
  }

  lifecycle {
    ignore_changes = [subnet_ids]
  }
}
