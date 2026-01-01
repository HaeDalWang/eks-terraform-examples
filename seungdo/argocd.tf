
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
resource "kubernetes_manifest" "argocd_project" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "AppProject"

    metadata = {
      name      = local.project
      namespace = kubernetes_namespace_v1.argocd.metadata[0].name
      # 해당 프로젝트에 속한 애플리케이션이 존재할 경우 삭제 방지
      finalizers = [
        "resources-finalizer.argocd.argoproj.io"
      ]
    }

    spec = {
      description = "${local.project} 환경"
      sourceRepos = ["*"]
      destinations = [
        {
          name      = "*"
          server    = "*"
          namespace = "*"
        }
      ]
      clusterResourceWhitelist = [
        {
          group = "*"
          kind  = "*"
        }
      ]
    }
  }

  depends_on = [
    helm_release.argocd
  ]
}

# Argo CD 애플리케이션 생성 (ingress-controller-test.git)
resource "kubernetes_manifest" "argocd_app_ingress_nginx" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"

    metadata = {
      name      = "ingress-echo-alb"
      namespace = kubernetes_namespace_v1.argocd.metadata[0].name
      finalizers = [
        "resources-finalizer.argocd.argoproj.io"
      ]
    }

    spec = {
      project = kubernetes_manifest.argocd_project.manifest.metadata.name

      sources = [
        {
          repoURL        = "https://github.com/HaeDalWang/ingress-controller-test.git"
          targetRevision = "HEAD"
          path           = "chart"
          helm = {
            releaseName = "ingress-echo-alb"
            valueFiles = [
              "values_alb.yaml"
            ]
          }
        }
      ]

      destination = {
        name      = "in-cluster"
        namespace = "app"
      }

      syncPolicy = {
        syncOptions : ["CreateNamespace=true"]
        automated : {}
      }
    }
  }

  depends_on = [
    helm_release.argocd,
    kubernetes_manifest.argocd_project
  ]
}