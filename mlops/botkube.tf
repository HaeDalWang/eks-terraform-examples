# # BotKube - Kubernetes 이벤트 모니터링 및 알림
# # https://artifacthub.io/packages/helm/infracloudio/botkube

# # BotKube 네임스페이스
# resource "kubernetes_namespace" "botkube" {
#   metadata {
#     name = "botkube"
#   }
# }

# # BotKube Helm Chart
# resource "helm_release" "botkube" {
#   count = var.argocd_slack_app_token != "" ? 1 : 0

#   name       = "botkube"
#   repository = "https://charts.botkube.io/"
#   chart      = "botkube"
#   version    = "1.14.0"
#   namespace  = kubernetes_namespace.botkube.metadata[0].name

#   values = [
#     templatefile("${path.module}/helm-values/botkube.yaml", {
#       slack_channel = var.argocd_notification_slack_channel
#       slack_token   = var.argocd_slack_app_token
#       cluster_name  = local.project
#     })
#   ]

#   depends_on = [
#     kubernetes_namespace.botkube
#   ]
# }
