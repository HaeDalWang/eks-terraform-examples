
# GitHub 리포지토리 인증 정보
resource "kubernetes_secret_v1" "github_token" {
  metadata {
    name      = "github"
    namespace = kubernetes_namespace_v1.argocd.metadata[0].name
    labels = {
      "argocd.argoproj.io/secret-type" = "repo-creds"
    }
  }

  data = {
    type     = "git"
    url      = "https://github.com/haedalwang"
    username = "HaeDalWang"
    password = jsondecode(data.aws_secretsmanager_secret_version.auth.secret_string)["github"]["token"]
  }
}

# Argo CD에 프로젝트 생성
# hashicorp/kubernetes_manifest는 plan 시 OpenAPI 스키마 조회로 API 서버에 접속한다.
# (참고: registry .kubernetes doc — Before you use this resource) 클러스터·provider 구성이
# plan 단계에 완성되지 않으면 "no client config"가 난다. AppProject는 kubectl_manifest로 둔다.
resource "kubectl_manifest" "argocd_project" {
  yaml_body = <<-YAML
    apiVersion: argoproj.io/v1alpha1
    kind: AppProject
    metadata:
      name: ${local.project}
      namespace: ${kubernetes_namespace_v1.argocd.metadata[0].name}
      finalizers:
        - resources-finalizer.argocd.argoproj.io
    spec:
      description: ${local.project} 환경
      sourceRepos:
        - "*"
      destinations:
        - name: "*"
          server: "*"
          namespace: "*"
      clusterResourceWhitelist:
        - group: "*"
          kind: "*"
  YAML

  depends_on = [
    helm_release.argocd
  ]
}

# # Argo CD 애플리케이션 생성 (ingress-controller-test.git)
# resource "kubernetes_manifest" "argocd_app_ingress_nginx" {
#   manifest = {
#     apiVersion = "argoproj.io/v1alpha1"
#     kind       = "Application"

#     metadata = {
#       name      = "ezl-app-server"
#       namespace = kubernetes_namespace_v1.argocd.metadata[0].name
#       finalizers = [
#         "resources-finalizer.argocd.argoproj.io"
#       ]
#     }

#     spec = {
#       project = local.project

#       sources = [
#         {
#           repoURL        = "https://github.com/HaeDalWang/seungdo-helm-chart.git"
#           targetRevision = "HEAD"
#           path           = "ezl-app-server"
#           helm = {
#             releaseName = "app-server"
#             valueFiles = [
#               "values_dev.yaml"
#             ]
#           }
#         }
#       ]

#       destination = {
#         name      = "in-cluster"
#         namespace = "intgapp"
#       }

#       syncPolicy = {
#         syncOptions : ["CreateNamespace=true"]
#         automated : {}
#       }
#     }
#   }

#   depends_on = [
#     helm_release.argocd,
#     kubectl_manifest.argocd_project
#   ]
# }