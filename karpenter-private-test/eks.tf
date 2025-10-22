# EKS 클러스터
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  # version = "19.15"
  version = "21.3.1"

  authentication_mode = "API_AND_CONFIG_MAP"

  name    = local.project
  # cluster_version = var.eks_cluster_version
  kubernetes_version = var.eks_cluster_version

  vpc_id = module.vpc.vpc_id
  # 노드그룹을 사용할 경우 노드가 생성되는 서브넷
  subnet_ids = module.vpc.private_subnets
  # 컨트롤 플레인으로 연결된 ENI를 생성할 서브넷
  control_plane_subnet_ids        = module.vpc.intra_subnets
  endpoint_public_access  = true
  endpoint_private_access = false

  # 클러스터를 생성한 IAM 객체에서 쿠버네티스 어드민 권한 할당
  enable_cluster_creator_admin_permissions = true

  # 노드그룹을 사용하지 않기 때문에 노드 그룹용 보인그룹 미생성
  create_node_security_group = false

  fargate_profiles = {
    # Karpenter를 Fargate에 실행
    karpenter = {
      selectors = [
        {
          namespace = "karpenter"
        }
      ]
    }
    # CoreDNS를 Fargate에 실행
    coredns = {
      selectors = [
        {
          namespace = "kube-system"
          labels = {
            "k8s-app" = "kube-dns"
          }
        }
      ]
    }
  }

  # 로깅 비활성화 - 변수처리
  enabled_log_types = []
}

# EKS 클러스터 버전에 맞는 CoreDNS 애드온 버전 불러오기
data "aws_eks_addon_version" "coredns" {
  addon_name         = "coredns"
  kubernetes_version = module.eks.cluster_version
}

# CoreDNS - 먼저 생성하지 않으면 Karpenter가 작동을안함 > 노드가없음 > 나머지가 안뜸
resource "aws_eks_addon" "coredns" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "coredns"
  addon_version               = data.aws_eks_addon_version.coredns.version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  configuration_values = jsonencode({
    # Karpenter가 실행되려면 CoreDNS가 필수 구성요소기 때문에 Fargate에 배포
    computeType = "Fargate"
  })

  depends_on = [
    module.eks.fargate_profiles
  ]
}
# EKS Access Entries를 사용한 액세스 관리 (권장 방식)
# aws-auth ConfigMap 대신 AWS의 새로운 액세스 관리 방식 사용
resource "aws_eks_access_entry" "karpenter_node_role" {
  cluster_name      = module.eks.cluster_name
  principal_arn     = module.karpenter.node_iam_role_arn
  type              = "EC2_LINUX"
  kubernetes_groups = ["system:bootstrappers", "system:nodes"]

  depends_on = [
    module.eks,
    module.karpenter
  ]
}

# Karpenter 노드 역할에 필요한 권한 부여
resource "aws_eks_access_policy_association" "karpenter_node_role" {
  cluster_name  = module.eks.cluster_name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSNodeRolePolicy"
  principal_arn = module.karpenter.node_iam_role_arn

  access_scope {
    type = "cluster"
  }

  depends_on = [
    aws_eks_access_entry.karpenter_node_role
  ]
}
# Karpenter 구성에 필요한 AWS 리소스 생성
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "21.3.1"

  cluster_name                  = module.eks.cluster_name
  node_iam_role_name            = "${module.eks.cluster_name}-node-role"
  node_iam_role_use_name_prefix = false

  # Karpenter 1.0 이상 버전에 필요한 policy를 사용하도록 설정 (공식문서 input에 없음 주의)
  # enable_v1_permissions = true
  # Karpenter에 부여할 IAM 역할 생성
  # enable_irsa            = true
  # irsa_oidc_provider_arn = module.eks.oidc_provider_arn

  # Karpenter가 생성할 노드에 부여할 역할에 기본 정책 이외에 추가할 IAM 정책
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    AmazonEBSCSIDriverPolicy     = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  }
}

# Karpenter를 배포할 네임 스페이스
resource "kubernetes_namespace" "karpenter" {
  metadata {
    name = "karpenter"
  }
}

# Karpenter CRDs
# 분리해서 설치 시 karpenter chart에서 "skip_crds = true" 옵션 사용 필수
resource "helm_release" "karpenter-crd" {
  name       = "karpenter-crd"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter-crd"
  version    = var.karpenter_chart_version
  namespace  = kubernetes_namespace.karpenter.metadata[0].name
}

# Karpenter 메인 차트
resource "helm_release" "karpenter" {
  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = var.karpenter_chart_version
  namespace  = kubernetes_namespace.karpenter.metadata[0].name

  skip_crds = true

  values = [
    <<-EOT
    settings:
      clusterName: ${module.eks.cluster_name}
      clusterEndpoint: ${module.eks.cluster_endpoint}
      interruptionQueue: ${module.karpenter.queue_name}
      featureGates:
        spotToSpotConsolidation: true
    serviceAccount:
      annotations:
        eks.amazonaws.com/role-arn: ${module.karpenter.iam_role_arn}
    serviceMonitor:
      enabled: true
    controller:
      resources:
        requests:
          cpu: 256m
          memory: 256Mi
    EOT
  ]
}

# Karpenter 기본 노드 클래스
resource "kubectl_manifest" "karpenter_default_node_class" {
  yaml_body = <<-YAML
    apiVersion: karpenter.k8s.aws/v1
    kind: EC2NodeClass
    metadata:
      name: default
    spec:
      amiSelectorTerms:
      - alias: "${var.eks_node_ami_alias_al2023}"
      role: ${module.karpenter.node_iam_role_name}
      subnetSelectorTerms:
      - id: ${module.vpc.private_subnets[0]}
      - id: ${module.vpc.private_subnets[1]}
      securityGroupSelectorTerms:
      - id: ${module.eks.cluster_primary_security_group_id}
      blockDeviceMappings:
      - deviceName: /dev/xvda
        ebs:
          volumeSize: 20Gi
          volumeType: gp3
          encrypted: true
      metadataOptions:
        httpPutResponseHopLimit: 2
      tags:
        ${jsonencode(local.tags)}
    YAML

  depends_on = [
    helm_release.karpenter
  ]
}

# Karpenter 기본 노드 풀
resource "kubectl_manifest" "karpenter_default_nodepool" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1
    kind: NodePool
    metadata:
      name: default
    spec:
      template:
        spec:
          expireAfter: 720h
          requirements:
          - key: kubernetes.io/arch
            operator: In
            values: ["amd64"]
          - key: kubernetes.io/os
            operator: In
            values: ["linux"]
          - key: karpenter.sh/capacity-type
            operator: In
            values: ["spot", "on-demand"]
          - key: node.kubernetes.io/instance-type
            operator: In
            values: [ "t3.medium", "t3a.medium","c5.large", "c5a.large"]
          nodeClassRef:
            apiVersion: karpenter.k8s.aws/v1
            kind: EC2NodeClass
            name: "default"
            group: karpenter.k8s.aws
      limits:
        cpu: 1000
      disruption:
        consolidationPolicy: WhenEmptyOrUnderutilized 
        consolidateAfter: 30s
    YAML

  depends_on = [
    kubectl_manifest.karpenter_default_node_class
  ]
}

# EKS-Addon
locals {
  eks_addons = [
    "kube-proxy",
    "vpc-cni",
    # "metrics-server",
    # "aws-ebs-csi-driver",
    # "eks-pod-identity-agent",
    # "external-dns"
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

# # EBS CSI 드라이버를 사용하는 스토리지 클래스
# resource "kubernetes_storage_class" "ebs_sc" {
#   # EBS CSI 드라이버가 EKS Addon을 통해서 생성될 경우
#   # count = lookup(module.eks.cluster_addons, "aws-ebs-csi-driver", null) != null ? 1 : 0

#   metadata {
#     name = "ebs-sc"
#     annotations = {
#       "storageclass.kubernetes.io/is-default-class" : "true"
#     }
#   }
#   storage_provisioner = "ebs.csi.aws.com"
#   volume_binding_mode = "WaitForFirstConsumer"
#   parameters = {
#     type      = "gp3"
#     encrypted = "true"
#   }
# }

# # 기본값으로 생성된 스토리지 클래스 해제
# resource "kubernetes_annotations" "default_storageclass" {
#   # count = lookup(module.eks.cluster_addons, "aws-ebs-csi-driver", null) != null ? 1 : 0

#   api_version = "storage.k8s.io/v1"
#   kind        = "StorageClass"
#   force       = "true"

#   metadata {
#     name = "gp2"
#   }
#   annotations = {
#     "storageclass.kubernetes.io/is-default-class" = "false"
#   }

#   depends_on = [
#     kubernetes_storage_class.ebs_sc
#   ]
# }
