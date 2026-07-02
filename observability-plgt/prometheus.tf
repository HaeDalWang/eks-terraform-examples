# ########################################################
# Prometheus (RW receiver + Thanos sidecar 조건부)
# ########################################################
#
# 메트릭 척추:
#   Alloy(clustered) --remote_write--> Prometheus (--web.enable-remote-write-receiver, TSDB)
#                                           └─ Thanos sidecar (enable_thanos) --> S3 thanos/
#
# Prometheus는 아무것도 스크레이핑하지 않습니다. 모든 스크레이핑은 Alloy가 수행합니다.
#

# Thanos sidecar가 사용할 objstore 설정 (S3 + SSE-KMS)
resource "kubernetes_secret_v1" "thanos_objstore_config" {
  count = var.enable_thanos ? 1 : 0

  metadata {
    name      = "thanos-objstore-config"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }

  data = {
    "objstore.yml" = yamlencode({
      type = "S3"
      config = {
        bucket   = aws_s3_bucket.observability.id
        endpoint = "s3.${data.aws_region.current.id}.amazonaws.com"
        region   = data.aws_region.current.id
        sse_config = {
          type       = "SSE-KMS"
          kms_key_id = aws_kms_key.observability.arn
        }
      }
      prefix = "thanos"
    })
  }
}

resource "helm_release" "prometheus" {
  name       = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus"
  version    = var.prometheus_chart_version
  namespace  = kubernetes_namespace_v1.monitoring.metadata[0].name

  values = concat(
    [file("${path.module}/helm-values/prometheus.yaml")],
    var.enable_thanos ? [
      templatefile("${path.module}/helm-values/prometheus-thanos.yaml", {
        thanos_image_tag  = var.thanos_image_tag
        prometheus_sa_arn = module.prometheus_pod_identity[0].iam_role_arn
      })
    ] : []
  )

  depends_on = [
    helm_release.karpenter,
    kubernetes_storage_class_v1.ebs_sc,
    kubernetes_secret_v1.thanos_objstore_config,
  ]
}
