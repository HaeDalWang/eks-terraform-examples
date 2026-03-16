# =============================================================================
# seungdo 환경 - Terraform 변수
# =============================================================================

# VPC 대역대
vpc_cidr    = "10.100.0.0/16"
# Route53에 이미 사용중인 도메인 이름 및 호스팅존 명
domain_name = "seungdobae.com"

# EKS
eks_cluster_version = "1.35"

# EKS 보틀로켓 노드 AMI 별칭 (클러스터 버전에 맞게 갱신 필요)
eks_node_ami_alias_bottlerocket = "bottlerocket@1.54.0"

# Helm 차트 버전 (현재 클러스터 배포 버전과 동일하게 유지)
karpenter_chart_version                    = "1.8.3"
aws_load_balancer_controller_chart_version = "1.17.0"
external_dns_chart_version                 = "1.19.0"