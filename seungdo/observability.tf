########################################################
# LGTM (Loki,Grafana,Tempo,Mimir) + OpenTelemetry
########################################################

locals {
  slack_channel = "noti-alertmanager"
}

# Monitoring 스택을 설치할 네임스페이스
resource "kubernetes_namespace_v1" "monitoring" {
  metadata {
    name = "monitoring"
  }
}

# Mimir가 저장할 버킷
resource "aws_s3_bucket" "mimir" {
  bucket_prefix = "${local.project}-mimir-storage-"

  force_destroy = true
}
# 위에서 생성한 버킷에 대한 접근 설정
resource "aws_iam_policy" "mimir_s3_access" {
  name = "mimir-s3-access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:PutObject"
        ]
        Effect = "Allow"
        Resource = [
          aws_s3_bucket.mimir.arn,
          "${aws_s3_bucket.mimir.arn}/*"
        ]
      },
    ]
  })
}

module "mimir_pod_identity" {
  source          = "terraform-aws-modules/eks-pod-identity/aws"
  version         = "2.6.0"
  name            = "custom-pod-identity"
  
  additional_policy_arns = {
    mimir = aws_iam_policy.mimir_s3_access.arn
  }

  associations = {
    mimir = {
      cluster_name    = module.eks.cluster_name
      namespace       = kubernetes_namespace_v1.monitoring.metadata[0].name
      service_account = "mimir"
    }
  }
}


# Mimir
# https://grafana.com/docs/helm-charts/mimir-distributed/latest/run-production-environment-with-helm/#plan-capacity
resource "helm_release" "mimir" {
  name       = "mimir"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "mimir-distributed"
  version    = var.mimir_chart_version
  namespace  = kubernetes_namespace_v1.monitoring.metadata[0].name

  values = [
    templatefile("${path.module}/helm-values/mimir.yaml", {
      mimir_s3_bucket = aws_s3_bucket.mimir.id,
      mimir_sa_arn  = module.mimir_pod_identity.iam_role_arn
    })
  ]

  depends_on = [
    helm_release.ingress_nginx
  ]
}

# Kube-prometheus-stack
resource "helm_release" "prometheus" {
  name       = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = var.kube_prometheus_stack_chart_version
  namespace  = kubernetes_namespace_v1.monitoring.metadata[0].name

  values = [
    templatefile("${path.module}/helm-values/prometheus.yaml", {
      cluster_name                      = module.eks.cluster_name
      grafana_hostname                  = "grafana.${local.project_domain_name}"
      prometheus_hostname               = "prometheus.${local.project_domain_name}"
      grafana_admin_password            = jsondecode(data.aws_secretsmanager_secret_version.auth.secret_string)["basicauth"]["password"]
    })
  ]
  depends_on = [
    helm_release.ingress_nginx
  ]
}

      # alertmanager_hostname             = "alertmanager.${local.project_domain_name}"
      # slack_channel                     = local.slack_channel
      # slack_webhook_url                 = jsondecode(data.aws_secretsmanager_secret_version.auth.secret_string)["slack"]["webhook_url"]
      # alertmanager_password_secret_name = kubernetes_secret.alertmanager.metadata[0].name




# # Fluent Bit 네임스페이스
# resource "kubernetes_namespace_v1" "fluent_bit" {
#   metadata {
#     name = "fluent-bit"
#   }
# }

# # Fluent Bit
# resource "helm_release" "fluent_bit" {
#   name       = "fluent-bit"
#   repository = "https://fluent.github.io/helm-charts"
#   chart      = "fluent-bit"
#   version    = var.fluent_bit_chart_version
#   namespace  = kubernetes_namespace_v1.fluent_bit.metadata[0].name

#   values = [
#     templatefile("${path.module}/helm-values/fluent-bit.yaml", {})
#   ]

#   depends_on = [
#     helm_release.opensearch
#   ]
# }