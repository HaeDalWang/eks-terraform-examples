# 기존 EKS 클러스터 정보
variable "eks_cluster_name" {
  description = "기존 EKS 클러스터 이름"
  type        = string
}

# Central LGTM 엔드포인트 (HTTPS)
variable "central_mimir_endpoint" {
  description = "Central Mimir remote-write 엔드포인트 (예: https://mimir.lgtm.example.com)"
  type        = string
}

variable "central_loki_endpoint" {
  description = "Central Loki 로그 push 엔드포인트 (예: https://loki.lgtm.example.com)"
  type        = string
}

# Helm 차트 버전
variable "kube_prometheus_stack_chart_version" {
  description = "Kube Prometheus Stack 차트 버전"
  type        = string
}

variable "fluent_bit_chart_version" {
  description = "Fluent Bit 차트 버전"
  type        = string
}
