locals {
  project             = "lgtm-central"
  project_prefix      = "lgtm"
  domain_name         = var.domain_name
  project_domain_name = "${local.project_prefix}.${local.domain_name}"
  tags = {
    "terraform" = "true"
    "project"   = local.project
  }

  # Envoy Gateway HTTPRoute로 노출할 호스트명
  # ExternalDNS가 gateway-httproute 소스를 통해 자동으로 Route53 레코드 생성
  grafana_hostname    = "grafana.${local.project_domain_name}"
  prometheus_hostname = "prometheus.${local.project_domain_name}"
  mimir_hostname      = "mimir.${local.project_domain_name}"
  loki_hostname       = "loki.${local.project_domain_name}"
  tempo_hostname      = "tempo.${local.project_domain_name}"
}
