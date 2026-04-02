# ########################################################
# LGTM 중앙 저장소 (Mimir + Loki + Tempo)
# ########################################################
#
# 멀티 클러스터 데이터 흐름:
#
#   [central 클러스터 내부]
#   Prometheus → remote-write (cluster-internal) → Mimir
#   Fluent Bit → push (cluster-internal) → Loki
#   App OTLP  → push (cluster-internal) → Tempo
#
#   [agent 클러스터 → central]
#   Prometheus → remote-write (HTTPS) → Envoy Gateway → Mimir
#   Fluent Bit → push (HTTPS)         → Envoy Gateway → Loki
#   App OTLP  → push (HTTPS)          → Envoy Gateway → Tempo
#

resource "kubernetes_namespace_v1" "monitoring" {
  metadata {
    name = "monitoring"
  }
}

# ########################################################
# S3 버킷 (Mimir + Loki + Tempo 공용, prefix로 분리)
# ########################################################
resource "aws_s3_bucket" "observability" {
  bucket_prefix = "${local.project}-obs-"
  force_destroy = true
}

resource "aws_iam_policy" "observability_s3" {
  name = "${local.project}-observability-s3"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:PutObject"
        ]
        Resource = [
          aws_s3_bucket.observability.arn,
          "${aws_s3_bucket.observability.arn}/*"
        ]
      },
    ]
  })
}

# ########################################################
# Pod Identity: Mimir, Loki, Tempo
# ########################################################
module "mimir_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "2.6.0"
  name    = "mimir-pod-identity"
  additional_policy_arns = {
    s3 = aws_iam_policy.observability_s3.arn
  }
  associations = {
    mimir = {
      cluster_name    = module.eks.cluster_name
      namespace       = kubernetes_namespace_v1.monitoring.metadata[0].name
      service_account = "mimir"
    }
  }
}

module "loki_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "2.6.0"
  name    = "loki-pod-identity"
  additional_policy_arns = {
    s3 = aws_iam_policy.observability_s3.arn
  }
  associations = {
    loki = {
      cluster_name    = module.eks.cluster_name
      namespace       = kubernetes_namespace_v1.monitoring.metadata[0].name
      service_account = "loki"
    }
  }
}

module "tempo_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "2.6.0"
  name    = "tempo-pod-identity"
  additional_policy_arns = {
    s3 = aws_iam_policy.observability_s3.arn
  }
  associations = {
    tempo = {
      cluster_name    = module.eks.cluster_name
      namespace       = kubernetes_namespace_v1.monitoring.metadata[0].name
      service_account = "tempo"
    }
  }
}

# ########################################################
# Mimir (메트릭 장기 저장소)
# ########################################################
resource "helm_release" "mimir" {
  name       = "mimir"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "mimir-distributed"
  version    = var.mimir_chart_version
  namespace  = kubernetes_namespace_v1.monitoring.metadata[0].name

  values = [
    templatefile("${path.module}/helm-values/mimir.yaml", {
      s3_bucket  = aws_s3_bucket.observability.id
      sa_arn     = module.mimir_pod_identity.iam_role_arn
      aws_region = data.aws_region.current.id
    })
  ]

  depends_on = [
    helm_release.karpenter,
    kubernetes_storage_class_v1.ebs_sc
  ]
}

# ########################################################
# Loki (로그 저장소)
# ########################################################
resource "helm_release" "loki" {
  name       = "loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  version    = var.loki_chart_version
  namespace  = kubernetes_namespace_v1.monitoring.metadata[0].name

  values = [
    templatefile("${path.module}/helm-values/loki.yaml", {
      s3_bucket  = aws_s3_bucket.observability.id
      sa_arn     = module.loki_pod_identity.iam_role_arn
      aws_region = data.aws_region.current.id
    })
  ]

  depends_on = [helm_release.mimir]
}

# ########################################################
# Tempo (분산 추적 저장소)
# ########################################################
resource "helm_release" "tempo" {
  name       = "tempo"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "tempo-distributed"
  version    = var.tempo_chart_version
  namespace  = kubernetes_namespace_v1.monitoring.metadata[0].name

  values = [
    templatefile("${path.module}/helm-values/tempo.yaml", {
      s3_bucket  = aws_s3_bucket.observability.id
      sa_arn     = module.tempo_pod_identity.iam_role_arn
      aws_region = data.aws_region.current.id
    })
  ]

  depends_on = [helm_release.mimir]
}
