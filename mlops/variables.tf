variable "vpc_cidr" {
  description = "VPC 대역대"
  type        = string
}

variable "github_token" {
  description = "GitHub Personal Access Token for ArgoCD"
  type        = string
  sensitive   = true
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

variable "eks_node_ami_alias_al2023" {
  description = "EKS 노드 AMI 별칭 (al2023)"
  type        = string
}
variable "eks_node_ami_alias_bottlerocket" {
  description = "EKS 노드 AMI 별칭 (bottlerocket)"
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

variable "argocd_slack_app_token" {
  description = "ArgoCD Slack App Token"
  type        = string
}

variable "argocd_notification_slack_channel" {
  description = "ArgoCD Notification Slack Channel"
  type        = string
}

variable "reloader_chart_version" {
  description = "Reloader Helm 차트 버전"
  type        = string
}

variable "secrets_store_csi_driver_provider_aws_chart_version" {
  description = "Secrets Store CSI Driver Provider AWS Helm 차트 버전"
  type        = string
}

variable "secrets_store_csi_driver_chart_version" {
  description = "Secrets Store CSI Driver Helm 차트 버전"
  type        = string
}

variable "argo_rollouts_chart_version" {
  description = "Argo Rollouts Helm 차트 버전"
  type        = string
}

variable "keda_chart_version" {
  description = "KEDA Helm 차트 버전"
  type        = string
}

variable "kubeflow_chart_version" {
  description = "Kubeflow Helm 차트 버전"
  type        = string
}

variable "slack_webhook_url" {
  description = "Slack webhook URL for backup notifications"
  type        = string
  default     = ""
  sensitive   = true
}