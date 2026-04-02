# ########################################################
# Fluent Bit (로그 수집 → Central Loki via HTTPS)
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
    templatefile("${path.module}/helm-values/fluent-bit.yaml", {
      central_loki_host = replace(replace(var.central_loki_endpoint, "https://", ""), "http://", "")
    })
  ]

  depends_on = [helm_release.prometheus]
}
