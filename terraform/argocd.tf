# # GitHub 리포지토리 인증 정보
# resource "kubernetes_secret_v1" "github_token" {
#   metadata {
#     name      = "github"
#     namespace = kubernetes_namespace.argocd.metadata[0].name
#     labels = {
#       "argocd.argoproj.io/secret-type" = "repo-creds"
#     }
#   }

#   data = {
#     type     = "git"
#     url      = "https://github.com/ezllabs"
#     username = "ezllabschkong"
#     password = jsondecode(data.aws_secretsmanager_secret_version.this.secret_string)["github"]["token"]
#   }

#   depends_on = [
#     helm_release.argocd
#   ]
# }

# # Helm 차트 리포지토리
# resource "kubernetes_secret_v1" "helm_repo" {
#   metadata {
#     name      = "ezl-helm-charts"
#     namespace = kubernetes_namespace.argocd.metadata[0].name
#     labels = {
#       "argocd.argoproj.io/secret-type" = "repository"
#     }
#   }

#   data = {
#     type = "git"
#     url  = "https://github.com/ezllabs/ezl-helm-chart"
#   }

#   depends_on = [
#     helm_release.argocd
#   ]
# }