# # Envoy Gateway Namespace
# resource "kubernetes_namespace" "envoy_gateway" {
#   metadata {
#     name = "envoy-gateway-system"
#   }
# }

# # Envoy Gateway CRDs
# # 주석 처리: Helm release Secret 크기 제한(1MB) 초과 문제로 인해 비활성화
# # CRD는 envoy-gateway chart에서 직접 설치 (skip_crds = false)
# # resource "helm_release" "envoy_gateway_crds" {
# #   name       = "envoy-gateway-crds"
# #   namespace  = kubernetes_namespace.envoy_gateway.metadata[0].name
# #   repository = "oci://docker.io/envoyproxy"
# #   chart      = "gateway-crds-helm"
# #   version    = "1.6.1"
# #   values = [
# #     <<-EOT
# #     crds:
# #       gatewayAPI:
# #         enabled: true
# #         channel: standard
# #       envoyGateway:
# #         enabled: true
# #     EOT
# #   ]
# # }

# # Envoy Gateway Helm Chart
# # CRD는 chart에서 직접 설치 (skip_crds = false)
# # 별도의 CRD chart를 사용하면 Helm release Secret 크기 제한(1MB) 초과 문제 발생
# resource "helm_release" "envoy_gateway" {
#   name       = "envoy-gateway"
#   namespace  = kubernetes_namespace.envoy_gateway.metadata[0].name
#   repository = "oci://docker.io/envoyproxy"
#   chart      = "gateway-helm"
#   version    = "1.6.1"
#   skip_crds  = false # CRD를 chart에서 직접 설치
#   values = [
#     templatefile("${path.module}/helm-values/envoy-gateway.yaml", {
#       acm_certificate_arn = join(",", [
#         aws_acm_certificate_validation.project.certificate_arn,
#         data.aws_acm_certificate.existing.arn
#       ])
#     })
#   ]

#   depends_on = [
#     kubernetes_namespace.envoy_gateway,
#     aws_acm_certificate_validation.project,
#     helm_release.aws_load_balancer_controller
#     # helm_release.envoy_gateway_crds  # 주석 처리됨
#   ]
# }

# # EnvoyProxy 리소스: Envoy Service에 annotations를 영구적으로 적용
# # 즉, Envoy가 만들 Gateway(실제 NLB 및 트래픽을 받을 Pod)에 아래 설정을 영구적으로 적용하는 템플릿 개념
# resource "kubectl_manifest" "envoy_proxy" {
#   yaml_body = <<-YAML
#     apiVersion: gateway.envoyproxy.io/v1alpha1
#     kind: EnvoyProxy
#     metadata:
#       name: envoy-proxy-config
#       namespace: ${kubernetes_namespace.envoy_gateway.metadata[0].name}
#     spec:
#       provider:
#         type: Kubernetes
#         kubernetes:
#           envoyService:
#             type: LoadBalancer
#             # ports 설정 제거: Gateway listener가 80만 사용하므로 자동으로 10080으로 매핑됨
#             # NLB listener 443은 Service의 80 포트로 연결됨 (NLB가 자동으로 매핑)
#             annotations:
#               service.beta.kubernetes.io/aws-load-balancer-type: external
#               service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
#               service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: ip
#               service.beta.kubernetes.io/aws-load-balancer-backend-protocol: tcp
#               service.beta.kubernetes.io/aws-load-balancer-ssl-ports: "443"
#               service.beta.kubernetes.io/aws-load-balancer-ssl-cert: ${join(",", [
#   aws_acm_certificate_validation.project.certificate_arn,
#   data.aws_acm_certificate.existing.arn
# ])}
#               service.beta.kubernetes.io/aws-load-balancer-proxy-protocol: "*"
#               service.beta.kubernetes.io/aws-load-balancer-attributes: load_balancing.cross_zone.enabled=true
#   YAML

# depends_on = [
#   helm_release.envoy_gateway
# ]
# }

# # Envoy Gateway GatewayClass
# # Gateway 리소스가 어떤 컨트롤러를 사용해서 만들지 정의하는 리소스
# # 파라미터는 각 컨트롤러가 지원하는 항목을 참조하도록 지정가능, 여기서는 envoy이므로 위에서만든 envoyproxy을 지정
# resource "kubectl_manifest" "envoy_gateway_class" {
#   yaml_body = <<-YAML
#     apiVersion: gateway.networking.k8s.io/v1
#     kind: GatewayClass
#     metadata:
#       name: envoy-gateway-class
#     spec:
#       controllerName: gateway.envoyproxy.io/gatewayclass-controller
#       parametersRef:
#         group: gateway.envoyproxy.io
#         kind: EnvoyProxy
#         name: envoy-proxy-config
#         namespace: ${kubernetes_namespace.envoy_gateway.metadata[0].name}
#   YAML

#   depends_on = [
#     kubectl_manifest.envoy_proxy
#   ]
# }

# # Envoy Gateway
# # 실제 트래픽을 받을 Pod/Service를 만들도록하는 리소스
# # Gateway을 만들때는 GatewayClass을 참조하여 만들어진다
# resource "kubectl_manifest" "envoy_gateway" {
#   yaml_body = <<-YAML
#     apiVersion: gateway.networking.k8s.io/v1
#     kind: Gateway
#     metadata:
#       name: envoy-gateway
#       namespace: ${kubernetes_namespace.envoy_gateway.metadata[0].name}

#     spec:
#       gatewayClassName: envoy-gateway-class
#       listeners:
#         - name: http
#           protocol: HTTP
#           port: 80
#           allowedRoutes:
#             namespaces:
#               from: All
#         - name: https
#           protocol: HTTP  # 프로토콜은 HTTP (NLB에서 이미 TLS termination됨)
#           port: 443        # 포트 443 (Envoy Gateway가 자동으로 10443으로 매핑하지만, NLB에서 TLS termination 후 HTTP로 전달됨)
#           allowedRoutes:
#             namespaces:
#               from: All
#   YAML

#   depends_on = [
#     kubectl_manifest.envoy_gateway_class
#   ]
# }

# # # Envoy Gateway Admin Dashboard Service
# # # Envoy Gateway의 admin 인터페이스(포트 19000)를 노출하기 위한 Service
# # # helm-values/envoy-gateway.yaml에서 admin.address를 0.0.0.0으로 설정하여 외부 접근 가능
# # resource "kubernetes_service" "envoy_gateway_admin" {
# #   metadata {
# #     name      = "envoy-gateway-admin"
# #     namespace = kubernetes_namespace.envoy_gateway.metadata[0].name
# #     labels = {
# #       app = "envoy-gateway-admin"
# #     }
# #   }

# #   spec {
# #     type = "ClusterIP"
# #     selector = {
# #       "app.kubernetes.io/name" = "gateway-helm"
# #     }
# #     port {
# #       name        = "admin"
# #       port        = 19000
# #       target_port = 19000
# #       protocol    = "TCP"
# #     }
# #   }

# #   depends_on = [
# #     helm_release.envoy_gateway
# #   ]
# # }

# # # Envoy Gateway Admin Dashboard HTTPRoute
# # # Gateway API를 사용하여 대시보드 노출
# # # 참고: Envoy Gateway admin 인터페이스는 직접 접근을 위해 설계되었으므로,
# # # HTTPRoute를 통한 프록시 접근 시 제한이 있을 수 있습니다.
# # resource "kubectl_manifest" "envoy_gateway_admin_dashboard" {
# #   yaml_body = <<-YAML
# #     apiVersion: gateway.networking.k8s.io/v1
# #     kind: HTTPRoute
# #     metadata:
# #       name: envoy-gateway-admin-dashboard
# #       namespace: ${kubernetes_namespace.envoy_gateway.metadata[0].name}
# #     spec:
# #       parentRefs:
# #         - name: envoy-gateway  # Gateway 리소스 참조
# #           namespace: ${kubernetes_namespace.envoy_gateway.metadata[0].name}
# #           sectionName: http  # HTTP listener에 연결
# #       hostnames:
# #         - envoy-gateway-admin.seungdobae.com
# #       rules:
# #         - matches:
# #             - path:
# #                 type: PathPrefix
# #                 value: /
# #           backendRefs:
# #             - name: envoy-gateway-admin
# #               port: 19000
# #               kind: Service
# #   YAML

# #   depends_on = [
# #     kubernetes_service.envoy_gateway_admin,
# #     kubectl_manifest.envoy_gateway
# #   ]
# # }

