# 요구되는 테라폼 제공자 목록
terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.56.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.31.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.14.0"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = ">= 2.0.4"
    }
    htpasswd = {
      source  = "loafoe/htpasswd"
      version = ">= 1.0.4"
    }
    keycloak = {
      source  = "mrparkers/keycloak"
      version = ">= 4.4.0"
    }
    http = {
      source  = "hashicorp/http"
      version = ">= 3.4.4"
    }
  }
}

# # 테라폼 백엔드 설정
# terraform {
#   backend "s3" {
#     region         = "ap-northeast-2"
#     bucket         = "Change ME!"
#     key            = "Change ME!/terraform.tfstate"
#     dynamodb_table = "Change ME!"
#     encrypt        = true
#     assume_role = {
#       role_arn = "Change ME!"
#     }
#   }
# }

# AWS 제공자 설정
provider "aws" {
  # 별도의 Role을 Assume 하여 관리할 경우 사용
  # assume_role {
  #   role_arn = "Change ME!"
  # }

  # 해당 테라폼 모듈을 통해서 생성되는 모든 AWS 리소스에 아래의 태그 부여
  default_tags {
    tags = local.tags
  }
}

# Kubernetes 제공자 설정
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
}

# Helm 제공자 설정
provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
  debug = true
}

# Kubectl 제공자 설정
provider "kubectl" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
  load_config_file       = false
}

# # Keycloak 제공자
# provider "keycloak" {
#   client_id = "admin-cli"
#   username  = jsondecode(data.aws_secretsmanager_secret_version.this.secret_string)["keycloak"]["username"]
#   password  = jsondecode(data.aws_secretsmanager_secret_version.this.secret_string)["keycloak"]["password"]
#   url       = "https://${data.kubernetes_ingress_v1.keycloak.spec[0].rule[0].host}"
# }