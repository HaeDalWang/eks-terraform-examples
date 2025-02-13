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
      lb_acm_certificate_arn = aws_acm_certificate_validation.service_domain.certificate_arn
      whitelist_source_range = join(",", local.whitelist_ip_range)
    })
  ]

  depends_on = [
    helm_release.karpenter
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
  password = jsondecode(data.aws_secretsmanager_secret_version.this.secret_string)["argocd"]["adminPassword"]
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
      domain                            = "argocd.${local.service_domain_name}"
      server_admin_password             = htpasswd_password.argocd.bcrypt
      argocd_slack_app_token            = var.argocd_slack_app_token
      argocd_notification_slack_channel = var.argocd_notification_slack_channel
    })
  ]

  depends_on = [
    helm_release.ingress_nginx
  ]
}

# Prometheus를 설치할 네임스페이스
resource "kubernetes_namespace" "prometheus" {
  metadata {
    name = "monitoring"
  }
}

# Grafana assume 정책 설정
resource "aws_iam_policy" "grafana_account_access" {
  name = "grafana-account-access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "sts:AssumeRole",
        ]
        Effect = "Allow"
        Resource = [
          "*"
        ]
      },
    ]
  })
}

# Thanos 컴포넌트에 부여할 IAM 역할
module "grafana_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.39.0"

  role_name = "${module.eks.cluster_name}-cluster-grafana-role"

  role_policy_arns = {
    grafana_account_access = aws_iam_policy.grafana_account_access.arn
  }

  oidc_providers = {
    grafana = {
      provider_arn = module.eks.oidc_provider_arn
      namespace_service_accounts = [
        "monitoring:prometheus-grafana"
      ]
    }
  }
}

# Thanos 사이드카에서 Prometheus 지표를 보낼 버킷
# 생성에 실패하면 새로운 버킷으로 시도합니다
resource "aws_s3_bucket" "thanos" {
  bucket = "headal-thanos-storage"

  force_destroy = true
}

# 위에서 생성한 버킷에 대한 접근 설정
resource "aws_iam_policy" "thanos_s3_access" {
  name = "thanos-s3-access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:PutObject"
        ]
        Effect = "Allow"
        Resource = [
          aws_s3_bucket.thanos.arn,
          "${aws_s3_bucket.thanos.arn}/*"
        ]
      },
    ]
  })
}

# Thanos 컴포넌트에 부여할 IAM 역할
module "thanos_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.39.0"

  role_name = "${module.eks.cluster_name}-cluster-thanos-role"

  role_policy_arns = {
    thanos_s3_access = aws_iam_policy.thanos_s3_access.arn
  }

  oidc_providers = {
    thanos = {
      provider_arn = module.eks.oidc_provider_arn
      namespace_service_accounts = [
        "thanos:thanos-bucketweb",
        "thanos:thanos-compactor",
        "thanos:thanos-storegateway",
        "monitoring:kube-prometheus-prometheus"
      ]
    }
  }
}

# Thanos 사이드카 설정 파일 (https://thanos.io/tip/thanos/storage.md/#s3)
resource "kubernetes_secret_v1" "prometheus_object_store_config" {
  metadata {
    name      = "thanos-objstore-config"
    namespace = kubernetes_namespace.prometheus.metadata[0].name
  }

  data = {
    "thanos.yml" = yamlencode({
      type   = "s3"
      prefix = "mgm"
      config = {
        bucket   = aws_s3_bucket.thanos.bucket
        endpoint = replace(aws_s3_bucket.thanos.bucket_regional_domain_name, "${aws_s3_bucket.thanos.bucket}.", "")
      }
    })
  }
}

# Alertmanager 접근 비밀번호
resource "htpasswd_password" "alertmanager" {
  password = jsondecode(data.aws_secretsmanager_secret_version.this.secret_string)["alertmanager"]["password"]
}


resource "kubernetes_secret" "alertmanager" {
  metadata {
    name      = "alertmanager-password"
    namespace = kubernetes_namespace.prometheus.metadata[0].name
  }

  data = {
    auth = "admin:${htpasswd_password.alertmanager.bcrypt}"
  }

  type = "Opaque"
}

# Kube-prometheus-stack
resource "helm_release" "prometheus" {
  name       = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = var.kube_prometheus_stack_chart_version
  namespace  = kubernetes_namespace.prometheus.metadata[0].name

  values = [
    templatefile("${path.module}/helm-values/prometheus.yaml", {
      cluster_name                      = module.eks.cluster_name
      alertmanager_hostname             = "alertmanager.${local.service_domain_name}"
      grafana_hostname                  = "grafana.${local.service_domain_name}"
      thanos_hostname                   = "thanos-query.${local.service_domain_name}"
      # slack_channel                     = var.alert_slack_channel
      # slack_webhook_url                 = var.alert_slack_webhook_url
      grafana_role_arn                  = module.grafana_irsa.iam_role_arn
      thanos_sidecar_role_arn           = module.thanos_irsa.iam_role_arn
      thanos_objconfig_secret_name      = kubernetes_secret_v1.prometheus_object_store_config.metadata[0].name
      alertmanager_password_secret_name = kubernetes_secret.alertmanager.metadata[0].name
      grafana_admin_password            = jsondecode(data.aws_secretsmanager_secret_version.this.secret_string)["grafana"]["adminPassword"]
      thanos_password                   = jsondecode(data.aws_secretsmanager_secret_version.this.secret_string)["thanos"]["password"]
    })
  ]

  depends_on = [
    helm_release.ingress_nginx
  ]
}

# Thanos를 설치할 네임스페이스
resource "kubernetes_namespace" "thanos" {
  metadata {
    name = "thanos"
  }
}

# Thanos 컴포넌트에서 사용할 오브젝트 스토리지 (S3) 설정 파일
resource "kubernetes_secret_v1" "thanos_object_store_config" {
  metadata {
    name      = "objstore-config"
    namespace = kubernetes_namespace.thanos.metadata[0].name
  }

  data = {
    "objstore.yml" = yamlencode({
      type   = "s3"
      prefix = "mgm"
      config = {
        bucket   = aws_s3_bucket.thanos.bucket
        endpoint = replace(aws_s3_bucket.thanos.bucket_regional_domain_name, "${aws_s3_bucket.thanos.bucket}.", "")
      }
    })
  }
}

# Thanos 접근 비밀번호
resource "htpasswd_password" "thanos" {
  password = jsondecode(data.aws_secretsmanager_secret_version.this.secret_string)["thanos"]["password"]
}

resource "kubernetes_secret" "thanos" {
  metadata {
    name      = "thanos-password"
    namespace = kubernetes_namespace.thanos.metadata[0].name
  }

  data = {
    auth = "admin:${htpasswd_password.thanos.bcrypt}"
  }

  type = "Opaque"
}

# Thanos
resource "helm_release" "thanos" {
  name       = "thanos"
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "thanos"
  version    = var.thanos_chart_version
  namespace  = kubernetes_namespace.thanos.metadata[0].name

  values = [
    templatefile("${path.module}/helm-values/thanos.yaml", {
      query_frontend_hostname      = "thanos-query.${local.service_domain_name}"
      thanos_password_secret_name  = kubernetes_secret.thanos.metadata[0].name
      thanos_role_arn              = module.thanos_irsa.iam_role_arn
      thanos_objconfig_secret_name = kubernetes_secret_v1.thanos_object_store_config.metadata[0].name
    })
  ]

  depends_on = [
    helm_release.prometheus
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
    EOT
  ]
}

# Keycloak을 설치할 네임스페이스
resource "kubernetes_namespace" "keycloak" {
  metadata {
    name = "keycloak"
  }
}

# Keycloak
resource "helm_release" "keycloak" {
  name       = "keycloak"
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "keycloak"
  version    = var.keycloak_chart_version
  namespace  = kubernetes_namespace.keycloak.metadata[0].name

  values = [
    templatefile("${path.module}/helm-values/keycloak.yaml", {
      hostname  = "keycloak.${local.service_domain_name}"
      adminUser = jsondecode(data.aws_secretsmanager_secret_version.this.secret_string)["keycloak"]["username"]
      # 초기 비밀번호 - 비밀번호 변경이 필요한 경우에는 Keycloak UI에서 변경해야 함
      initialAdminPassword = jsondecode(data.aws_secretsmanager_secret_version.this.secret_string)["keycloak"]["password"]
    })
  ]

  depends_on = [
    helm_release.ingress_nginx
  ]
}

# # Kubernetes Event Exporter를 설치할 네임스페이스
# resource "kubernetes_namespace" "kubernetes_event_exporter" {
#   metadata {
#     name = "kubernetes-event-exporter"
#   }
# }

# # Kubernetes Event Exporter
# resource "helm_release" "kubernetes_event_exporter" {
#   name       = "kubernetes-event-exporter"
#   repository = "https://charts.bitnami.com/bitnami"
#   chart      = "kubernetes-event-exporter"
#   version    = var.kubernetes_event_exporter_chart_version
#   namespace  = kubernetes_namespace.kubernetes_event_exporter.metadata[0].name

#   values = [
#     templatefile("${path.module}/helm-values/kubernetes-event-exporter.yaml", {
#       cluster_name        = local.project
#       opensearch_username = jsondecode(data.aws_secretsmanager_secret_version.this.secret_string)["opensearch"]["username"]
#       opensearch_password = jsondecode(data.aws_secretsmanager_secret_version.this.secret_string)["opensearch"]["password"]
#       opensearch_endpoint = module.opensearch_log.domain_endpoint
#     })
#   ]
# }