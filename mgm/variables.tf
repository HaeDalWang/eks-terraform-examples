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

variable "eks_node_ami_id" {
  description = "EKS 노드 AMI ID"
  type        = string
}

variable "domain_name" {
  description = "Route53에 등록된 도메인 이름"
  type        = string
}

variable "alert_slack_channel" {
  description = "경보를 수신할 슬랙 채널"
  type        = string
}

variable "alert_slack_webhook_url" {
  description = "슬랙 메세지를 전송할 Webhook URL"
  type        = string
}

variable "karpenter_chart_version" {
  description = "Karpenter Helm 차트 버전"
  type        = string
}

variable "metrics_server_chart_version" {
  description = "Kubernetes Metrics Server Helm 차트 버전"
  type        = string
}

variable "external_dns_chart_version" {
  description = "Kubernetes ExternalDNS Helm 차트 버전"
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

variable "kubecost_chart_version" {
  description = "Kubecost Helm 차트 버전 "
  type        = string
}

variable "locust_chart_version" {
  description = "Locust Helm 차트 버전 "
  type        = string
}

variable "k8tz_chart_version" {
  description = "k8tz Helm 차트 버전 "
  type        = string
}

variable "keycloak_chart_version" {
  description = "Keycloak Helm 차트 버전 "
  type        = string
}

variable "kubernetes_event_exporter_chart_version" {
  description = "Kubernetes Event Exporter Helm 차트 버전 "
  type        = string
}

variable "argocd_slack_app_token" {
  description = "ArgoCD Notification에서 사용할 API 토큰"
  type        = string
}

variable "argocd_notification_slack_channel" {
  description = "ArgoCD Notification를 수신할 Slack 채널"
  type        = string
}