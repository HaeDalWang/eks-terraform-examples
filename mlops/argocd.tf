# GitHub 리포지토리 인증 정보
resource "kubernetes_secret_v1" "github_token" {
  metadata {
    name      = "github"
    namespace = kubernetes_namespace.argocd.metadata[0].name
    labels = {
      "argocd.argoproj.io/secret-type" = "repo-creds"
    }
  }

  data = {
    type     = "git"
    url      = "https://github.com/HaeDalWang"
    username = "HaeDalWang"
    password = var.github_token
  }

  depends_on = [
    helm_release.argocd
  ]
}

# Argo CD에 프로젝트 생성
resource "kubernetes_manifest" "argocd_project" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "AppProject"

    metadata = {
      name      = local.project
      namespace = kubernetes_namespace.argocd.metadata[0].name
      # 해당 프로젝트에 속한 애플리케이션이 존재할 경우 삭제 방지
      finalizers = [
        "resources-finalizer.argocd.argoproj.io"
      ]
    }

    spec = {
      description = "Seungdo TEST EZL 환경"
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
}

# Argo CD 애플리케이션 생성
resource "kubernetes_manifest" "argocd_app" {
  for_each = toset(local.app)

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"

    metadata = {
      name      = "${each.key}-dev"
      namespace = kubernetes_namespace.argocd.metadata[0].name
      finalizers = [
        "resources-finalizer.argocd.argoproj.io"
      ]
    }

    spec = {
      project = kubernetes_manifest.argocd_project.manifest.metadata.name

      source = {
        repoURL        = "https://github.com/HaeDalWang/seungdo-helm-chart.git"
        targetRevision = "HEAD"
        path           = each.key
        helm = {
          releaseName = each.key
          valueFiles = [
            "values_prod.yaml"
          ]
        }
      }

      destination = {
        name      = "in-cluster"
        namespace = "intgapp"
      }

      syncPolicy = {
        syncOptions : ["CreateNamespace=true"]
        automated : {}
      }
    }
  }
}

# Secrets Manager에서 애플리케이션 시크릿 조회
data "aws_secretsmanager_secret" "application" {
  for_each = toset(local.app)
  name     = "${each.key}-secrets"
}

data "aws_secretsmanager_secret_version" "application" {
  for_each  = toset(local.app)
  secret_id = data.aws_secretsmanager_secret.application[each.key].id
}

# 애플리케이션에 부여할 IAM 정책
resource "aws_iam_policy" "application" {
  for_each = toset(local.app)

  name = each.key

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # 암호 정보를 불러올수 있는 권한
      {
        Sid = "secretsmanager"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Effect   = "Allow"
        Resource = [data.aws_secretsmanager_secret_version.application[each.key].arn]
      }
    ]
  })
}

# 애플리케이션에 부여할 IAM 역할 (IRSA용)
resource "aws_iam_role" "application" {
  for_each = toset(local.app)
  name     = "${each.key}-dev-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = module.eks.oidc_provider_arn
        }
        Condition = {
          StringEquals = {
            "${module.eks.oidc_provider}:sub" = "system:serviceaccount:intgapp:${each.key}"
            "${module.eks.oidc_provider}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

# 애플리케이션에 부여할 IAM 역할 정책 연결
resource "aws_iam_role_policy_attachment" "application" {
  for_each = toset(local.app)

  role       = aws_iam_role.application[each.key].name
  policy_arn = aws_iam_policy.application[each.key].arn
}