# =============================================================================
# Istio Mesh Primary Cluster - Terraform 변수
# =============================================================================

# 네트워크
vpc_cidr    = "10.210.0.0/16"
domain_name = "example.com" # 실제 Route53 도메인으로 변경

# EKS
eks_cluster_version             = "1.35"
eks_node_ami_alias_bottlerocket = "bottlerocket@1.54.0"

# 기본 인프라 Helm 차트 버전
karpenter_chart_version                    = "1.8.3"
aws_load_balancer_controller_chart_version = "1.17.0"
external_dns_chart_version                 = "1.19.0"

# Istio
istio_chart_version = "1.25.2"
mesh_id             = "istio-mesh"
cluster_name        = "primary"
network_name        = "network-1"
