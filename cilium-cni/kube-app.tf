# Argo CD를 설치할 네임스페이스
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }
}
data "aws_secretsmanager_secret_version" "auth" {
  secret_id = "cotong/auth"
}
resource "htpasswd_password" "argocd" {
  password = jsondecode(data.aws_secretsmanager_secret_version.auth.secret_string)["argocd"]["adminPassword"]
}
# Argo CD
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  values = [
    templatefile("${path.module}/helm-values/argocd.yaml", {
      domain                = "argocd.seungdobae.com"
      server_admin_password = htpasswd_password.argocd.bcrypt
    })
  ]

  depends_on = [
    helm_release.ingress_nginx
  ]
}