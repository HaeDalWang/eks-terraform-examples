# =============================================================================
# observability-plgt - Terraform 변수
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
envoy_gateway_chart_version                = "1.7.1"

# 관측성 스택 Helm 차트 버전
alloy_chart_version              = "1.10.0"
prometheus_chart_version         = "29.14.0"
kube_state_metrics_chart_version = "7.5.1"
loki_chart_version               = "7.0.0"
tempo_chart_version              = "1.24.4" # monolithic (그리고 tempo-distributed가 아닌 tempo 차트)
grafana_chart_version            = "10.5.15"

# Grafana
grafana_admin_password = "changeme" # 실제 배포 시 변경 필수

# Thanos (toggle, 기본 off)
# true로 켜면 Prometheus sidecar + Store Gateway + Query + Query Frontend + Compactor가
# 추가로 배포되고, Grafana 메트릭 datasource가 Thanos Query Frontend로 전환됩니다.
enable_thanos    = false
thanos_image_tag = "v0.41.0"
