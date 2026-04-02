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

# Istio
variable "istio_chart_version" {
  description = "Istio Helm 차트 버전"
  type        = string
}

variable "mesh_id" {
  description = "Istio Mesh ID (모든 클러스터에서 동일해야 함)"
  type        = string
  default     = "istio-mesh"
}

variable "cluster_name" {
  description = "Istio 멀티 클러스터에서 사용할 클러스터 이름"
  type        = string
  default     = "primary"
}

variable "network_name" {
  description = "Istio 네트워크 이름 (클러스터별 다른 네트워크)"
  type        = string
  default     = "network-1"
}
