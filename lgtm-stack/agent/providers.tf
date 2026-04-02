# 테라폼 백엔드 설정 (실제 배포 시 수정 필요)
terraform {
  backend "s3" {
    region         = "ap-northeast-2"
    bucket         = "your-terraform-state"         # 실제 버킷명으로 변경
    key            = "lgtm-agent/terraform.tfstate"
    dynamodb_table = "your-terraform-lock"           # 실제 테이블명으로 변경
    encrypt        = true
  }
}

terraform {
  required_version = ">= 1.13.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.26.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.1.1"
    }
  }
}

provider "aws" {}

# 기존 EKS 클러스터에 연결
provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes = {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["eks", "get-token", "--cluster-name", var.eks_cluster_name]
      command     = "aws"
    }
  }
}
