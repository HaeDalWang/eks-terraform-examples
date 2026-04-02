# ########################################################
# ACM Certificate (NLB TLS 종료용)
# ########################################################
resource "aws_acm_certificate" "project" {
  domain_name       = "*.${local.project_domain_name}"
  validation_method = "DNS"
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "acm_validation" {
  for_each = {
    for dvo in aws_acm_certificate.project.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }
  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.this.zone_id
}

resource "aws_acm_certificate_validation" "project" {
  certificate_arn         = aws_acm_certificate.project.arn
  validation_record_fqdns = [for record in aws_route53_record.acm_validation : record.fqdn]
}

# ########################################################
# Envoy Gateway
# ########################################################
resource "kubernetes_namespace" "envoy_gateway" {
  metadata {
    name = "envoy-gateway-system"
  }
}

resource "helm_release" "envoy_gateway" {
  name       = "envoy-gateway"
  namespace  = kubernetes_namespace.envoy_gateway.metadata[0].name
  repository = "oci://docker.io/envoyproxy"
  chart      = "gateway-helm"
  version    = var.envoy_gateway_chart_version

  values = [
    file("${path.module}/helm-values/envoy-gateway.yaml")
  ]

  depends_on = [
    kubernetes_namespace.envoy_gateway,
    aws_acm_certificate_validation.project,
    helm_release.aws_load_balancer_controller
  ]
}

# EnvoyProxy: NLB Service 설정 템플릿
# Gateway가 생성하는 Envoy Pod/Service에 NLB annotation을 적용
resource "kubectl_manifest" "envoy_proxy" {
  yaml_body = <<-YAML
    apiVersion: gateway.envoyproxy.io/v1alpha1
    kind: EnvoyProxy
    metadata:
      name: envoy-proxy-config
      namespace: ${kubernetes_namespace.envoy_gateway.metadata[0].name}
    spec:
      provider:
        type: Kubernetes
        kubernetes:
          envoyService:
            type: LoadBalancer
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

  depends_on = [helm_release.envoy_gateway]
}

# ClientTrafficPolicy: Proxy Protocol 활성화 (NLB와 쌍으로 사용)
resource "kubectl_manifest" "envoy_client_traffic_policy" {
  yaml_body = <<-YAML
    apiVersion: gateway.envoyproxy.io/v1alpha1
    kind: ClientTrafficPolicy
    metadata:
      name: enable-proxy-protocol
      namespace: ${kubernetes_namespace.envoy_gateway.metadata[0].name}
    spec:
      targetRef:
        group: gateway.networking.k8s.io
        kind: Gateway
        name: default
        namespace: ${kubernetes_namespace.envoy_gateway.metadata[0].name}
      enableProxyProtocol: true
  YAML

  depends_on = [kubectl_manifest.envoy_gateway]
}

# BackendTrafficPolicy: 요청 body 최대 100MB (Mimir remote-write 대용량 지원)
resource "kubectl_manifest" "envoy_backend_traffic_policy" {
  yaml_body = <<-YAML
    apiVersion: gateway.envoyproxy.io/v1alpha1
    kind: BackendTrafficPolicy
    metadata:
      name: request-buffer-100mb
      namespace: ${kubernetes_namespace.envoy_gateway.metadata[0].name}
    spec:
      targetRefs:
        - group: gateway.networking.k8s.io
          kind: Gateway
          name: default
          namespace: ${kubernetes_namespace.envoy_gateway.metadata[0].name}
      requestBuffer:
        limit: "100Mi"
  YAML

  depends_on = [kubectl_manifest.envoy_gateway]
}

# GatewayClass → EnvoyProxy 참조
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
        namespace: ${kubernetes_namespace.envoy_gateway.metadata[0].name}
  YAML

  depends_on = [kubectl_manifest.envoy_proxy]
}

# Gateway: 실제 트래픽 수신 (NLB ↔ Envoy Pod)
resource "kubectl_manifest" "envoy_gateway" {
  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: Gateway
    metadata:
      name: default
      namespace: ${kubernetes_namespace.envoy_gateway.metadata[0].name}
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

  depends_on = [kubectl_manifest.envoy_gateway_class]
}
