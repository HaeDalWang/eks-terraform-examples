# AWS 지역 정보 불러오기
data "aws_region" "current" {}

# 현재 설정된 AWS 리전에 있는 가용영역 정보 불러오기
data "aws_availability_zones" "azs" {}

# 현재 Terraform을 실행하는 IAM 객체
data "aws_caller_identity" "current" {}

# AWS 파티션 정보 불러오기
data "aws_partition" "current" {}
# Route53 호스트존
data "aws_route53_zone" "this" {
  name = "${var.domain_name}."
}

########################################################
# 암호 정보가 저장된 Secrets
########################################################

# 다방면에서 사용되는 암호 정보
data "aws_secretsmanager_secret_version" "auth" {
  secret_id = "seungdo/auth"
}