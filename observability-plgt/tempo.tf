# ########################################################
# Tempo (분산 추적 저장소, monolithic + metrics-generator)
# ########################################################
#
# metrics-generator가 트레이스로부터 span metrics/service graph를 계산해
# Prometheus RW receiver로 직접 remote_write 합니다 (Alloy 경유 없음).
#
resource "helm_release" "tempo" {
  name       = "tempo"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "tempo"
  version    = var.tempo_chart_version
  namespace  = kubernetes_namespace_v1.monitoring.metadata[0].name

  values = [
    templatefile("${path.module}/helm-values/tempo.yaml", {
      s3_bucket   = aws_s3_bucket.observability.id
      sa_arn      = module.tempo_pod_identity.iam_role_arn
      aws_region  = data.aws_region.current.id
      kms_key_arn = aws_kms_key.observability.arn
      namespace   = kubernetes_namespace_v1.monitoring.metadata[0].name
    })
  ]

  depends_on = [
    helm_release.prometheus,
    kubernetes_storage_class_v1.ebs_sc,
  ]
}
