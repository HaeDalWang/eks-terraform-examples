# Argo CD를 설치할 네임스페이스
resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name = "argocd"
  }
}
resource "htpasswd_password" "argocd" {
  password = jsondecode(data.aws_secretsmanager_secret_version.auth.secret_string)["basicauth"]["password"]
}
# Argo CD
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version
  namespace  = kubernetes_namespace_v1.argocd.metadata[0].name

  values = [
    templatefile("${path.module}/helm-values/argocd.yaml", {
      domain                = "argocd.${local.project_domain_name}"
      server_admin_password = htpasswd_password.argocd.bcrypt,
      lb_acm_certificate_arn = join(",", [
        aws_acm_certificate_validation.project.certificate_arn,
        data.aws_acm_certificate.existing.arn
      ]),
      lb_group_name = local.project
    })
  ]

  depends_on = [
    helm_release.aws_load_balancer_controller
  ]
}