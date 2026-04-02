# 기존 EKS 클러스터 정보
variable "eks_cluster_name" {
  description = "기존 EKS 클러스터 이름"
  type        = string
}

# Istio 설정
variable "istio_chart_version" {
  description = "Istio Helm 차트 버전 (primary와 동일해야 함)"
  type        = string
}

variable "mesh_id" {
  description = "Istio Mesh ID (primary와 동일해야 함)"
  type        = string
  default     = "istio-mesh"
}

variable "cluster_name" {
  description = "Istio 멀티 클러스터에서 사용할 클러스터 이름"
  type        = string
  default     = "remote"
}

variable "network_name" {
  description = "Istio 네트워크 이름 (primary와 다른 네트워크)"
  type        = string
  default     = "network-2"
}

# Root CA (primary에서 출력된 값)
variable "root_ca_cert_pem" {
  description = "Root CA 인증서 (primary terraform output 값)"
  type        = string
  sensitive   = true
}

variable "root_ca_key_pem" {
  description = "Root CA 개인키 (primary terraform output 값)"
  type        = string
  sensitive   = true
}
