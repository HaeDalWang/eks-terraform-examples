locals {
  project             = "observability-plgt"
  project_prefix      = "plgt"
  domain_name         = var.domain_name
  project_domain_name = "${local.project_prefix}.${local.domain_name}"
  tags = {
    "terraform" = "true"
    "project"   = local.project
  }

  # Envoy Gateway HTTPRoute로 노출할 호스트명
  # ExternalDNS가 gateway-httproute 소스를 통해 자동으로 Route53 레코드 생성
  grafana_hostname = "grafana.${local.project_domain_name}"

  # Thanos on 일 때 Grafana 메트릭 datasource가 바라보는 대상
  # off: Prometheus 직결 / on: Thanos Query Frontend (HTTP 10902)
  metrics_query_service = var.enable_thanos ? "http://thanos-query-frontend.monitoring.svc.cluster.local:10902" : "http://prometheus-server.monitoring.svc.cluster.local:80"
}
