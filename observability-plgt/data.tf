data "aws_region" "current" {}
data "aws_availability_zones" "azs" {}
data "aws_caller_identity" "current" {}

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

# Route53 호스트존 (도메인 DNS 관리)
data "aws_route53_zone" "this" {
  name = "${var.domain_name}."
}

# 루트 도메인 ACM 인증서 (이미 발급된 것)
data "aws_acm_certificate" "existing" {
  domain   = local.domain_name
  statuses = ["ISSUED"]
}
