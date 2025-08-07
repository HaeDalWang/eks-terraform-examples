# # Datadog Namespace 생성
# resource "kubernetes_namespace" "datadog" {
#   metadata {
#     name = "datadog"
#   }
# }

# # datadog agent helm 설치
# resource "helm_release" "datadog" {
#   name       = "datadog"
#   repository = "https://helm.datadoghq.com"
#   chart      = "datadog"
#   version    = "3.123.0"
#   namespace  = kubernetes_namespace.datadog.metadata[0].name
#   values = [
#     templatefile("${path.module}/helm-values/datadog.yaml", {}
#     )]
# }