# ########################################################
# Loki (로그 저장소, SimpleScalable/SSD)
# ########################################################
resource "helm_release" "loki" {
  name       = "loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  version    = var.loki_chart_version
  namespace  = kubernetes_namespace_v1.monitoring.metadata[0].name

  values = [
    templatefile("${path.module}/helm-values/loki.yaml", {
      s3_bucket   = aws_s3_bucket.observability.id
      sa_arn      = module.loki_pod_identity.iam_role_arn
      aws_region  = data.aws_region.current.id
      kms_key_arn = aws_kms_key.observability.arn
    })
  ]

  depends_on = [
    helm_release.karpenter,
    kubernetes_storage_class_v1.ebs_sc,
  ]
}
