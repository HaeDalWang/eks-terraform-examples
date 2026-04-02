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

# LGTM 스택 차트 버전
variable "mimir_chart_version" {
  description = "Grafana Mimir 차트 버전"
  type        = string
}

variable "kube_prometheus_stack_chart_version" {
  description = "Kube Prometheus Stack 차트 버전"
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

variable "fluent_bit_chart_version" {
  description = "Fluent Bit 차트 버전"
  type        = string
}

variable "grafana_admin_password" {
  description = "Grafana 관리자 비밀번호"
  type        = string
  sensitive   = true
}
