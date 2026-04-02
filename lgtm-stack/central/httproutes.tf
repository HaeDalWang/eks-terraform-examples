# ########################################################
# HTTPRoute: LGTM 서비스 외부 노출 (Envoy Gateway)
# ########################################################
#
# ExternalDNS가 gateway-httproute 소스를 통해
# HTTPRoute hostname → Route53 레코드를 자동 생성합니다.
#
# [보안 참고]
# 프로덕션에서는 Mimir/Loki/Tempo 수신 엔드포인트에 인증을 추가해야 합니다.
# - Envoy Gateway SecurityPolicy (JWT, OIDC, BasicAuth 등)
# - 또는 mTLS (BackendTLSPolicy)
# PoC에서는 인증 없이 노출합니다.
#

# Grafana 대시보드
resource "kubectl_manifest" "httproute_grafana" {
  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: grafana
      namespace: monitoring
    spec:
      parentRefs:
        - name: default
          namespace: envoy-gateway-system
          sectionName: https
      hostnames:
        - "${local.grafana_hostname}"
      rules:
        - matches:
            - path:
                type: PathPrefix
                value: /
          backendRefs:
            - name: prometheus-grafana
              port: 80
  YAML

  depends_on = [
    kubectl_manifest.envoy_gateway,
    helm_release.prometheus
  ]
}

# Prometheus (옵션: 직접 접근 필요시)
resource "kubectl_manifest" "httproute_prometheus" {
  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: prometheus
      namespace: monitoring
    spec:
      parentRefs:
        - name: default
          namespace: envoy-gateway-system
          sectionName: https
      hostnames:
        - "${local.prometheus_hostname}"
      rules:
        - matches:
            - path:
                type: PathPrefix
                value: /
          backendRefs:
            - name: kube-prometheus-prometheus
              port: 9090
  YAML

  depends_on = [
    kubectl_manifest.envoy_gateway,
    helm_release.prometheus
  ]
}

# Mimir Gateway (agent 클러스터 Prometheus → remote-write 수신)
resource "kubectl_manifest" "httproute_mimir" {
  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: mimir
      namespace: monitoring
    spec:
      parentRefs:
        - name: default
          namespace: envoy-gateway-system
          sectionName: https
      hostnames:
        - "${local.mimir_hostname}"
      rules:
        - matches:
            - path:
                type: PathPrefix
                value: /
          backendRefs:
            - name: mimir-gateway
              port: 80
  YAML

  depends_on = [
    kubectl_manifest.envoy_gateway,
    helm_release.mimir
  ]
}

# Loki Gateway (agent 클러스터 Fluent Bit → 로그 push 수신)
resource "kubectl_manifest" "httproute_loki" {
  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: loki
      namespace: monitoring
    spec:
      parentRefs:
        - name: default
          namespace: envoy-gateway-system
          sectionName: https
      hostnames:
        - "${local.loki_hostname}"
      rules:
        - matches:
            - path:
                type: PathPrefix
                value: /
          backendRefs:
            - name: loki-gateway
              port: 80
  YAML

  depends_on = [
    kubectl_manifest.envoy_gateway,
    helm_release.loki
  ]
}

# Tempo Distributor (agent 클러스터 App → OTLP HTTP 수신)
resource "kubectl_manifest" "httproute_tempo" {
  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: tempo
      namespace: monitoring
    spec:
      parentRefs:
        - name: default
          namespace: envoy-gateway-system
          sectionName: https
      hostnames:
        - "${local.tempo_hostname}"
      rules:
        - matches:
            - path:
                type: PathPrefix
                value: /
          backendRefs:
            - name: tempo-distributor
              port: 4318
  YAML

  depends_on = [
    kubectl_manifest.envoy_gateway,
    helm_release.tempo
  ]
}
