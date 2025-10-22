# =============================================================================
# Linkerd mTLS 인증서 관리 - AWS Secrets Manager 방식
# =============================================================================
# 
# 인증서는 별도로 생성하여 회사 비밀저장소에 백업 후 AWS Secrets Manager에 등록됨
# Terraform에서는 Secrets Manager에서 인증서를 읽어와서 사용
# 
# 인증서 생성 방법:
# 1. 자동 스크립트 사용 (권장):
#    ./scripts/linkerd-cert-create.sh
#    - 모든 인증서를 자동으로 생성하고 AWS Secrets Manager 등록용 JSON 생성
#    - 회사 비밀저장소 백업 후 AWS Secrets Manager에 등록
# 2. 수동 OpenSSL 생성:
#    - Trust Anchor: openssl req -x509 -newkey rsa:4096 -keyout ca-key.pem -out ca-cert.pem -days 365 -nodes -subj "/CN=identity.linkerd.cluster.local"
#    - Issuer: openssl genrsa -out issuer-key.pem 4096 && openssl req -new -key issuer-key.pem -out issuer.csr -subj "/CN=identity.linkerd.cluster.local"
#    - 서명: openssl x509 -req -in issuer.csr -CA ca-cert.pem -CAkey ca-key.pem -CAcreateserial -out issuer-cert.pem -days 365
# 3. Linkerd CLI: linkerd install --identity-external-issuer=false
# 
# AWS Secrets Manager 등록 형식:
# {
#   "trust_anchor": {
#     "crt": "-----BEGIN CERTIFICATE-----...",
#     "key": "-----BEGIN PRIVATE KEY-----..."
#   },
#   "issuer": {
#     "crt": "-----BEGIN CERTIFICATE-----...", 
#     "key": "-----BEGIN PRIVATE KEY-----..."
#   }
# }
# =============================================================================
# AWS Secrets Manager에서 기존 Linkerd 인증서 읽기
# 주의: 이 data source는 위의 secret이 이미 존재해야 함
data "aws_secretsmanager_secret_version" "linkerd_certificates" {
  secret_id = "linkerd/certificates"
}

# 인증서 데이터 파싱 및 로컬 변수로 저장
locals {
  # JSON 형태의 인증서 데이터를 파싱 (개행 문자 처리)
  linkerd_certs = jsondecode(data.aws_secretsmanager_secret_version.linkerd_certificates.secret_string)
  
  # 개별 인증서 접근을 위한 편의 변수들 (개행 문자 복원)
  trust_anchor_crt = local.linkerd_certs.trust_anchor.crt
  trust_anchor_key = local.linkerd_certs.trust_anchor.key
  issuer_crt       = local.linkerd_certs.issuer.crt
  issuer_key       = local.linkerd_certs.issuer.key
}

# =============================================================================
# IAM 역할 및 정책 - AWS Secrets Manager 접근용
# =============================================================================

# # EKS Pod Identity로 Secrets Manager 접근을 위한 IAM 역할
# resource "aws_iam_role" "linkerd_secrets_access" {
#   name = "${local.project}-linkerd-secrets-access"
  
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Effect = "Allow"
#       Principal = {
#         Service = "pods.eks.amazonaws.com"
#       }
#       Action = "sts:AssumeRole"
#       Condition = {
#         StringEquals = {
#           "eks:cluster-name" = module.eks.cluster_name
#           "eks:namespace"    = "kube-system"
#         }
#       }
#     }]
#   })
  
#   tags = merge(local.tags, {
#     Name        = "Linkerd Secrets Access Role"
#     Purpose     = "EKS Pod Identity for Secrets Manager"
#     Service     = "Linkerd"
#   })
# }

# # Secrets Manager 접근을 위한 IAM 정책
# resource "aws_iam_role_policy" "linkerd_secrets_access" {
#   name = "${local.project}-linkerd-secrets-access"
#   role = aws_iam_role.linkerd_secrets_access.id
  
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Effect = "Allow"
#       Action = [
#         "secretsmanager:GetSecretValue",
#         "secretsmanager:DescribeSecret"
#       ]
#       Resource = aws_secretsmanager_secret.linkerd_certificates.arn
#     }]
#   })
# }

# # =============================================================================
# # EKS Pod Identity 및 Kubernetes 리소스
# # =============================================================================

# # EKS Pod Identity Association - Linkerd installer가 Secrets Manager 접근 가능하도록
# resource "aws_eks_pod_identity_association" "linkerd_installer" {
#   cluster_name    = module.eks.cluster_name
#   namespace       = "kube-system"
#   service_account = "linkerd-installer"
  
#   role_arn = aws_iam_role.linkerd_secrets_access.arn
  
#   tags = merge(local.tags, {
#     Name        = "Linkerd Installer Pod Identity"
#     Purpose     = "EKS Pod Identity for Linkerd"
#     Service     = "Linkerd"
#   })
# }

# # Linkerd installer용 ServiceAccount 생성
# # 이 ServiceAccount는 EKS Pod Identity를 통해 Secrets Manager 접근 권한을 가짐
# resource "kubernetes_service_account_v1" "linkerd_installer" {
#   metadata {
#     name      = "linkerd-installer"
#     namespace = "kube-system"
#     annotations = {
#       "eks.amazonaws.com/role-arn" = aws_iam_role.linkerd_secrets_access.arn
#     }
#     labels = {
#       "app.kubernetes.io/name"     = "linkerd-installer"
#       "app.kubernetes.io/component" = "installer"
#     }
#   }
  
#   depends_on = [
#     aws_eks_pod_identity_association.linkerd_installer
#   ]
# }

# =============================================================================
# 사용 방법 및 주의사항
# =============================================================================
#
# 1. 인증서 생성 및 등록:
#    - 자동 스크립트 실행: ./scripts/linkerd-cert-create.sh
#    - 회사 비밀저장소에 백업 (스크립트에서 안내)
#    - AWS Secrets Manager에 JSON 형태로 등록 (스크립트에서 생성된 linkerd-certs.json 사용)
#
# 2. Terraform 적용:
#    - terraform plan으로 리소스 확인
#    - terraform apply로 리소스 생성
#
# 3. Linkerd 설치:
#    - kube-apps.tf에서 Helm 차트로 Linkerd 설치
#    - 인증서는 local.trust_anchor_crt, local.issuer_crt 등으로 접근 가능
#
# 4. 보안:
#    - Terraform state 파일에 민감한 정보 저장 안됨
#    - 회사 비밀저장소에서 안전하게 백업 관리
#    - EKS Pod Identity로 안전한 Secrets Manager 접근
# =============================================================================
