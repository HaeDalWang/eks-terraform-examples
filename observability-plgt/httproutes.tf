# ########################################################
# HTTPRoute: Grafana 외부 노출 (Envoy Gateway)
# ########################################################
#
# ExternalDNS가 gateway-httproute 소스를 통해
# HTTPRoute hostname → Route53 레코드를 자동 생성합니다.
#
# [보안 참고]
# 프로덕션에서는 Envoy Gateway SecurityPolicy(OIDC/JWT/BasicAuth) 또는
# Grafana 자체 OAuth 연동으로 인증을 추가해야 합니다. 이 예제는 인증 없이 노출합니다.
#

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
            - name: grafana
              port: 80
  YAML

  depends_on = [
    kubectl_manifest.envoy_gateway,
    helm_release.grafana
  ]
}
