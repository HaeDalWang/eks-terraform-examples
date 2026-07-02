variable "domain_name" {
  description = "도메인 이름"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
}

variable "eks_cluster_version" {
  description = "EKS 클러스터 버전"
  type        = string
}

variable "eks_node_ami_alias_bottlerocket" {
  description = "EKS 노드 AMI 별칭 (Bottlerocket)"
  type        = string
}

# 기본 인프라 Helm 차트 버전
variable "karpenter_chart_version" {
  description = "Karpenter 차트 버전"
  type        = string
}

variable "aws_load_balancer_controller_chart_version" {
  description = "AWS Load Balancer Controller 차트 버전"
  type        = string
}

variable "external_dns_chart_version" {
  description = "External DNS 차트 버전"
  type        = string
}

variable "envoy_gateway_chart_version" {
  description = "Envoy Gateway 차트 버전"
  type        = string
}

# 관측성 스택 차트 버전
variable "alloy_chart_version" {
  description = "Grafana Alloy 차트 버전"
  type        = string
}

variable "prometheus_chart_version" {
  description = "Prometheus 차트 버전 (prometheus-community/prometheus)"
  type        = string
}

variable "kube_state_metrics_chart_version" {
  description = "kube-state-metrics 차트 버전"
  type        = string
}

variable "loki_chart_version" {
  description = "Grafana Loki 차트 버전"
  type        = string
}

variable "tempo_chart_version" {
  description = "Grafana Tempo 차트 버전"
  type        = string
}

variable "grafana_chart_version" {
  description = "Grafana 차트 버전 (grafana/grafana, 단독 배포)"
  type        = string
}

variable "grafana_admin_password" {
  description = "Grafana 관리자 비밀번호"
  type        = string
  sensitive   = true
}

# Thanos (toggle)
variable "enable_thanos" {
  description = "Thanos 장기 저장소 활성화 여부. false면 Prometheus 로컬 TSDB만 사용"
  type        = bool
  default     = false
}

variable "thanos_image_tag" {
  description = "Thanos 컨테이너 이미지 태그 (quay.io/thanos/thanos)"
  type        = string
}
