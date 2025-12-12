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
      vpc_cidr            = module.vpc.vpc_cidr_block
      acm_certificate_arn = join(",", [
        aws_acm_certificate_validation.project.certificate_arn,
        data.aws_acm_certificate.existing.arn
      ])
    })
  ]

  depends_on = [
    aws_acm_certificate_validation.project,
    kubectl_manifest.karpenter_default_nodepool,
    helm_release.aws_load_balancer_controller
  ]
}


# # Traefik 대시보드 Ingress
# resource "kubectl_manifest" "traefik_dashboard" {
#   yaml_body = templatefile("${path.module}/yamls/traefik-dashboard.yaml", {
#     domain_name = local.project_domain_name
#   })

#   depends_on = [
#     helm_release.traefik
#   ]
# }