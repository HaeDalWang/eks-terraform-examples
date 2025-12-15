
# EKS-Addon
locals {
  eks_addons = [
    "metrics-server",
    "aws-ebs-csi-driver",
    "eks-pod-identity-agent",
    # "snapshot-controller"
  ]
}
data "aws_eks_addon_version" "this" {
  for_each = toset(local.eks_addons)

  addon_name         = each.key
  kubernetes_version = module.eks.cluster_version
}
resource "aws_eks_addon" "this" {
  for_each = toset(local.eks_addons)

  cluster_name                = module.eks.cluster_name
  addon_name                  = each.key
  addon_version               = data.aws_eks_addon_version.this[each.key].version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [
    kubectl_manifest.karpenter_default_nodepool
  ]

  timeouts {
    create = "5m"
  }
}

# 기본값 gp3 Delete 스토리지 클래스
resource "kubernetes_storage_class_v1" "ebs_sc" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" : "true"
    }
  }
  storage_provisioner = "ebs.csi.aws.com"
  volume_binding_mode = "WaitForFirstConsumer"
  parameters = {
    type      = "gp3"
    encrypted = "true"
  }
}

# gp3 retain 스토리지 클래스
resource "kubernetes_storage_class_v1" "ebs_sc_retain" {
  metadata {
    name = "gp3-retain"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "false"
    }
  }
  storage_provisioner = "ebs.csi.aws.com"
  reclaim_policy      = "Retain"
  volume_binding_mode = "WaitForFirstConsumer"
  parameters = {
    type      = "gp3"
    encrypted = "true"
  }
}

# 기본값으로 생성된 스토리지 클래스 해제
resource "kubernetes_annotations" "default_storageclass" {
  api_version = "storage.k8s.io/v1"
  kind        = "StorageClass"
  force       = "true"
  metadata {
    name = "gp2"
  }
  annotations = {
    "storageclass.kubernetes.io/is-default-class" = "false"
  }
  depends_on = [
    kubernetes_storage_class_v1.ebs_sc
  ]
}

# AWS Load Balancer Controller에 부여할 IAM 역할 및 Pod Identity Association
module "aws_load_balancer_controller_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "2.2.1" # 최신화 2025년 10월 24일

  name = "aws-load-balancer-controller"

  attach_aws_lb_controller_policy = true

  associations = {
    aws_load_balancer_controller = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller"
      tags = {
        app = "aws-load-balancer-controller"
      }
    }
  }
}

# AWS Load Balancer Controller
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.aws_load_balancer_controller_chart_version
  namespace  = "kube-system"

  values = [
    <<-EOT
    clusterName: ${module.eks.cluster_name}
    serviceAccount:
      create: true
      annotations:
        eks.amazonaws.com/role-arn: ${module.aws_load_balancer_controller_pod_identity.iam_role_arn}
    EOT
  ]

  depends_on = [
    kubectl_manifest.karpenter_default_nodepool
  ]
}

# External DNS Pod Identity
module "external_dns_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "2.2.1" # 최신화 2025년 10월 24일

  name = "external-dns"

  attach_external_dns_policy    = true
  external_dns_hosted_zone_arns = ["${data.aws_route53_zone.this.arn}"]

  association_defaults = {
    namespace       = "kube-system"
    service_account = "external-dns-sa"
  }

  associations = {
    external_dns = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "external-dns-sa"
      tags = {
        app = "external-dns"
      }
    }
  }

  tags = local.tags
}

# External DNS
resource "helm_release" "external_dns" {
  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns"
  chart      = "external-dns"
  version    = var.external_dns_chart_version
  namespace  = "kube-system"

  values = [
    <<-EOT
    serviceAccount:
      create: true
      name: external-dns-sa
      annotations:
        eks.amazonaws.com/role-arn: ${module.external_dns_pod_identity.iam_role_arn}
    txtOwnerId: ${module.eks.cluster_name}
    policy: sync
    sources:
      - service
      - ingress
      - traefik-proxy
    extraArgs:
      - --annotation-filter=external-dns.alpha.kubernetes.io/exclude notin (true)
    env:
      - name: AWS_REGION
        value: ${data.aws_region.current.id}
    EOT
  ]

  depends_on = [
    kubectl_manifest.karpenter_default_nodepool
  ]
}

# External DNS RBAC for Traefik Proxy
# 참고: https://kubernetes-sigs.github.io/external-dns/v0.14.1/tutorials/traefik-proxy/
resource "kubernetes_cluster_role_v1" "external_dns_traefik_proxy" {
  metadata {
    name = "external-dns-traefik-proxy-reader"
  }

  rule {
    api_groups = ["traefik.containo.us", "traefik.io"]
    resources  = ["ingressroutes", "ingressroutetcps", "ingressrouteudps"]
    verbs      = ["get", "watch", "list"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "external_dns_traefik_proxy" {
  metadata {
    name = "external-dns-traefik-proxy-reader"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.external_dns_traefik_proxy.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = "external-dns-sa"
    namespace = "kube-system"
  }

  depends_on = [
    helm_release.external_dns
  ]
}