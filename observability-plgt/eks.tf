# ########################################################
# EKS 클러스터
# ########################################################
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.10.1"

  name               = local.project
  kubernetes_version = var.eks_cluster_version

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.intra_subnets

  endpoint_public_access  = true
  endpoint_private_access = true

  enable_cluster_creator_admin_permissions = true
  node_security_group_tags = {
    "karpenter.sh/discovery" = local.project
  }
  create_node_security_group = true
  enabled_log_types          = []

  addons = {
    vpc-cni = {
      before_compute = true
      most_recent    = true
    }
    kube-proxy = {
      before_compute = true
      most_recent    = true
    }
    coredns = {
      before_compute = true
      most_recent    = true
      configuration_values = jsonencode({
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
        resources = {
          limits = {
            cpu    = "0.25"
            memory = "256M"
          }
          requests = {
            cpu    = "0.25"
            memory = "256M"
          }
        }
      })
    }
  }

  eks_managed_node_groups = {
    system-node = {
      name            = "${local.project_prefix}-system-node"
      use_name_prefix = true
      subnet_ids      = module.vpc.private_subnets

      use_latest_ami_release_version = false
      ami_type                       = "AL2023_x86_64_STANDARD"
      capacity_type                  = "ON_DEMAND"
      instance_types                 = ["t3a.medium"]
      desired_size                   = 2
      min_size                       = 2
      max_size                       = 2

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
    }
  }
}

# 클러스터 ↔ 노드 보안 그룹 간 양방향 통신 허용
resource "aws_security_group_rule" "cluster_to_node_ingress" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "-1"
  source_security_group_id = module.eks.cluster_primary_security_group_id
  security_group_id        = module.eks.node_security_group_id
  description              = "Allow all traffic from cluster primary SG to node SG"
}

resource "aws_security_group_rule" "node_to_cluster_ingress" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "-1"
  source_security_group_id = module.eks.node_security_group_id
  security_group_id        = module.eks.cluster_primary_security_group_id
  description              = "Allow all traffic from node SG to cluster primary SG"
}

# ########################################################
# Karpenter
# ########################################################
data "aws_iam_policy_document" "karpenter_controller_assume_role_policy" {
  statement {
    effect = "Allow"
    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:sub"
      values   = ["system:serviceaccount:karpenter:karpenter"]
    }
    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
    actions = ["sts:AssumeRoleWithWebIdentity"]
  }
}

resource "kubernetes_namespace_v1" "karpenter" {
  metadata {
    name = "karpenter"
  }
}

module "karpenter" {
  source    = "terraform-aws-modules/eks/aws//modules/karpenter"
  version   = "21.10.1"
  namespace = kubernetes_namespace_v1.karpenter.metadata[0].name

  cluster_name                  = module.eks.cluster_name
  node_iam_role_name            = "${module.eks.cluster_name}-node-role"
  node_iam_role_use_name_prefix = false

  create_pod_identity_association = false
  iam_role_source_assume_policy_documents = [
    data.aws_iam_policy_document.karpenter_controller_assume_role_policy.json
  ]

  iam_policy_name            = "KarpenterController-${module.eks.cluster_name}"
  iam_policy_use_name_prefix = false

  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    AmazonEBSCSIDriverPolicy     = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  }

  depends_on = [module.eks]
}

resource "helm_release" "karpenter_crd" {
  name       = "karpenter-crd"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter-crd"
  version    = var.karpenter_chart_version
  namespace  = kubernetes_namespace_v1.karpenter.metadata[0].name
}

resource "helm_release" "karpenter" {
  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = var.karpenter_chart_version
  namespace  = kubernetes_namespace_v1.karpenter.metadata[0].name

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
    controller:
      resources:
        requests:
          cpu: 100m
          memory: 128Mi
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
    helm_release.karpenter_crd,
    module.karpenter
  ]
}

resource "kubectl_manifest" "karpenter_default_node_class" {
  yaml_body = <<-YAML
    apiVersion: karpenter.k8s.aws/v1
    kind: EC2NodeClass
    metadata:
      name: default
    spec:
      amiSelectorTerms:
      - alias: "${var.eks_node_ami_alias_bottlerocket}"
      role: ${module.karpenter.node_iam_role_name}
      subnetSelectorTerms:
      - tags:
          karpenter.sh/discovery: ${module.eks.cluster_name}
      securityGroupSelectorTerms:
      - id: ${module.eks.cluster_primary_security_group_id}
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

  depends_on = [helm_release.karpenter]
}

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
          - key: karpenter.sh/capacity-type
            operator: In
            values: ["spot", "on-demand"]
          - key: karpenter.k8s.aws/instance-family
            operator: In
            values: ["t3", "t3a", "t4g", "c5", "c5a", "c6g", "c6i", "c7g", "c7i", "m5", "m5a", "m6g", "m7g"]
          - key: karpenter.k8s.aws/instance-size
            operator: In
            values: ["large","xlarge"]
          nodeClassRef:
            apiVersion: karpenter.k8s.aws/v1
            kind: EC2NodeClass
            name: "default"
            group: karpenter.k8s.aws
      limits:
        cpu: 32
      disruption:
        consolidationPolicy: WhenEmptyOrUnderutilized
        consolidateAfter: 15m
    YAML

  depends_on = [kubectl_manifest.karpenter_default_node_class]
}

# ########################################################
# EKS Addons
# ########################################################
locals {
  eks_addons = [
    "metrics-server",
    "aws-ebs-csi-driver",
    "eks-pod-identity-agent",
  ]
}

data "aws_eks_addon_version" "this" {
  for_each           = toset(local.eks_addons)
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

  depends_on = [kubectl_manifest.karpenter_default_nodepool]

  timeouts {
    create = "5m"
  }
}

# ########################################################
# Storage Class
# ########################################################
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
  depends_on = [kubernetes_storage_class_v1.ebs_sc]
}

# ########################################################
# AWS Load Balancer Controller
# ########################################################
module "aws_load_balancer_controller_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "2.6.0"

  name                            = "aws-load-balancer-controller"
  attach_aws_lb_controller_policy = true

  associations = {
    aws_load_balancer_controller = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller"
    }
  }
}

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

  depends_on = [kubectl_manifest.karpenter_default_nodepool]
}

# ########################################################
# External DNS
# ########################################################
module "external_dns_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "2.6.0"

  name                          = "external-dns"
  attach_external_dns_policy    = true
  external_dns_hosted_zone_arns = ["${data.aws_route53_zone.this.arn}"]

  associations = {
    external_dns = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "external-dns-sa"
    }
  }

  tags = local.tags
}

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

  depends_on = [kubectl_manifest.karpenter_default_nodepool]
}
