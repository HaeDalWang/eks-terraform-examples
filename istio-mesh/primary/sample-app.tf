# ########################################################
# 샘플 애플리케이션 (Sidecar 주입 테스트)
# ########################################################

# 네임스페이스에 istio-injection 라벨 → 자동 사이드카 주입
resource "kubernetes_namespace_v1" "sample_app" {
  metadata {
    name = "sample-app"
    labels = {
      "istio-injection" = "enabled"
    }
  }
}

# httpbin 배포 (Istio 공식 예제)
resource "kubectl_manifest" "sample_app" {
  yaml_body = <<-YAML
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: httpbin
      namespace: sample-app
      labels:
        app: httpbin
    spec:
      replicas: 1
      selector:
        matchLabels:
          app: httpbin
      template:
        metadata:
          labels:
            app: httpbin
        spec:
          containers:
          - name: httpbin
            image: kennethreitz/httpbin
            ports:
            - containerPort: 80
            resources:
              requests:
                cpu: 50m
                memory: 64Mi
              limits:
                memory: 128Mi
    ---
    apiVersion: v1
    kind: Service
    metadata:
      name: httpbin
      namespace: sample-app
    spec:
      selector:
        app: httpbin
      ports:
      - name: http
        port: 80
        targetPort: 80
  YAML

  depends_on = [
    kubernetes_namespace_v1.sample_app,
    helm_release.istiod,
  ]
}

# Kubernetes Gateway API HTTPRoute로 Ingress 노출
resource "kubectl_manifest" "sample_httproute" {
  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: httpbin
      namespace: sample-app
    spec:
      parentRefs:
        - name: istio-ingressgateway
          namespace: istio-ingress
      hostnames:
        - "httpbin.${local.project_domain_name}"
      rules:
        - matches:
            - path:
                type: PathPrefix
                value: /
          backendRefs:
            - name: httpbin
              port: 80
  YAML

  depends_on = [
    kubectl_manifest.sample_app,
    helm_release.istio_ingress_gateway,
  ]
}

# PeerAuthentication: sample-app 네임스페이스에 STRICT mTLS 강제
resource "kubectl_manifest" "sample_peer_auth" {
  yaml_body = <<-YAML
    apiVersion: security.istio.io/v1
    kind: PeerAuthentication
    metadata:
      name: default
      namespace: sample-app
    spec:
      mtls:
        mode: STRICT
  YAML

  depends_on = [helm_release.istiod]
}
