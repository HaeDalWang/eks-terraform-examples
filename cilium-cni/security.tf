########################################################
# ACM Certificate for Project Domain
########################################################
# ACM에 존재하는 루트 도메인 인증서 불러오기
data "aws_acm_certificate" "existing" {
  domain   = local.domain_name
  statuses = ["ISSUED"]
}

# 프로젝트에서만 사용하는 ACM 인증서 발급 요청
resource "aws_acm_certificate" "project" {
  domain_name       = "*.${local.project_domain_name}"
  validation_method = "DNS"
  lifecycle {
    create_before_destroy = true
  }
}
# 위에서 생성한 ACM 인증서 검증하는 DNS 레코드 생성
resource "aws_route53_record" "acm_validation_project_domain" {
  for_each = {
    for dvo in aws_acm_certificate.project.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }
  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.this.zone_id
}
# 인증서 발급 상태
resource "aws_acm_certificate_validation" "project" {
  certificate_arn         = aws_acm_certificate.project.arn
  validation_record_fqdns = [for record in aws_route53_record.acm_validation_project_domain : record.fqdn]
}

########################################################
# GitHub Actions OIDC Provider and Role
########################################################
# GitHub Actions OIDC Provider (존재하는 것을 참조)
# data "aws_iam_openid_connect_provider" "github" {
#   url = "https://token.actions.githubusercontent.com"
# }

# # GitHub Actions용 IAM 역할 (Helm 차트 배포용)
# resource "aws_iam_role" "github_actions_helm" {
#   name = "github-actions-helm-publisher"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect = "Allow"
#         Principal = {
#           Federated = data.aws_iam_openid_connect_provider.github.arn
#         }
#         Action = "sts:AssumeRoleWithWebIdentity"
#         Condition = {
#           StringEquals = {
#             "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
#           }
#           StringLike = {
#             # co-tong org의 모든 리포지토리에서 사용 가능
#             "token.actions.githubusercontent.com:sub" = "repo:co-tong/*:*"
#           }
#         }
#       }
#     ]
#   })
# }
# # ECR 접근 권한
# resource "aws_iam_role_policy" "github_actions_helm_ecr" {
#   name = "ecr-push-policy"
#   role = aws_iam_role.github_actions_helm.id

#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       # ECR 인증 토큰 가져오기
#       {
#         Effect = "Allow"
#         Action = [
#           "ecr:GetAuthorizationToken"
#         ]
#         Resource = "*"
#       },
#       # ECR에 이미지/차트 푸시 (모든 리포지토리 허용)
#       {
#         Effect = "Allow"
#         Action = [
#           "ecr:BatchCheckLayerAvailability",
#           "ecr:GetDownloadUrlForLayer",
#           "ecr:BatchGetImage",
#           "ecr:PutImage",
#           "ecr:InitiateLayerUpload",
#           "ecr:UploadLayerPart",
#           "ecr:CompleteLayerUpload",
#           "ecr:DescribeRepositories",
#           "ecr:DescribeImages",
#           "ecr:ListImages"
#         ]
#         Resource = "arn:aws:ecr:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:repository/*"
#       }
#     ]
#   })
# }

########################################################
# EKS AccessEntry
########################################################
locals {
  eks_admin_iam_roles = [
    "youngwoojung"
  ]
}
# EKS 클러스터 접근 제어
resource "aws_eks_access_entry" "cluster_admin" {
  for_each = toset(local.eks_admin_iam_roles)

  cluster_name  = module.eks.cluster_name
  principal_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${each.key}"
}
resource "aws_eks_access_policy_association" "cluster_admin" {
  for_each = toset(local.eks_admin_iam_roles)

  cluster_name  = module.eks.cluster_name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  principal_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${each.key}"

  access_scope {
    type = "cluster"
  }
}

########################################################
# Self-signed Certificate for Joint Domain (*.seungdobae.com)
########################################################
# Traefik 등에서 사용할 공통 와일드카드 인증서 생성
# 1년짜리 자체 서명 인증서

# 개인키 생성
resource "tls_private_key" "joint_domain" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# 자체 서명 인증서 생성 (1년 유효기간)
resource "tls_self_signed_cert" "joint_domain" {
  private_key_pem = tls_private_key.joint_domain.private_key_pem

  subject {
    common_name  = "*.seungdobae.com"
    organization = "Self-Signed"
  }

  validity_period_hours = 8760 # 1년 (365일 * 24시간)

  # 와일드카드 도메인 지원
  dns_names = [
    "*.seungdobae.com",
    "seungdobae.com"
  ]

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

# Kubernetes TLS Secret 생성 (Traefik 네임스페이스)
resource "kubernetes_secret_v1" "joint_domain_secret" {
  metadata {
    name      = "joint-domain-secret"
    namespace = "traefik"
  }

  type = "kubernetes.io/tls"

  data = {
    "tls.crt" = tls_self_signed_cert.joint_domain.cert_pem
    "tls.key" = tls_private_key.joint_domain.private_key_pem
  }
}