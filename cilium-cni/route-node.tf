# # Router 노드 풀
# # Traefik, Envoy Gateway 등 Ingress Controller를 위한 전용 노드 풀
# # nodeSelector.role: router를 사용하여 이 노드 풀에만 스케줄링되도록 설정
# # 퍼블릭 서브넷에 배포되어 NodePort로 외부 접근 가능

# # Karpenter Router 전용 EC2NodeClass (퍼블릭 서브넷)
# # NodePort 서비스를 외부에서 접근하기 위해 퍼블릭 서브넷에 배포
# resource "kubectl_manifest" "karpenter_router_node_class" {
#   yaml_body = <<-YAML
#     apiVersion: karpenter.k8s.aws/v1
#     kind: EC2NodeClass
#     metadata:
#       name: router
#     spec:
#       amiSelectorTerms:
#       - alias: "${var.eks_node_ami_alias_al2023}"
#       role: ${module.karpenter.node_iam_role_name}
#       # 퍼블릭 서브넷 선택: kubernetes.io/role/elb 태그 사용
#       subnetSelectorTerms:
#       - tags:
#           kubernetes.io/role/elb: "1"
#       # 퍼블릭 서브넷에서 EKS API 접근을 위해 퍼블릭 IP 필요
#       associatePublicIPAddress: true
#       securityGroupSelectorTerms:
#       - id: ${module.eks.node_security_group_id}
#       blockDeviceMappings:
#       - deviceName: /dev/xvda
#         ebs:
#           volumeSize: 20Gi
#           volumeType: gp3
#           encrypted: true
#       metadataOptions:
#         httpEndpoint: enabled
#         httpTokens: optional
#         httpPutResponseHopLimit: 2
#       tags:
#         ${jsonencode(merge(local.tags, { role = "router" }))}
#     YAML

#   depends_on = [
#     helm_release.karpenter
#   ]
# }

# # Karpenter Router 노드 풀
# # router EC2NodeClass를 사용하여 퍼블릭 서브넷에 노드 생성
# resource "kubectl_manifest" "karpenter_router_nodepool" {
#   yaml_body = <<-YAML
#     apiVersion: karpenter.sh/v1
#     kind: NodePool
#     metadata:
#       name: router
#     spec:
#       template:
#         spec:
#           # 노드 라벨: nodeSelector.role: router로 사용 가능
#           labels:
#             role: router
#           expireAfter: 720h
#           requirements:
#           # role 라벨을 requirements에 추가해야 Karpenter가 nodeSelector 인식
#           - key: role
#             operator: In
#             values: ["router"]
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
#             values: ["spot"]  # Router 노드는 안정성을 위해 on-demand만 사용
#           - key: karpenter.k8s.aws/instance-family
#             operator: In
#             values: ["t3", "t3a", "t4g", "c5", "c5a", "c6g", "c6i", "c7g", "c7i", "m5", "m5a", "m6g", "m7g"]
#           - key: karpenter.k8s.aws/instance-size
#             operator: In
#             values: ["large", "xlarge", "2xlarge"]  # Router 노드는 더 큰 인스턴스 사용 가능
#           nodeClassRef:
#             apiVersion: karpenter.k8s.aws/v1
#             kind: EC2NodeClass
#             name: "router"  # 퍼블릭 서브넷용 router EC2NodeClass 사용
#             group: karpenter.k8s.aws
#           # Router 전용 노드: taint로 다른 워크로드 차단
#           taints:
#           - key: "role"
#             value: "router"
#             effect: "NoSchedule"
#       limits:
#         cpu: 4  # Router 노드 풀의 최대 CPU 제한
#       disruption:
#         consolidationPolicy: WhenEmptyOrUnderutilized
#         consolidateAfter: 3s
#     YAML

#   depends_on = [
#     kubectl_manifest.karpenter_router_node_class
#   ]
# }

# # Router 노드 생성을 위한 싱글톤 파드
# # Karpenter가 router 노드를 프로비저닝하도록 트리거
# resource "kubectl_manifest" "router_singleton_pod" {
#   yaml_body = <<-YAML
#     apiVersion: apps/v1
#     kind: Deployment
#     metadata:
#       name: router-singleton
#       namespace: default
#     spec:
#       replicas: 1
#       selector:
#         matchLabels:
#           app: router-singleton
#       template:
#         metadata:
#           labels:
#             app: router-singleton
#         spec:
#           # router 노드에만 스케줄링
#           nodeSelector:
#             role: router
#           tolerations:
#           # Router 노드 taint 허용
#           - key: "role"
#             operator: "Equal"
#             value: "router"
#             effect: "NoSchedule"
#           containers:
#           - name: pause
#             image: registry.k8s.io/pause:3.9
#             resources:
#               requests:
#                 cpu: 100m
#                 memory: 128Mi
#     YAML

#   depends_on = [
#     kubectl_manifest.karpenter_router_nodepool
#   ]
# }
