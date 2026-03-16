
# External DNS Pod Identity
module "external_dns_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "2.6.0" # 최신화 2026년 3월 16일

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

  # source의 api로 없는걸 넣으면 애초에 Pod가 죽으므로 정말로 쓸것만 명시해야합니다
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
      - gateway-httproute
    extraArgs:
      - --annotation-filter=external-dns.alpha.kubernetes.io/exclude notin (true)
    env:
      - name: AWS_REGION
        value: ${data.aws_region.current.id}
    rbac:
      create: true
    EOT
  ]

  depends_on = [
    kubectl_manifest.karpenter_default_nodepool
  ]
}