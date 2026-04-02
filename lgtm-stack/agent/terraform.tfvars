# =============================================================================
# LGTM Agent (워크로드 클러스터) - Terraform 변수
# =============================================================================

# 기존 EKS 클러스터 이름
eks_cluster_name = "my-workload-cluster"

# Central LGTM 엔드포인트 (central/ 배포 후 확인)
central_mimir_endpoint = "https://mimir.lgtm.example.com"
central_loki_endpoint  = "https://loki.lgtm.example.com"

# Helm 차트 버전 (central과 동일하게 유지 권장)
kube_prometheus_stack_chart_version = "82.10.1"
fluent_bit_chart_version            = "0.56.0"
