# =============================================================================
# LGTM Central (관리 클러스터) - Terraform 변수
# =============================================================================

# 네트워크
vpc_cidr    = "10.200.0.0/16"
domain_name = "example.com" # 실제 Route53 도메인으로 변경

# EKS
eks_cluster_version             = "1.35"
eks_node_ami_alias_bottlerocket = "bottlerocket@1.54.0"

# 기본 인프라 Helm 차트 버전
karpenter_chart_version                    = "1.8.3"
aws_load_balancer_controller_chart_version = "1.17.0"
external_dns_chart_version                 = "1.19.0"
envoy_gateway_chart_version                = "1.7.1"

# LGTM 스택 Helm 차트 버전
mimir_chart_version                 = "6.0.5"
kube_prometheus_stack_chart_version = "82.10.1"
loki_chart_version                  = "6.20.0"
tempo_chart_version                 = "1.18.3"
fluent_bit_chart_version            = "0.56.0"

# Grafana
grafana_admin_password = "changeme" # 실제 배포 시 변경 필수
