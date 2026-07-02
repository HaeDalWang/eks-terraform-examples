# ########################################################
# 관측성 저장소 (S3 + KMS + Pod Identity)
# ########################################################
#
# 데이터 흐름:
#
#   Alloy(metrics, clustered)  --remote_write--> Prometheus (RW receiver, TSDB)
#                                                     └─ Thanos sidecar (enable_thanos) --> S3 thanos/
#   Alloy(logs, DaemonSet)     --push-->          Loki (SSD)                            --> S3 loki/
#   Alloy(receiver, OTLP)      --push-->          Tempo (monolithic)                    --> S3 tempo/
#
# S3 버킷은 loki/tempo가 항상 사용하고, thanos/ prefix는 enable_thanos = true일 때만 사용됩니다.
#

resource "kubernetes_namespace_v1" "monitoring" {
  metadata {
    name = "monitoring"
  }
}

# ########################################################
# S3 버킷 (Loki + Tempo + Thanos 공용, prefix로 분리)
# ########################################################
resource "aws_kms_key" "observability" {
  description             = "${local.project}-observability S3 SSE-KMS"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_kms_alias" "observability" {
  name          = "alias/${local.project}-observability"
  target_key_id = aws_kms_key.observability.key_id
}

resource "aws_s3_bucket" "observability" {
  bucket_prefix = "${local.project}-obs-"
  force_destroy = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "observability" {
  bucket = aws_s3_bucket.observability.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.observability.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_versioning" "observability" {
  bucket = aws_s3_bucket.observability.id
  versioning_configuration {
    status = "Enabled"
  }
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
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = [aws_kms_key.observability.arn]
      },
    ]
  })
}

# ########################################################
# Pod Identity: Loki, Tempo, Thanos(조건부)
# ########################################################
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

module "thanos_pod_identity" {
  count   = var.enable_thanos ? 1 : 0
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "2.6.0"
  name    = "thanos-pod-identity"
  additional_policy_arns = {
    s3 = aws_iam_policy.observability_s3.arn
  }
  associations = {
    thanos = {
      cluster_name    = module.eks.cluster_name
      namespace       = kubernetes_namespace_v1.monitoring.metadata[0].name
      service_account = "thanos"
    }
  }
}

module "prometheus_pod_identity" {
  count   = var.enable_thanos ? 1 : 0
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "2.6.0"
  name    = "prometheus-pod-identity"
  additional_policy_arns = {
    s3 = aws_iam_policy.observability_s3.arn
  }
  associations = {
    # Thanos sidecar가 Prometheus 컨테이너에 붙어서 S3 업로드를 수행하므로
    # Prometheus 서비스 어카운트에 S3 권한 부여
    prometheus = {
      cluster_name    = module.eks.cluster_name
      namespace       = kubernetes_namespace_v1.monitoring.metadata[0].name
      service_account = "prometheus-server"
    }
  }
}
