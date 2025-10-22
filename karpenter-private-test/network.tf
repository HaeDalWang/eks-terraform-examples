# VPC 및 VPC 엔드포인트 설정
# 
# Karpenter 스펙에 맞는 VPC 엔드포인트들:
# - S3 (Gateway): 컨테이너 이미지 풀링용
# - EC2 (Interface): 인스턴스 메타데이터, 태그 등
# - ECR API (Interface): 컨테이너 이미지 풀링용
# - ECR DKR (Interface): 컨테이너 이미지 풀링용  
# - STS (Interface): IAM 역할 서비스 계정용
# - SSM (Interface): 기본 AMI 해결용
# - SSM Messages (Interface): SSM 에이전트 통신
# - EC2 Messages (Interface): EC2 인스턴스 통신
# - SQS (Interface): 중단 처리용
# - EKS (Interface): 클러스터 엔드포인트 발견용

# VPC
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.21.0"

  name = local.project
  cidr = var.vpc_cidr

  azs             = data.aws_availability_zones.azs.names
  public_subnets  = [for idx, _ in data.aws_availability_zones.azs.names : cidrsubnet(var.vpc_cidr, 8, idx)]
  private_subnets = [for idx, _ in data.aws_availability_zones.azs.names : cidrsubnet(var.vpc_cidr, 8, idx + 10)]

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
    # Karpenter는 이제 ID로 직접 참조하므로 태그 불필요
  }
}

# # VPC 엔드포인트 - S3 (Gateway)
# resource "aws_vpc_endpoint" "s3" {
#   vpc_id            = module.vpc.vpc_id
#   service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
#   vpc_endpoint_type = "Gateway"
  
#   route_table_ids = module.vpc.private_route_table_ids
  
#   tags = merge(local.tags, {
#     Name = "${local.project}-s3-endpoint"
#   })
# }

# VPC 엔드포인트 - EC2 (Interface)
resource "aws_vpc_endpoint" "ec2" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ec2"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  
  private_dns_enabled = true
  
  tags = merge(local.tags, {
    Name = "${local.project}-ec2-endpoint"
  })
}

# VPC 엔드포인트 - SSM (Interface)
resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  
  private_dns_enabled = true
  
  tags = merge(local.tags, {
    Name = "${local.project}-ssm-endpoint"
  })
}

# VPC 엔드포인트 - SSM Messages (Interface)
resource "aws_vpc_endpoint" "ssm_messages" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  
  private_dns_enabled = true
  
  tags = merge(local.tags, {
    Name = "${local.project}-ssm-messages-endpoint"
  })
}

# VPC 엔드포인트 - EC2 Messages (Interface)
resource "aws_vpc_endpoint" "ec2_messages" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  
  private_dns_enabled = true
  
  tags = merge(local.tags, {
    Name = "${local.project}-ec2-messages-endpoint"
  })
}

# # VPC 엔드포인트 - ECR API (Interface) - 컨테이너 이미지 풀링용
# resource "aws_vpc_endpoint" "ecr_api" {
#   vpc_id              = module.vpc.vpc_id
#   service_name        = "com.amazonaws.${data.aws_region.current.name}.ecr.api"
#   vpc_endpoint_type   = "Interface"
#   subnet_ids          = module.vpc.private_subnets
#   security_group_ids  = [aws_security_group.vpc_endpoints.id]
  
#   private_dns_enabled = true
  
#   tags = merge(local.tags, {
#     Name = "${local.project}-ecr-api-endpoint"
#   })
# }

# # VPC 엔드포인트 - ECR DKR (Interface) - 컨테이너 이미지 풀링용
# resource "aws_vpc_endpoint" "ecr_dkr" {
#   vpc_id              = module.vpc.vpc_id
#   service_name        = "com.amazonaws.${data.aws_region.current.name}.ecr.dkr"
#   vpc_endpoint_type   = "Interface"
#   subnet_ids          = module.vpc.private_subnets
#   security_group_ids  = [aws_security_group.vpc_endpoints.id]
  
#   private_dns_enabled = true
  
#   tags = merge(local.tags, {
#     Name = "${local.project}-ecr-dkr-endpoint"
#   })
# }

# # VPC 엔드포인트 - STS (Interface) - IAM 역할 서비스 계정용
# resource "aws_vpc_endpoint" "sts" {
#   vpc_id              = module.vpc.vpc_id
#   service_name        = "com.amazonaws.${data.aws_region.current.name}.sts"
#   vpc_endpoint_type   = "Interface"
#   subnet_ids          = module.vpc.private_subnets
#   security_group_ids  = [aws_security_group.vpc_endpoints.id]
  
#   private_dns_enabled = true
  
#   tags = merge(local.tags, {
#     Name = "${local.project}-sts-endpoint"
#   })
# }

# # VPC 엔드포인트 - SQS (Interface) - 중단 처리용
# resource "aws_vpc_endpoint" "sqs" {
#   vpc_id              = module.vpc.vpc_id
#   service_name        = "com.amazonaws.${data.aws_region.current.name}.sqs"
#   vpc_endpoint_type   = "Interface"
#   subnet_ids          = module.vpc.private_subnets
#   security_group_ids  = [aws_security_group.vpc_endpoints.id]
  
#   private_dns_enabled = true
  
#   tags = merge(local.tags, {
#     Name = "${local.project}-sqs-endpoint"
#   })
# }

# # VPC 엔드포인트 - EKS (Interface) - 클러스터 엔드포인트 발견용
# resource "aws_vpc_endpoint" "eks" {
#   vpc_id              = module.vpc.vpc_id
#   service_name        = "com.amazonaws.${data.aws_region.current.name}.eks"
#   vpc_endpoint_type   = "Interface"
#   subnet_ids          = module.vpc.private_subnets
#   security_group_ids  = [aws_security_group.vpc_endpoints.id]
  
#   private_dns_enabled = true
  
#   tags = merge(local.tags, {
#     Name = "${local.project}-eks-endpoint"
#   })
# }

# VPC 엔드포인트용 보안 그룹
resource "aws_security_group" "vpc_endpoints" {
  name_prefix = "${local.project}-vpc-endpoints-"
  vpc_id      = module.vpc.vpc_id
  
  # HTTPS 트래픽 허용 (VPC 엔드포인트 통신용)
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "HTTPS from VPC"
  }
  
  # 모든 아웃바운드 트래픽 허용
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }
  
  tags = merge(local.tags, {
    Name = "${local.project}-vpc-endpoints-sg"
  })
}