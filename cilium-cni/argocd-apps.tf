
# # Argo CD 애플리케이션 생성 - Ingress-nginx 사용 시
# resource "kubernetes_manifest" "argocd_app_ingress_nginx" {
#   manifest = {
#     apiVersion = "argoproj.io/v1alpha1"
#     kind       = "Application"

#     metadata = {
#       name      = "ingress-echo-nginx"
#       namespace = kubernetes_namespace.argocd.metadata[0].name
#       finalizers = [
#         "resources-finalizer.argocd.argoproj.io"
#       ]
#     }

#     spec = {
#       project = kubernetes_manifest.argocd_project.manifest.metadata.name

#       sources = [
#         {
#           repoURL        = "https://github.com/HaeDalWang/ingress-controller-test.git"
#           targetRevision = "HEAD"
#           path           = "chart"
#           helm = {
#             releaseName = "ingress-echo-nginx"
#             valueFiles = [
#               "values_nginx.yaml"
#             ]
#           }
#         }
#       ]

#       destination = {
#         name      = "in-cluster"
#         namespace = "app"
#       }

#       syncPolicy = {
#         syncOptions : ["CreateNamespace=true"]
#         automated : {}
#       }
#     }
#   }

#   depends_on = [
#     helm_release.argocd,
#     kubernetes_manifest.argocd_project
#   ]
# }


# # Argo CD 애플리케이션 생성 - Traefik 사용 시
# resource "kubernetes_manifest" "argocd_app_ingress_traefik" {
#   manifest = {
#     apiVersion = "argoproj.io/v1alpha1"
#     kind       = "Application"

#     metadata = {
#       name      = "ingress-echo-traefik"
#       namespace = kubernetes_namespace.argocd.metadata[0].name
#       finalizers = [
#         "resources-finalizer.argocd.argoproj.io"
#       ]
#     }

#     spec = {
#       project = kubernetes_manifest.argocd_project.manifest.metadata.name

#       sources = [
#         {
#           repoURL        = "https://github.com/HaeDalWang/ingress-controller-test.git"
#           targetRevision = "HEAD"
#           path           = "chart"
#           helm = {
#             releaseName = "ingress-echo-traefik"
#             valueFiles = [
#               "values_traefik.yaml"
#             ]
#           }
#         }
#       ]

#       destination = {
#         name      = "in-cluster"
#         namespace = "app"
#       }

#       syncPolicy = {
#         syncOptions : ["CreateNamespace=true"]
#         automated : {}
#       }
#     }
#   }

#   depends_on = [
#     helm_release.argocd,
#     kubernetes_manifest.argocd_project
#   ]
# }