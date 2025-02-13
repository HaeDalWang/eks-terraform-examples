# VPC
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.8.1"

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

# ===================================================== #  
# Cluster의 접근을 ClientVPN으로 할 경우 추가하는 항목
# ===================================================== #  

# # ClientVPN에 부여할 보안그룹
# module "client_vpn_sg" {
#   source  = "terraform-aws-modules/security-group/aws"
#   version = "5.1.2"

#   name        = "${local.project}-client-vpn-sg"
#   description = "${local.project} client vpn security group"
#   vpc_id      = module.vpc.vpc_id

#   # 모든 아웃바운드 허용
#   egress_cidr_blocks = ["0.0.0.0/0"]
#   egress_rules       = ["all-all"]
# }

# # ClientVPN 생성
# resource "aws_ec2_client_vpn_endpoint" "this" {
#   server_certificate_arn = aws_acm_certificate.service_domain.arn
#   client_cidr_block      = "10.239.0.0/16"
#   vpc_id                 = module.vpc.vpc_id
#   security_group_ids     = [module.client_vpn_sg.security_group_id]
#   self_service_portal    = "enabled"
#   split_tunnel           = true
#   dns_servers            = ["10.240.0.2"]

#   authentication_options {
#     type              = "federated-authentication"
#     saml_provider_arn = aws_iam_saml_provider.client_vpn.arn
#   }

#   connection_log_options {
#     enabled = false
#   }

#   tags = {
#     "Name" = local.project
#   }
# }

# # ClientVPN을 모든 프라이빗 서브넷에 연동
# resource "aws_ec2_client_vpn_network_association" "this" {
#   for_each = toset(module.vpc.private_subnets)

#   client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.this.id
#   subnet_id              = each.key
# }

# # ClientVPN이 생성된 VPC로 가는 트래픽 허용
# resource "aws_ec2_client_vpn_authorization_rule" "this" {
#   client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.this.id
#   target_network_cidr    = module.vpc.vpc_cidr_block
#   authorize_all_groups   = true
# }

# # ClientVPN이 생성된 VPC에 연결된 모든 Peering 연결 목록 불러오기
# data "aws_vpc_peering_connections" "pcs" {
#   filter {
#     name   = "status-code"
#     values = ["active"]
#   }

#   filter {
#     name   = "accepter-vpc-info.vpc-id"
#     values = [module.vpc.vpc_id]
#   }
# }

# # ClientVPN이 생성된 VPC에 연결된 각각의 Peering 연결에 대한 정보 불러오기
# data "aws_vpc_peering_connection" "pc" {
#   count = length(data.aws_vpc_peering_connections.pcs.ids)

#   id = data.aws_vpc_peering_connections.pcs.ids[count.index]
# }

# # ClientVPN이 생성된 각각의 프라이빗 서브넷에 Peering 연결이된 VPC로 가는 경로 추가
# resource "aws_ec2_client_vpn_route" "pc" {
#   for_each = {
#     for item in flatten([
#       for subnet in module.vpc.private_subnets : [
#         for pc in data.aws_vpc_peering_connection.pc : {
#           subnet     = subnet
#           cidr_block = pc.cidr_block
#         }
#       ]
#     ])
#     : "${item.subnet}-${item.cidr_block}" => item
#   }

#   client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.this.id
#   destination_cidr_block = each.value.cidr_block
#   target_vpc_subnet_id   = aws_ec2_client_vpn_network_association.this[each.value.subnet].subnet_id
# }

# # Peering으로 연결된 VPC로 가는 트래픽 허용
# resource "aws_ec2_client_vpn_authorization_rule" "pc" {
#   for_each = { for pc in data.aws_vpc_peering_connection.pc : pc.id => pc }

#   client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.this.id
#   target_network_cidr    = each.value.cidr_block
#   authorize_all_groups   = true
# }