# # KEDA를 설치할 네임스페이스
# resource "kubernetes_namespace" "keda" {
#   metadata {
#     name = "keda"
#   }
# }

# # KEDA
# resource "helm_release" "keda" {
#   name       = "keda"
#   repository = "https://kedacore.github.io/charts"
#   chart      = "keda"
#   version    = "2.13.1"
#   namespace  = kubernetes_namespace.keda.metadata[0].name

#   values = [
#     templatefile("${path.module}/helm-values/keda.yaml", {})
#   ]

#   depends_on = [
#     helm_release.karpenter
#   ]
# }