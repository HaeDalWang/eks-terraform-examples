# ########################################################
# Grafana (단독 배포, 조건부 metrics datasource)
# ########################################################
resource "helm_release" "grafana" {
  name       = "grafana"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "grafana"
  version    = var.grafana_chart_version
  namespace  = kubernetes_namespace_v1.monitoring.metadata[0].name

  values = [
    templatefile("${path.module}/helm-values/grafana.yaml", {
      grafana_admin_password = var.grafana_admin_password
      metrics_query_service  = local.metrics_query_service
      namespace              = kubernetes_namespace_v1.monitoring.metadata[0].name
    })
  ]

  depends_on = [
    helm_release.prometheus,
    helm_release.loki,
    helm_release.tempo,
    kubernetes_deployment_v1.thanos_query_frontend,
  ]
}
