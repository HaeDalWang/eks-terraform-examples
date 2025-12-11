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

variable "cilium_chart_version" {
  description = "Cilium 차트 버전"
  type        = string
}

variable "eks_node_ami_alias_al2023" {
  description = "EKS 노드 AMI 별칭 (Amazon Linux 2023)"
  type        = string
}

variable "eks_node_ami_alias_bottlerocket" {
  description = "EKS 노드 AMI 별칭 (Bottlerocket)"
  type        = string
}

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

variable "ingress_nginx_chart_version" {
  description = "Ingress NGINX 차트 버전"
  type        = string
}

variable "opensearch_chart_version" {
  description = "OpenSearch 차트 버전"
  type        = string
}

variable "argocd_chart_version" {
  description = "Argo CD 차트 버전"
  type        = string
}

variable "psmdb-operator_chart_version" {
  description = "Percona Server for MongoDB Operator 차트 버전"
  type        = string
}

variable "kube_prometheus_stack_chart_version" {
  description = "Kube Prometheus Stack 차트 버전"
  type        = string
}

variable "thanos_chart_version" {
  description = "Thanos 차트 버전"
  type        = string
}

variable "pg-operator_chart_version" {
  description = "Percona Server for PostgreSQL Operator 차트 버전"
  type        = string
}

variable "nginx_gateway_fabric_chart_version" {
  description = "NGINX Gateway Fabric 차트 버전"
  type        = string
}

variable "traefik_chart_version" {
  description = "Traefik 차트 버전"
  type        = string
}