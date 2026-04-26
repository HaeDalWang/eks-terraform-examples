# Envoy Gateway Namespace (deprecated 'kubernetes_namespace' → v1)
moved {
  from = kubernetes_namespace.envoy_gateway
  to   = kubernetes_namespace_v1.envoy_gateway
}

resource "kubernetes_namespace_v1" "envoy_gateway" {
  metadata {
    name = "envoy-gateway-system"
  }
}
resource "helm_release" "envoy_gateway" {
  name       = "envoy-gateway"
  namespace  = kubernetes_namespace_v1.envoy_gateway.metadata[0].name
  repository = "oci://docker.io/envoyproxy"
  chart      = "gateway-helm"
  version    = "1.7.1"

  values = [
    templatefile("${path.module}/helm-values/envoy-gateway.yaml", {
      acm_certificate_arn = join(",", [
        aws_acm_certificate_validation.project.certificate_arn,
        data.aws_acm_certificate.existing.arn
      ])
    })
  ]

  depends_on = [
    kubernetes_namespace_v1.envoy_gateway,
    aws_acm_certificate_validation.project,
    helm_release.aws_load_balancer_controller
  ]
}

# EnvoyProxy 리소스: Envoy Service에 annotations를 영구적으로 적용
# 즉, Envoy가 만들 Gateway(실제 NLB 및 트래픽을 받을 Pod)에 아래 설정을 영구적으로 적용하는 템플릿 개념
resource "kubectl_manifest" "envoy_proxy" {
  yaml_body = <<-YAML
    apiVersion: gateway.envoyproxy.io/v1alpha1
    kind: EnvoyProxy
    metadata:
      name: envoy-proxy-config
      namespace: ${kubernetes_namespace_v1.envoy_gateway.metadata[0].name}
    spec:
      provider:
        type: Kubernetes
        kubernetes:
          envoyService:
            type: LoadBalancer
            # NLB listener 443은 Service의 80 포트로 연결됨 (NLB가 자동으로 매핑)
            annotations:
              service.beta.kubernetes.io/aws-load-balancer-type: external
              service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
              service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: ip
              service.beta.kubernetes.io/aws-load-balancer-backend-protocol: tcp
              service.beta.kubernetes.io/aws-load-balancer-ssl-ports: "443"
              service.beta.kubernetes.io/aws-load-balancer-ssl-cert: ${join(",", [
  aws_acm_certificate_validation.project.certificate_arn,
  data.aws_acm_certificate.existing.arn
])}
              service.beta.kubernetes.io/aws-load-balancer-proxy-protocol: "*"
              service.beta.kubernetes.io/aws-load-balancer-attributes: load_balancing.cross_zone.enabled=true
  YAML

depends_on = [
  helm_release.envoy_gateway
]
}

# ClientTrafficPolicy: NLB Proxy Protocol 사용 시 Envoy가 프록시 프로토콜 헤더 해석하도록 설정
# NLB annotation service.beta.kubernetes.io/aws-load-balancer-proxy-protocol: "*" 와 쌍으로 사용
# https://gateway.envoyproxy.io/docs/api/extension_types/#clienttrafficpolicyspec
resource "kubectl_manifest" "envoy_client_traffic_policy_proxy_protocol" {
  yaml_body = <<-YAML
    apiVersion: gateway.envoyproxy.io/v1alpha1
    kind: ClientTrafficPolicy
    metadata:
      name: enable-proxy-protocol
      namespace: ${kubernetes_namespace_v1.envoy_gateway.metadata[0].name}
    spec:
      targetRef:
        group: gateway.networking.k8s.io
        kind: Gateway
        name: default
        namespace: ${kubernetes_namespace_v1.envoy_gateway.metadata[0].name}
      enableProxyProtocol: true
  YAML

  depends_on = [
    kubectl_manifest.envoy_gateway
  ]
}

# BackendTrafficPolicy: 요청 body 최대 100MB 허용 (Envoy buffer filter)
# Gateway 타겟이면 해당 Gateway 하위 모든 HTTPRoute에 적용
# https://gateway.envoyproxy.io/docs/api/extension_types/#backendtrafficpolicyspec
resource "kubectl_manifest" "envoy_backend_traffic_policy_request_buffer" {
  yaml_body = <<-YAML
    apiVersion: gateway.envoyproxy.io/v1alpha1
    kind: BackendTrafficPolicy
    metadata:
      name: request-buffer-100mb
      namespace: ${kubernetes_namespace_v1.envoy_gateway.metadata[0].name}
    spec:
      targetRefs:
        - group: gateway.networking.k8s.io
          kind: Gateway
          name: default
          namespace: ${kubernetes_namespace_v1.envoy_gateway.metadata[0].name}
      requestBuffer:
        limit: "100Mi"
  YAML

  depends_on = [
    kubectl_manifest.envoy_gateway
  ]
}

# Envoy Gateway GatewayClass
# Gateway 리소스가 어떤 컨트롤러를 사용해서 만들지 정의하는 리소스, gateway 리소스를 사용하는 컨트롤러가 여러 종류 일 수 있으므로: Envoy, Cilium etc.
# 파라미터는 각 컨트롤러가 지원하는 항목을 참조하도록 지정가능, 여기서는 envoy이므로 위에서만든 envoyproxy을 지정
resource "kubectl_manifest" "envoy_gateway_class" {
  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: GatewayClass
    metadata:
      name: envoy-gateway-class
    spec:
      controllerName: gateway.envoyproxy.io/gatewayclass-controller
      parametersRef:
        group: gateway.envoyproxy.io
        kind: EnvoyProxy
        name: envoy-proxy-config
        namespace: ${kubernetes_namespace_v1.envoy_gateway.metadata[0].name}
  YAML

  depends_on = [
    kubectl_manifest.envoy_proxy
  ]
}

# Envoy Gateway
# 실제 트래픽을 받을 Pod/Service를 만들도록하는 리소스
# Gateway을 만들때는 GatewayClass을 참조하여 만들어진다
resource "kubectl_manifest" "envoy_gateway" {
  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: Gateway
    metadata:
      name: default
      namespace: ${kubernetes_namespace_v1.envoy_gateway.metadata[0].name}
    spec:
      gatewayClassName: envoy-gateway-class
      listeners:
        - name: http
          protocol: HTTP
          port: 80
          allowedRoutes:
            namespaces:
              from: All
        - name: https
          protocol: HTTP
          port: 443
          allowedRoutes:
            namespaces:
              from: All
  YAML

  depends_on = [
    kubectl_manifest.envoy_gateway_class
  ]
}