# n8n
# ref: https://artifacthub.io/packages/helm/community-charts/n8n

resource "kubernetes_namespace_v1" "n8n" {
  metadata {
    name = "n8n"
  }
}

# # IRSA
# module "n8n_irsa" {
#   source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
#   version = "6.2.3"

#   name = "n8n-irsa"

#   policies = {
#     # bedrock 사용 시 필요한 정책
#     bedrock = "arn:aws:iam::aws:policy/AmazonBedrockFullAccess"
#   }

#   oidc_providers = {
#     n8n = {
#       provider_arn = module.eks.oidc_provider_arn
#       namespace_service_accounts = [
#         "n8n:n8n"
#       ]
#     }
#   }
# }

# n8n
# ref: https://artifacthub.io/packages/helm/community-charts/n8n
resource "helm_release" "n8n" {
  name       = "n8n"
  repository = "https://community-charts.github.io/helm-charts"
  chart      = "n8n"
  version    = "1.16.26"
  namespace  = kubernetes_namespace_v1.n8n.metadata[0].name

  values = [
    templatefile("${path.module}/helm-values/n8n.yaml", {
      domain              = "${local.project_domain_name}"
      n8n_encryption_key  = jsondecode(data.aws_secretsmanager_secret_version.auth.secret_string)["basicauth"]["password"]
      postgresql_password = jsondecode(data.aws_secretsmanager_secret_version.auth.secret_string)["basicauth"]["password"]
    })
  ]

  timeout = 600
  wait    = false

  # templatefile()+secret 조합으로 values가 매 plan마다 state와 다르게 인식되는 drift 방지. n8n values 실제 변경 시엔 잠시 이 블록에서 values 제거 후 apply
  lifecycle {
    ignore_changes = [metadata, values]
  }
}