# ########################################################
# Kube-Prometheus-Stack (Central)
# ########################################################
#
# 배포하는 것:
#   - Prometheus Operator (CRD 관리)
#   - Prometheus (메트릭 수집 → Mimir remote-write)
#   - Grafana (LGTM 통합 대시보드)
#   - node-exporter (노드 메트릭)
#   - kube-state-metrics (K8s 리소스 메트릭)
#   - PrometheusRules (알림 룰)
#
# 배포하지 않는 것:
#   - Alertmanager (Mimir Alertmanager 사용)
#

resource "helm_release" "prometheus" {
  name       = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = var.kube_prometheus_stack_chart_version
  namespace  = kubernetes_namespace_v1.monitoring.metadata[0].name

  values = [
    templatefile("${path.module}/helm-values/prometheus.yaml", {
      cluster_name           = module.eks.cluster_name
      grafana_admin_password = var.grafana_admin_password
    })
  ]

  depends_on = [
    helm_release.mimir,
    helm_release.loki,
    helm_release.tempo
  ]
}
