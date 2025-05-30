variable "vpc_cidr" {
  description = "VPC 대역대"
  type        = string
}

variable "eks_cluster_version" {
  description = "EKS 클러스터 버전"
  type        = string
}

variable "eks_cluster_endpoint_public_access" {
  description = "EKS 엔드포인트에 대한 퍼블릭 접근 허가"
  default     = false
  type        = bool
}

variable "eks_node_ami_alias" {
  description = "EKS 노드 AMI 별칭"
  type        = string
}

variable "domain_name" {
  description = "Route53에 등록된 도메인 이름"
  type        = string
}

variable "karpenter_chart_version" {
  description = "Karpenter Helm 차트 버전"
  type        = string
}

# variable "external_dns_chart_version" {
#   description = "Kubernetes ExternalDNS Helm 차트 버전"
#   type        = string
# }

variable "aws_load_balancer_controller_chart_version" {
  description = "AWS Load Balancer Controller Helm 차트 버전"
  type        = string
}

variable "ingress_nginx_chart_version" {
  description = "Ingess-nginx Controller Helm 차트 버전 "
  type        = string
}

variable "argocd_chart_version" {
  description = "ArgoCD Helm 차트 버전 "
  type        = string
}

variable "kube_prometheus_stack_chart_version" {
  description = "Kube-prometheus-stack Helm 차트 버전 "
  type        = string
}

variable "thanos_chart_version" {
  description = "Thanos Helm 차트 버전 "
  type        = string
}

variable "k8tz_chart_version" {
  description = "k8tz Helm 차트 버전 "
  type        = string
}

variable "kong_chart_version" {
  description = "Kong Helm 차트 버전 "
  type        = string
}