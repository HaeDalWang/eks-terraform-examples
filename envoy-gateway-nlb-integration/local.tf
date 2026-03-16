# AWS 지역 정보 불러오기
data "aws_region" "current" {}
# 현재 설정된 AWS 리전에 있는 가용영역 정보 불러오기
data "aws_availability_zones" "azs" {}
# 현재 Terraform을 실행하는 IAM 객체
data "aws_caller_identity" "current" {}
# AWS 파티션 정보 불러오기
data "aws_partition" "current" {}
# EKS 클러스터 인증 토큰
data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}
# Route53 호스트존
data "aws_route53_zone" "this" {
  name = "${var.domain_name}."
}

# 로컬 환경변수 지정
locals {
  project             = "seungdo"
  project_prefix      = "sd"
  domain_name         = var.domain_name                                # 클러스터에 기반이 되는 루트 도메인
  project_domain_name = "${local.project_prefix}.${local.domain_name}" # 프로젝트에서만 사용하는 도메인
  tags = {                                                             # 모든 리소스에 적용되는 전역 태그
    "terraform" = "true"
    "project"   = local.project
  }
}