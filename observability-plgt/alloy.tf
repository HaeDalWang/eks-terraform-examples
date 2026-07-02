# ########################################################
# Alloy: 수집 소프트웨어 통일 (Node Exporter / Promtail / Fluent Bit / OTel Collector 미사용)
# ########################################################
#
# alloy-logs      DaemonSet             노드 로컬 Pod 로그 tailing + node-exporter → Loki / Prometheus
# alloy-metrics   Deployment(clustered) Pod annotation + kube-state-metrics 스크레이핑 → Prometheus RW
# alloy-receiver  Deployment            OTLP(gRPC 4317/HTTP 4318) 수신 → Prometheus/Loki/Tempo 분배
#

resource "helm_release" "kube_state_metrics" {
  name       = "kube-state-metrics"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-state-metrics"
  version    = var.kube_state_metrics_chart_version
  namespace  = kubernetes_namespace_v1.monitoring.metadata[0].name

  depends_on = [helm_release.karpenter, kubernetes_namespace_v1.monitoring]
}

resource "helm_release" "alloy_logs" {
  name       = "alloy-logs"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "alloy"
  version    = var.alloy_chart_version
  namespace  = kubernetes_namespace_v1.monitoring.metadata[0].name

  values = [
    <<-EOT
    alloy:
      configMap:
        content: |
          ${indent(6, file("${path.module}/helm-values/alloy-logs.alloy"))}
      mounts:
        varlog: true
        dockercontainers: true
    controller:
      type: daemonset
      resources:
        requests:
          cpu: 50m
          memory: 128Mi
        limits:
          memory: 256Mi
    EOT
  ]

  depends_on = [helm_release.prometheus, helm_release.loki]
}

resource "helm_release" "alloy_metrics" {
  name       = "alloy-metrics"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "alloy"
  version    = var.alloy_chart_version
  namespace  = kubernetes_namespace_v1.monitoring.metadata[0].name

  values = [
    <<-EOT
    alloy:
      configMap:
        content: |
          ${indent(6, file("${path.module}/helm-values/alloy-metrics.alloy"))}
      clustering:
        enabled: true
    controller:
      type: deployment
      replicas: 2
      resources:
        requests:
          cpu: 100m
          memory: 128Mi
        limits:
          memory: 256Mi
    EOT
  ]

  depends_on = [helm_release.prometheus, helm_release.kube_state_metrics]
}

resource "helm_release" "alloy_receiver" {
  name       = "alloy-receiver"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "alloy"
  version    = var.alloy_chart_version
  namespace  = kubernetes_namespace_v1.monitoring.metadata[0].name

  values = [
    <<-EOT
    alloy:
      configMap:
        content: |
          ${indent(6, file("${path.module}/helm-values/alloy-receiver.alloy"))}
    controller:
      type: deployment
      replicas: 2
      resources:
        requests:
          cpu: 50m
          memory: 128Mi
        limits:
          memory: 256Mi
    service:
      enabled: true
    EOT
  ]

  depends_on = [helm_release.prometheus, helm_release.loki, helm_release.tempo]
}
