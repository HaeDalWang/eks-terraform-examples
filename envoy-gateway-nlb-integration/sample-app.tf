############################################
# 샘플 애플리케이션 (nginx + Service + HTTPRoute)
############################################

resource "kubectl_manifest" "sample_app" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: Namespace
    metadata:
      name: httproute-example
  YAML
}

resource "kubectl_manifest" "sample_app_workload" {
  yaml_body = <<-YAML
    ---
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: nginx-example
      namespace: httproute-example
      labels:
        app: nginx-example
    spec:
      replicas: 1
      selector:
        matchLabels:
          app: nginx-example
      template:
        metadata:
          labels:
            app: nginx-example
        spec:
          containers:
            - name: nginx
              image: nginx:stable
              ports:
                - containerPort: 80
    ---
    apiVersion: v1
    kind: Service
    metadata:
      name: nginx-example
      namespace: httproute-example
    spec:
      selector:
        app: nginx-example
      ports:
        - name: http
          port: 80
          targetPort: 80
    ---
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: nginx-example
      namespace: httproute-example
    spec:
      parentRefs:
        - name: default
          namespace: envoy-gateway-system
          sectionName: https
      hostnames:
        - "nginx-example.${local.domain_name}"
      rules:
        - matches:
            - path:
                type: PathPrefix
                value: /
          backendRefs:
            - name: nginx-example
              port: 80
  YAML

  depends_on = [
    kubectl_manifest.sample_app,
    kubectl_manifest.envoy_gateway,
  ]
}

