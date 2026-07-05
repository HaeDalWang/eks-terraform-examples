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

# EnvoyProxy: NLB Service 설정 + 데이터플레인 Envoy Proxy pod 메트릭 노출
# Gateway가 생성하는 실제 트래픽 처리 Pod(Envoy Proxy, 컨트롤러 아님)에
# NLB annotation과 Prometheus 스크레이핑 annotation을 적용합니다.
#
# [트레이스 입구 메트릭]
# 여기서 노출되는 :19001/stats/prometheus 가 실제 요청이 지나가는 지점의
# RED 메트릭(envoy_http_downstream_rq_total, envoy_cluster_upstream_rq_time 등)입니다.
# 컨트롤러(envoy-gateway) 자체 메트릭은 gateway-helm 차트 기본값에 이미
# prometheus.io/scrape annotation이 있어 별도 설정 없이도 스크레이핑됩니다.
resource "kubectl_manifest" "envoy_proxy" {
  yaml_body = <<-YAML
    apiVersion: gateway.envoyproxy.io/v1alpha1
    kind: EnvoyProxy
    metadata:
      name: envoy-proxy-config
      namespace: ${kubernetes_namespace.envoy_gateway.metadata[0].name}
    spec:
      telemetry:
        metrics:
          prometheus: {}
      provider:
        type: Kubernetes
        kubernetes:
          envoyDeployment:
            pod:
              annotations:
                prometheus.io/scrape: "true"
                prometheus.io/port: "19001"
                prometheus.io/path: "/stats/prometheus"
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
              service.beta.kubernetes.io/aws-load-balancer-ssl-negotiation-policy: "ELBSecurityPolicy-TLS13-1-2-2021-06"
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
# 이 예제는 Grafana 조회용 HTTPS 노출만 필요 (OTLP/remote-write 수신은 cluster-internal)
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
