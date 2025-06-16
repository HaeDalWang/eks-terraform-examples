# VPC
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.21.0"

  name = local.project
  cidr = var.vpc_cidr

  azs              = data.aws_availability_zones.azs.names
  public_subnets   = [for idx, _ in data.aws_availability_zones.azs.names : cidrsubnet(var.vpc_cidr, 8, idx)]
  private_subnets  = [for idx, _ in data.aws_availability_zones.azs.names : cidrsubnet(var.vpc_cidr, 8, idx + 10)]
  database_subnets = [for idx, _ in data.aws_availability_zones.azs.names : cidrsubnet(var.vpc_cidr, 8, idx + 20)]
  intra_subnets    = [for idx, _ in data.aws_availability_zones.azs.names : cidrsubnet(var.vpc_cidr, 8, idx + 30)]

  default_security_group_egress = [
    {
      cidr_blocks      = "0.0.0.0/0"
      ipv6_cidr_blocks = "::/0"
    }
  ]

  enable_nat_gateway = true
  single_nat_gateway = true

  # 외부 접근용 ALB/NLB를 생성할 서브넷에요구되는 태그
  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    # VPC 내부용 ALB/NLB를 생성할 서브넷에 요구되는 태그
    "kubernetes.io/role/internal-elb" = 1
    # Karpenter가 노드를 생성할 서브넷에 요구되는 태그
    "karpenter.sh/discovery" = local.project
  }
}