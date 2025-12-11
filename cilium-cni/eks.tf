# EKS 클러스터
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.10.1" # 최신화 2025년 12월 11일

  name               = local.project
  kubernetes_version = var.eks_cluster_version

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.intra_subnets

  endpoint_public_access  = true
  endpoint_private_access = true

  # 클러스터를 생성한 IAM 객체에서 쿠버네티스 어드민 권한 할당
  enable_cluster_creator_admin_permissions = true
  # Nodepool에서 태그기반으로도 가져갈 수 있도록 선언
  node_security_group_tags = {
    "karpenter.sh/discovery" = local.project
  }
  # 노드 보안그룹 생성
  create_node_security_group = true

  # 로깅 비활성화 - 변수처리
  enabled_log_types = []
}

# EKS 클러스터 버전에 맞는 CoreDNS 애드온 버전 불러오기
data "aws_eks_addon_version" "coredns" {
  addon_name         = "coredns"
  kubernetes_version = module.eks.cluster_version
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = module.eks.cluster_name
  addon_name                  = "coredns"
  addon_version               = data.aws_eks_addon_version.coredns.version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  configuration_values = jsonencode({
    # 전용 노드 그룹에만 스케줄
    nodeSelector = {
      workload  = "system"
      nodegroup = "system"
    }
    tolerations = [
      {
        key      = "workload"
        operator = "Equal"
        value    = "system"
        effect   = "NoSchedule"
      }
    ]
  })

  depends_on = [
    module.eks
  ]
}

# Cilium CNI 애드온 생성
resource "helm_release" "cilium" {
  name       = "cilium"
  repository = "https://helm.cilium.io/"
  chart      = "cilium"
  version    = var.cilium_chart_version
  namespace  = "kube-system"

  values = [
    templatefile("${path.module}/helm-values/cilium.yaml", {
      k8sServiceHost = replace(module.eks.cluster_endpoint, "https://", "")
    })
  ]

  # Cilium CNI 애드온 생성 시 파드 Ready 기다리지 말고, 리소스 생성되면 바로 완료로 처리
  wait    = false # 파드 Ready 기다리지 말고, 리소스 생성되면 바로 완료로 처리
  timeout = 600   # 혹시라도 API 응답 지연 대비

  depends_on = [
    module.eks
  ]
}

module "eks_managed_node_group" {
  source  = "terraform-aws-modules/eks/aws//modules/eks-managed-node-group"
  version = "21.10.1" # 최신화 2025년 12월 11일

  name                 = "system"
  cluster_name         = module.eks.cluster_name
  kubernetes_version   = module.eks.cluster_version
  cluster_endpoint     = module.eks.cluster_endpoint
  cluster_auth_base64  = module.eks.cluster_certificate_authority_data
  cluster_service_cidr = module.eks.cluster_service_cidr

  subnet_ids                        = module.vpc.private_subnets
  cluster_primary_security_group_id = module.eks.cluster_primary_security_group_id
  vpc_security_group_ids            = [module.eks.node_security_group_id]

  ami_type       = "AL2023_x86_64_STANDARD"
  capacity_type  = "ON_DEMAND"
  instance_types = ["t3a.small"]
  desired_size   = 2
  min_size       = 2
  max_size       = 2

  # --- IAM Role 생성 + 기본 EKS 노드 정책 부착 ---
  create_iam_role = true
  iam_role_attach_cni_policy = true
  iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  # 시스템 워크로드만 스케줄되도록 테인트
  labels = {
    workload  = "system"
    nodegroup = "system"
  }
  taints = {
    workload = {
      key    = "workload"
      value  = "system"
      effect = "NO_SCHEDULE"
    }
  }

  tags = local.tags

  depends_on = [
    helm_release.cilium
  ]
}

# Karpenter를 배포할 네임 스페이스
resource "kubernetes_namespace" "karpenter" {
  metadata {
    name = "karpenter"
  }
}

# Karpenter 구성에 필요한 AWS 리소스 생성
module "karpenter" {
  source    = "terraform-aws-modules/eks/aws//modules/karpenter"
  version   = "21.6.1" # 최신화 2025년 10월 23일
  namespace = kubernetes_namespace.karpenter.metadata[0].name

  cluster_name                  = module.eks.cluster_name
  node_iam_role_name            = "${module.eks.cluster_name}-node-role"
  node_iam_role_use_name_prefix = false

  # Pod Identity는 Fargate을 지원하지 않음
  create_pod_identity_association = false

  # Controller IAM Policy 이름 고정 (IRSA에서 참조하기 위해)
  iam_policy_name            = "KarpenterController-${module.eks.cluster_name}"
  iam_policy_use_name_prefix = false

  # Karpenter가 생성할 노드에 부여할 역할에 기본 정책 이외에 추가할 IAM 정책
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    AmazonEBSCSIDriverPolicy     = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  }

  # Delete시 Coredns가 마지막으로 삭제되도록 의존성 추가
  depends_on = [
    module.eks
    # aws_eks_addon.coredns
  ]
}

# Karpenter module이 생성한 Controller IAM Policy 조회
data "aws_iam_policy" "karpenter_controller" {
  name = "KarpenterController-${module.eks.cluster_name}"

  depends_on = [module.karpenter]
}

# Karpenter IRSA
module "karpenter_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "6.2.2" # 최신화 2025년 10월 23일

  name = "KarpenterController-${module.eks.cluster_name}-irsa"

  # Karpenter module이 생성한 policy를 재사용
  policies = {
    karpenter = data.aws_iam_policy.karpenter_controller.arn
  }

  oidc_providers = {
    cotong = {
      provider_arn = module.eks.oidc_provider_arn
      namespace_service_accounts = [
        "karpenter:karpenter"
      ]
    }
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
        eks.amazonaws.com/role-arn: ${module.karpenter_irsa.arn}
    controller:
      resources:
        requests:
          cpu: 200m
          memory: 250Mi
    nodeSelector:
      workload: system
      nodegroup: system
    tolerations:
      - key: workload
        operator: Equal
        value: system
        effect: NoSchedule
    EOT
  ]

  depends_on = [
    helm_release.karpenter-crd,
    module.karpenter_irsa
  ]
}

# Karpenter 기본 노드 클래스
# - id: ${module.eks.cluster_primary_security_group_id}

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
      - tags:
          karpenter.sh/discovery: ${module.eks.cluster_name}
      securityGroupSelectorTerms:
      - id: ${module.eks.node_security_group_id}
      blockDeviceMappings:
      - deviceName: /dev/xvda
        ebs:
          volumeSize: 20Gi
          volumeType: gp3
          encrypted: true
      metadataOptions:
        httpEndpoint: enabled
        httpTokens: optional
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
            values: ["amd64", "arm64"]
          - key: kubernetes.io/os
            operator: In
            values: ["linux"]
          - key: topology.kubernetes.io/zone
            operator: In
            values: ["ap-northeast-2a", "ap-northeast-2b", "ap-northeast-2c", "ap-northeast-2d"]
          - key: karpenter.sh/capacity-type
            operator: In
            values: ["spot", "on-demand"]
          - key: karpenter.k8s.aws/instance-family
            operator: In
            values: ["t3", "t3a", "t4g", "c5", "c5a", "c6g", "c6i", "c7g", "c7i", "m5", "m5a", "m6g", "m7g"]
          - key: karpenter.k8s.aws/instance-size
            operator: In
            values: ["medium", "large"]
          nodeClassRef:
            apiVersion: karpenter.k8s.aws/v1
            kind: EC2NodeClass
            name: "default"
            group: karpenter.k8s.aws
          taints:
          - key: "node.cilium.io/agent-not-ready"
            value: "true"
            effect: "NoExecute"
      limits:
        cpu: 10
      disruption:
        consolidationPolicy: WhenEmptyOrUnderutilized 
        consolidateAfter: 30s
    YAML

  depends_on = [
    kubectl_manifest.karpenter_default_node_class
  ]
}