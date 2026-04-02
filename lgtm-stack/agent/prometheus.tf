# ########################################################
# Kube-Prometheus-Stack (Agent 클러스터)
# ########################################################
#
# 배포하는 것:
#   - Prometheus Operator
#   - Prometheus (메트릭 수집 → Central Mimir remote-write via HTTPS)
#   - node-exporter
#   - kube-state-metrics
#   - PrometheusRules (로컬 평가 → Central Mimir Alertmanager로 alert 전송)
#
# 배포하지 않는 것:
#   - Grafana (Central에서만 조회)
#   - Alertmanager (Central Mimir Alertmanager 사용)
#

resource "kubernetes_namespace_v1" "monitoring" {
  metadata {
    name = "monitoring"
  }
}

resource "helm_release" "prometheus" {
  name       = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = var.kube_prometheus_stack_chart_version
  namespace  = kubernetes_namespace_v1.monitoring.metadata[0].name

  values = [
    templatefile("${path.module}/helm-values/prometheus.yaml", {
      cluster_name           = var.eks_cluster_name
      central_mimir_endpoint = var.central_mimir_endpoint
    })
  ]
}
