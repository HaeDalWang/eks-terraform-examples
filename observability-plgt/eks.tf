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

# EKS 클러스터 생성 직후 enable_cluster_creator_admin_permissions로 만들어지는
# access entry가 API 서버에 전파되기까지 시간이 걸려서, 바로 붙는 Kubernetes
# provider 리소스(namespace, storageclass 등)가 "forbidden" 에러로 실패하는 경우가 있음.
# 전파 시간을 벌기 위해 30초 대기.
resource "time_sleep" "wait_for_cluster_access" {
  depends_on      = [module.eks]
  create_duration = "30s"
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

  depends_on = [time_sleep.wait_for_cluster_access]
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

# Karpenter 노드 자동 drain (destroy 데드락 방지)
#
# Karpenter가 동적 생성하는 NodeClaim/EC2 인스턴스는 Terraform 리소스가 아니라 그래프가 모릅니다.
# NodeClaim에는 karpenter.sh/termination finalizer가 붙어 있어, destroy 시 karpenter 컨트롤러가
# 죽은 뒤에는 finalizer가 풀리지 않아 karpenter-crd 삭제가 stuck되고, EC2 인스턴스도 orphan으로
# 남아 VPC 삭제까지 막습니다.
#
# 이 null_resource를 karpenter helm/nodepool 뒤에 생성 → destroy 시 가장 먼저 실행되어
# 컨트롤러가 살아있는 동안 NodeClaim을 정상 삭제(=EC2도 함께 종료)합니다.
# CONVENTIONS.md "규칙 3 (컨트롤러 예외: karpenter)" 참조.
resource "null_resource" "drain_karpenter_nodes" {
  triggers = {
    cluster_name = module.eks.cluster_name
    region       = data.aws_region.current.id
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      aws eks update-kubeconfig --name ${self.triggers.cluster_name} --region ${self.triggers.region}
      kubectl delete nodeclaims --all --timeout=300s || true
    EOT
  }

  depends_on = [
    kubectl_manifest.karpenter_default_nodepool,
    helm_release.karpenter,
  ]
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

# EBS CSI 드라이버 정리 대기 (destroy 시 볼륨 unmount 데드락 방지)
#
# loki/tempo/prometheus/grafana/thanos는 gp3 PVC를 사용합니다. destroy 시 CSI 드라이버가
# 워크로드보다 먼저 삭제되면 볼륨 detach가 안 돼 Pod가 Terminating에 걸리고 helm uninstall이
# 무한 대기합니다. 이 time_sleep을 CSI addon과 storageclass 사이에 끼워 삭제 순서를
# "PVC 워크로드 삭제 → 120s 대기(CSI 생존) → CSI addon 삭제"로 강제합니다.
# 생성 시에도 "CSI addon → storageclass" 순서를 보장합니다.
resource "time_sleep" "wait_for_ebs_csi" {
  depends_on       = [aws_eks_addon.this["aws-ebs-csi-driver"]]
  destroy_duration = "120s"
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

  depends_on = [time_sleep.wait_for_ebs_csi]
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

# external-dns 레코드 정리 대기 (destroy 시 Route53 orphan 레코드 방지)
#
# external-dns(policy: sync)는 HTTPRoute가 사라지면 대응 Route53 레코드를 삭제합니다.
# destroy 시 external-dns가 HTTPRoute보다 먼저 죽으면 grafana DNS 레코드가 orphan으로 남습니다.
# 이 time_sleep을 external_dns helm과 httproute 사이에 끼워 삭제 순서를
# "HTTPRoute 삭제 → 60s 대기(external-dns가 레코드 sync 삭제) → external_dns helm 삭제"로 강제합니다.
resource "time_sleep" "wait_for_dns_cleanup" {
  depends_on       = [helm_release.external_dns]
  destroy_duration = "60s"
}
