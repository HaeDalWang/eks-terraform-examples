# Traefik Namespace
resource "kubernetes_namespace" "traefik" {
  metadata {
    name = "traefik"
  }
}

# Traefik
resource "helm_release" "traefik" {
  name       = "traefik"
  repository = "https://traefik.github.io/charts"
  chart      = "traefik"
  version    = var.traefik_chart_version
  namespace  = kubernetes_namespace.traefik.metadata[0].name

  values = [
    templatefile("${path.module}/helm-values/traefik.yaml", {
      vpc_cidr = module.vpc.vpc_cidr_block
      acm_certificate_arn = join(",", [
        aws_acm_certificate_validation.project.certificate_arn,
        data.aws_acm_certificate.existing.arn
      ])
      providers_file_content = indent(6, file("${path.module}/yaml/traefik-middlewares.yaml"))
    })
  ]

  depends_on = [
    aws_acm_certificate_validation.project,
    kubectl_manifest.karpenter_default_nodepool,
    helm_release.aws_load_balancer_controller
  ]
}

# Traefik Dashboard Ingress
# Nginx Ingress Controller를 통해 대시보드 노출
# NLB에서 TLS termination이 되므로 Ingress에서는 TLS 설정 불필요
resource "kubectl_manifest" "traefik_dashboard" {
  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: Ingress
    metadata:
      name: traefik-dashboard
      namespace: ${kubernetes_namespace.traefik.metadata[0].name}
    spec:
      ingressClassName: nginx
      rules:
        - host: traefik-dashboard.seungdobae.com
          http:
            paths:
              - path: /
                pathType: Prefix
                backend:
                  service:
                    name: traefik
                    port:
                      name: traefik
    YAML

  depends_on = [
    helm_release.traefik
  ]
}

