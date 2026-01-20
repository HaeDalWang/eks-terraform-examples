# # Karpenter RMQ 노드 풀 1: node-group: rmq 라벨
# resource "kubectl_manifest" "karpenter_rmq_nodepool_1" {
#   yaml_body = <<-YAML
#     apiVersion: karpenter.sh/v1
#     kind: NodePool
#     metadata:
#       name: rmq-nodepool-1
#     spec:
#       template:
#         metadata:
#           labels:
#             node-group: rmq
#         spec:
#           expireAfter: 720h
#           requirements:
#           - key: kubernetes.io/arch
#             operator: In
#             values: ["amd64", "arm64"]
#           - key: kubernetes.io/os
#             operator: In
#             values: ["linux"]
#           - key: topology.kubernetes.io/zone
#             operator: In
#             values: ["ap-northeast-2a", "ap-northeast-2b", "ap-northeast-2c", "ap-northeast-2d"]
#           - key: karpenter.sh/capacity-type
#             operator: In
#             values: ["spot", "on-demand"]
#           - key: karpenter.k8s.aws/instance-family
#             operator: In
#             values: ["t3", "t3a", "t4g", "c5", "c5a", "c6g", "c6i", "c7g", "c7i", "m5", "m5a", "m6g", "m7g"]
#           - key: karpenter.k8s.aws/instance-size
#             operator: In
#             values: ["large","xlarge"]
#           nodeClassRef:
#             apiVersion: karpenter.k8s.aws/v1
#             kind: EC2NodeClass
#             name: "default"
#             group: karpenter.k8s.aws
#       limits:
#         cpu: 2
#       disruption:
#         consolidationPolicy: WhenEmptyOrUnderutilized 
#         consolidateAfter: 10s
#     YAML

#   depends_on = [
#     kubectl_manifest.karpenter_default_node_class
#   ]
# }

# # Karpenter RMQ 노드 풀 2: rmq: true 라벨
# resource "kubectl_manifest" "karpenter_rmq_nodepool_2" {
#   yaml_body = <<-YAML
#     apiVersion: karpenter.sh/v1
#     kind: NodePool
#     metadata:
#       name: rmq-nodepool-2
#     spec:
#       template:
#         metadata:
#           labels:
#             rmq: "true"
#         spec:
#           expireAfter: 720h
#           requirements:
#           - key: kubernetes.io/arch
#             operator: In
#             values: ["amd64", "arm64"]
#           - key: kubernetes.io/os
#             operator: In
#             values: ["linux"]
#           - key: topology.kubernetes.io/zone
#             operator: In
#             values: ["ap-northeast-2a", "ap-northeast-2b", "ap-northeast-2c", "ap-northeast-2d"]
#           - key: karpenter.sh/capacity-type
#             operator: In
#             values: ["spot", "on-demand"]
#           - key: karpenter.k8s.aws/instance-family
#             operator: In
#             values: ["t3", "t3a", "t4g", "c5", "c5a", "c6g", "c6i", "c7g", "c7i", "m5", "m5a", "m6g", "m7g"]
#           - key: karpenter.k8s.aws/instance-size
#             operator: In
#             values: ["large","xlarge"]
#           nodeClassRef:
#             apiVersion: karpenter.k8s.aws/v1
#             kind: EC2NodeClass
#             name: "default"
#             group: karpenter.k8s.aws
#       limits:
#         cpu: 2
#       disruption:
#         consolidationPolicy: WhenEmptyOrUnderutilized 
#         consolidateAfter: 10s
#     YAML

#   depends_on = [
#     kubectl_manifest.karpenter_default_node_class
#   ]
# }

# # RabbitMQ 네임스페이스
# resource "kubernetes_namespace_v1" "rabbitmq" {
#   metadata {
#     name = "rabbitmq"
#   }
# }

# RabbitMQ Helm 차트 설치
# # ref: https://artifacthub.io/packages/helm/bitnami/rabbitmq
# resource "helm_release" "rabbitmq" {
#   name       = "rabbitmq"
#   repository = "https://charts.bitnami.com/bitnami"
#   chart      = "rabbitmq"
#   version    = "16.0.14"
#   namespace  = kubernetes_namespace_v1.rabbitmq.metadata[0].name

#   values = [
#     <<-EOT
#     replicaCount: 3
#     nodeSelector:
#       rmq: "true"
#     global:
#       security:
#         allowInsecureImages: true
#     image:
#       registry: docker.io
#       repository: bitnamilegacy/rabbitmq
#       tag: "4.1.3-debian-12-r1"
#     EOT
#   ]
  
#   depends_on = [
#     kubectl_manifest.karpenter_rmq_nodepool_1
#   ]
# }
