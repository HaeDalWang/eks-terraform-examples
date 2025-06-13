# AWS 지역 정보 불러오기
data "aws_region" "current" {}

# 현재 설정된 AWS 리전에 있는 가용영역 정보 불러오기
data "aws_availability_zones" "azs" {}

# 현재 Terraform을 실행하는 IAM 객체
data "aws_caller_identity" "current" {}

# Route53 호스트존
data "aws_route53_zone" "this" {
  name = "${var.domain_name}."
}

# EKS 클러스터 인증 토큰
data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

# # 암호 정보가 저장된 Secrets
# # 이미 local.project의 시크릿이름으로 관련 정보가 저장되어 있어야합니다
# data "aws_secretsmanager_secret_version" "this" {
#   secret_id = local.project
# }

# # Helm 차트를 통해서 생성된 Keycloak의 Ingress 객체 정보 불러오기
# data "kubernetes_ingress_v1" "keycloak" {
#   metadata {
#     name      = helm_release.keycloak.name
#     namespace = kubernetes_namespace.keycloak.metadata[0].name
#   }
# }