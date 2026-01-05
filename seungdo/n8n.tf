# n8n
# ref: https://artifacthub.io/packages/helm/community-charts/n8n

resource "kubernetes_namespace_v1" "n8n" {
  metadata {
    name = "n8n"
  }
}

# n8n
# ref: https://artifacthub.io/packages/helm/community-charts/n8n
resource "helm_release" "n8n" {
  name       = "n8n"
  repository = "https://community-charts.github.io/helm-charts"
  chart      = "n8n"
  version    = "1.16.15"
  namespace  = kubernetes_namespace_v1.n8n.metadata[0].name

  values = [
    templatefile("${path.module}/helm-values/n8n.yaml", {
      domain              = "${local.project_domain_name}"
      n8n_encryption_key  = jsondecode(data.aws_secretsmanager_secret_version.auth.secret_string)["basicauth"]["password"]
      postgresql_password = jsondecode(data.aws_secretsmanager_secret_version.auth.secret_string)["basicauth"]["password"]
    })
  ]

  # PostgreSQL과 Redis가 먼저 준비되어야 함
  timeout = 600
}