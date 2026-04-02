# ########################################################
# Fluent Bit (로그 수집 → Loki)
# ########################################################
resource "kubernetes_namespace_v1" "fluent_bit" {
  metadata {
    name = "fluent-bit"
  }
}

resource "helm_release" "fluent_bit" {
  name       = "fluent-bit"
  repository = "https://fluent.github.io/helm-charts"
  chart      = "fluent-bit"
  version    = var.fluent_bit_chart_version
  namespace  = kubernetes_namespace_v1.fluent_bit.metadata[0].name

  values = [
    file("${path.module}/helm-values/fluent-bit.yaml")
  ]

  depends_on = [helm_release.loki]
}
