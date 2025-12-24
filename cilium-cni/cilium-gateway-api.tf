# Cilium Gateway API 구성
# GatewayClass는 Cilium이 자동으로 제공하므로 별도 생성 불필요
# 기본 GatewayClass 이름: "cilium"

# Gateway 리소스: NLB + ACM 인증서를 사용한 TLS 터미네이션
# NLB에서 TLS 터미네이션을 처리하고, 백엔드로는 HTTP(80)로 전달
# Gateway API의 infrastructure 필드를 사용하여 Service annotations 설정
resource "kubectl_manifest" "cilium_gateway" {
  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: Gateway
    metadata:
      name: cilium-gateway
      namespace: default
    spec:
      gatewayClassName: cilium
      
      # infrastructure 필드를 사용하여 생성되는 Service에 annotations 설정
      # Gateway API 표준 스펙에 따라 Service annotations를 지정
      infrastructure:
        annotations:
          # NLB 타입 지정 및 설정
          service.beta.kubernetes.io/aws-load-balancer-type: external
          service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
          service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: ip
          service.beta.kubernetes.io/aws-load-balancer-backend-protocol: tcp
          # TLS 터미네이션을 위한 ACM 인증서 설정
          # NLB에서 443 포트에서 TLS 터미네이션 후 백엔드로는 HTTP(80)로 전달
          service.beta.kubernetes.io/aws-load-balancer-ssl-ports: "443"
          service.beta.kubernetes.io/aws-load-balancer-ssl-cert: ${aws_acm_certificate_validation.project.certificate_arn},${data.aws_acm_certificate.existing.arn}
          # Proxy Protocol 설정 (선택사항)
          service.beta.kubernetes.io/aws-load-balancer-proxy-protocol: "*"
          # Cross-Zone 로드밸런싱 활성화
          service.beta.kubernetes.io/aws-load-balancer-attributes: load_balancing.cross_zone.enabled=true
      listeners:
        # HTTP 리스너 (80 포트)
        - name: http
          protocol: HTTP
          port: 80
          allowedRoutes:
            namespaces:
              from: All
        # HTTPS 리스너 (443 포트)
        # NLB에서 TLS 터미네이션을 처리하므로, Gateway 리스너는 HTTP로 설정
        # NLB가 443에서 TLS를 터미네이션하고 백엔드로는 HTTP(80)로 전달
        - name: https
          protocol: HTTP  # NLB에서 이미 TLS 터미네이션 처리됨
          port: 443       # NLB 443 포트에서 받은 트래픽
          allowedRoutes:
            namespaces:
              from: All
  YAML

  depends_on = [
    helm_release.cilium,
    helm_release.aws_load_balancer_controller,
    aws_acm_certificate_validation.project
  ]
}

# # HTTPRoute 예시: Gateway를 통해 트래픽을 백엔드 서비스로 라우팅
# # 실제 사용 시에는 이 리소스를 참고하여 애플리케이션별로 생성
# resource "kubectl_manifest" "cilium_gateway_httproute_example" {
#   yaml_body = <<-YAML
#     apiVersion: gateway.networking.k8s.io/v1
#     kind: HTTPRoute
#     metadata:
#       name: example-httproute
#       namespace: default
#     spec:
#       parentRefs:
#         - name: cilium-gateway
#           namespace: default
#           sectionName: http  # HTTP listener에 연결
#       hostnames:
#         - "example.${local.project_domain_name}"
#       rules:
#         - matches:
#             - path:
#                 type: PathPrefix
#                 value: /
#           backendRefs:
#             - name: example-service
#               port: 80
#               kind: Service
#   YAML

#   depends_on = [
#     kubectl_manifest.cilium_gateway
#   ]

#   # 예시 리소스이므로 기본적으로 비활성화
#   # 실제 사용 시 이 리소스를 활성화하거나 복사하여 사용
#   count = 0
# }

