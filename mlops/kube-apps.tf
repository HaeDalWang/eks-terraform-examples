# Ingress NGINX를 설치할 네임스페이스
resource "kubernetes_namespace" "ingress_nginx" {
  metadata {
    name = "ingress-nginx"
  }
}

# Ingress NGINX
resource "helm_release" "ingress_nginx" {
  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = var.ingress_nginx_chart_version
  namespace  = kubernetes_namespace.ingress_nginx.metadata[0].name

  values = [
    templatefile("${path.module}/helm-values/ingress-nginx.yaml", {
      lb_acm_certificate_arn = join(",", [
        aws_acm_certificate_validation.project.certificate_arn,
        data.aws_acm_certificate.existing.arn
      ])
    })
  ]

  depends_on = [
    helm_release.karpenter
  ]
}

# OpenSearch 네임스페이스
resource "kubernetes_namespace" "opensearch" {
  metadata {
    name = "opensearch"
  }
}

# OpenSearch
resource "helm_release" "opensearch" {
  name       = "opensearch"
  repository = "https://opensearch-project.github.io/helm-charts/"
  chart      = "opensearch"
  version    = "2.18.0"
  namespace  = kubernetes_namespace.opensearch.metadata[0].name

  replace      = true
  force_update = true

  values = [
    templatefile("${path.module}/helm-values/opensearch.yaml", {})
  ]

  depends_on = [
    helm_release.karpenter
  ]
}

# OpenSearch Dashboards
resource "helm_release" "opensearch_dashboards" {
  name       = "opensearch-dashboards"
  repository = "https://opensearch-project.github.io/helm-charts/"
  chart      = "opensearch-dashboards"
  version    = "2.16.0"
  namespace  = kubernetes_namespace.opensearch.metadata[0].name

  values = [
    templatefile("${path.module}/helm-values/opensearch-dashboards.yaml", {})
  ]

  depends_on = [
    helm_release.opensearch
  ]
}

# Fluent Bit 네임스페이스
resource "kubernetes_namespace" "fluent_bit" {
  metadata {
    name = "fluent-bit"
  }
}

# Fluent Bit
resource "helm_release" "fluent_bit" {
  name       = "fluent-bit"
  repository = "https://fluent.github.io/helm-charts"
  chart      = "fluent-bit"
  version    = "0.46.10"
  namespace  = kubernetes_namespace.fluent_bit.metadata[0].name

  replace      = true
  force_update = true

  values = [
    templatefile("${path.module}/helm-values/fluent-bit.yaml", {})
  ]

  depends_on = [
    helm_release.opensearch
  ]
}

# Argo CD를 설치할 네임스페이스
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }
}

# Argo CD 어드민 비밀번호의 bcrypt hash 생성
resource "htpasswd_password" "argocd" {
  password = "Admin123!"
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
      domain                            = "argocd.${local.domain_name}"
      server_admin_password             = htpasswd_password.argocd.bcrypt
      argocd_slack_app_token            = var.argocd_slack_app_token
      argocd_notification_slack_channel = var.argocd_notification_slack_channel
    })
  ]

  depends_on = [
    helm_release.ingress_nginx
  ]
}

# 외부 비밀 저장소에서 암호 정보를 불러와서 Pod에 볼륨으로 마운트 시켜주는 라이브러리
resource "helm_release" "secrets_store_csi_driver" {
  name       = "secrets-store-csi-driver"
  repository = "https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts"
  chart      = "secrets-store-csi-driver"
  version    = var.secrets_store_csi_driver_chart_version
  namespace  = "kube-system"

  values = [
    templatefile("${path.module}/helm-values/secrets-store-csi-driver.yaml", {})
  ]
}

# Secrets Store CSI Driver에 비밀 정보를 제공해주는 AWS 라이브러리
resource "helm_release" "secrets_store_csi_driver_provider_aws" {
  name       = "secrets-store-csi-driver-provider-aws"
  repository = "https://aws.github.io/secrets-store-csi-driver-provider-aws"
  chart      = "secrets-store-csi-driver-provider-aws"
  version    = var.secrets_store_csi_driver_provider_aws_chart_version
  namespace  = "kube-system"

  values = [
    templatefile("${path.module}/helm-values/secrets-store-csi-driver-provider-aws.yaml", {})
  ]
}

# Secret 객체에 변경이 감지되면 Pod를 재생성해주는 라이브버리
resource "helm_release" "reloader" {
  name       = "reloader"
  repository = "https://stakater.github.io/stakater-charts"
  chart      = "reloader"
  version    = var.reloader_chart_version
  namespace  = "kube-system"

  values = [
    templatefile("${path.module}/helm-values/reloader.yaml", {})
  ]
}

# Argo Rollouts를 설치할 네임스페이스
resource "kubernetes_namespace" "argo_rollouts" {
  metadata {
    name = "argo-rollouts"
  }
}

# Argo Rollout
resource "helm_release" "argo_rollouts" {
  name       = "argo-rollouts"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-rollouts"
  version    = var.argo_rollouts_chart_version
  namespace  = kubernetes_namespace.argo_rollouts.metadata[0].name

  values = [
    templatefile("${path.module}/helm-values/argo-rollouts.yaml", {})
  ]

  depends_on = [
    helm_release.karpenter
  ]
}

# KEDA를 설치할 네임스페이스
resource "kubernetes_namespace" "keda" {
  metadata {
    name = "keda"
  }
}

# KEDA
resource "helm_release" "keda" {
  name       = "keda"
  repository = "https://kedacore.github.io/charts"
  chart      = "keda"
  version    = var.keda_chart_version
  namespace  = kubernetes_namespace.keda.metadata[0].name

  values = [
    templatefile("${path.module}/helm-values/keda.yaml", {})
  ]

  depends_on = [
    helm_release.karpenter
  ]
}

# k8tz 설치할 네임스페이스
resource "kubernetes_namespace" "k8tz" {
  metadata {
    name = "k8tz"
  }
}

# k8tz
resource "helm_release" "k8tz" {
  name       = "k8tz"
  repository = "https://k8tz.github.io/k8tz"
  chart      = "k8tz"
  version    = var.k8tz_chart_version
  namespace  = kubernetes_namespace.k8tz.metadata[0].name

  values = [
    <<-EOT
    replicaCount: 2
    timezone: Asia/Seoul
    createNamespace: false
    namespace: null
    webhook:
      ignoredNamespaces:
        - backup
        - kube-system
    EOT
  ]
}
# # Kubeflow를 설치할 네임스페이스
# resource "kubernetes_namespace" "kubeflow" {
#   metadata {
#     name = "kubeflow"
#   }
# }

# # Kubeflow
# resource "helm_release" "kubeflow" {
#   name       = "kubeflow"
#   repository = "https://kubeflow.github.io/kubeflow"
#   chart      = "kubeflow"
#   version    = var.kubeflow_chart_version
#   namespace  = kubernetes_namespace.kubeflow.metadata[0].name

#   values = [
#     templatefile("${path.module}/helm-values/kubeflow.yaml", {
#       domain = "kubeflow.${local.domain_name}"
#     })
#   ]

#   depends_on = [
#     helm_release.ingress_nginx,
#     helm_release.argocd
#   ]
# }