# Router 노드 풀
# Traefik, Envoy Gateway 등 Ingress Controller를 위한 전용 노드 풀
# nodeSelector.role: router를 사용하여 이 노드 풀에만 스케줄링되도록 설정
# 퍼블릭 서브넷에 배포되어 NodePort로 외부 접근 가능

# Karpenter Router 전용 EC2NodeClass (퍼블릭 서브넷)
# NodePort 서비스를 외부에서 접근하기 위해 퍼블릭 서브넷에 배포
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

# # 라우터 노드 ip 로컬 변수 설정 (우선 수동으로)
# locals {
#   router_node_ip = "10.123.3.87"
# }

# # 물리 장비 대체용 NLB
# module "nlb" {
#   source  = "terraform-aws-modules/alb/aws"
#   version = "10.4.0"

#   name               = "contentree-nlb"
#   load_balancer_type = "network"
#   vpc_id             = module.vpc.vpc_id
#   subnets            = module.vpc.public_subnets
  
#   # 테스트 환경이므로 삭제 방지 비활성화
#   enable_deletion_protection = false

#   # Security Group
#   enforce_security_group_inbound_rules_on_private_link_traffic = "on"
#   security_group_ingress_rules = {
#     all_http = {
#       from_port   = 80
#       to_port     = 80
#       ip_protocol = "tcp"
#       description = "HTTP web traffic"
#       cidr_ipv4   = "0.0.0.0/0"
#     }
#     all_https = {
#       from_port   = 443
#       to_port     = 443
#       ip_protocol = "tcp"
#       description = "HTTPS web traffic"
#       cidr_ipv4   = "0.0.0.0/0"
#     }
#     all_9443 = {
#       from_port   = 9443
#       to_port     = 9443
#       ip_protocol = "tcp"
#       description = "Custom 9443 traffic"
#       cidr_ipv4   = "0.0.0.0/0"
#     }
#     # Karpenter 노드 및 내부 통신을 위한 VPC 대역 허용
#     internal_vpc = {
#       ip_protocol = "-1"
#       description = "Allow all internal VPC traffic (Karpenter nodes)"
#       cidr_ipv4   = module.vpc.vpc_cidr_block
#     }
#   }
#   security_group_egress_rules = {
#     all = {
#       ip_protocol = "-1"
#       cidr_ipv4   = "0.0.0.0/0"
#     }
#   }

#   listeners = {
#     http = {
#       port     = 80
#       protocol = "TCP"
#       forward = {
#         target_group_key = "tg-80"
#       }
#     }
#     https = {
#       port     = 443
#       protocol = "TCP"
#       forward = {
#         target_group_key = "tg-443"
#       }
#     }
#     custom_9443 = {
#       port     = 9443
#       protocol = "TCP"
#       forward = {
#         target_group_key = "tg-9443"
#       }
#     }
#   }

#   # 라우터 노드 ip로 타겟id 수동으로 바꾸기 (귀찬아))
#   target_groups = {
#     tg-80 = {
#       name_prefix = "h80-"
#       protocol    = "TCP"
#       port        = 80
#       target_type = "ip"
#       target_id   = "${local.router_node_ip}"
#     }
#     tg-443 = {
#       name_prefix = "h443-"
#       protocol    = "TCP"
#       port        = 443
#       target_type = "ip"
#       target_id   = "${local.router_node_ip}"
#     }
#     tg-9443 = {
#       name_prefix = "h9443-"
#       protocol    = "TCP"
#       port        = 9443
#       target_type = "ip"
#       target_id   = "${local.router_node_ip}"
#     }
#   }

#   tags = {
#     Environment = "Development"
#     Project     = "Contentree"
#   }
# }

# # Route53 record envoy.sd.seungdobae.com → NLB alias
# resource "aws_route53_record" "envoy_record" {
#   zone_id = data.aws_route53_zone.this.zone_id
#   name    = "envoy.sd.seungdobae.com"
#   type    = "A"

#   alias {
#     name                   = module.nlb.dns_name
#     zone_id                = module.nlb.zone_id
#     evaluate_target_health = true
#   }
# }

# # Envoy Gateway Namespace
# resource "kubernetes_namespace_v1" "envoy_gateway" {
#   metadata {
#     name = "envoy-gateway-system"
#   }
# }

# # Envoy Gateway Helm Chart
# # CRD는 chart에서 직접 설치 (skip_crds = false)
# # 별도의 CRD chart를 사용하면 Helm release Secret 크기 제한(1MB) 초과 문제 발생
# resource "helm_release" "envoy_gateway" {
#   name       = "envoy-gateway"
#   namespace  = kubernetes_namespace_v1.envoy_gateway.metadata[0].name
#   repository = "oci://docker.io/envoyproxy"
#   chart      = "gateway-helm"
#   version    = "1.3.3"
#   skip_crds  = false # CRD를 chart에서 직접 설치
#   values = [
#     templatefile("${path.module}/helm-values/envoy-gateway.yaml", {
#       acm_certificate_arn = join(",", [
#         aws_acm_certificate_validation.project.certificate_arn,
#         data.aws_acm_certificate.existing.arn
#       ])
#     })
#   ]

#   depends_on = [
#     kubernetes_namespace_v1.envoy_gateway,
#     aws_acm_certificate_validation.project,
#     module.nlb
#   ]
# }

# # EnvoyProxy 리소스: Envoy Service에 annotations를 영구적으로 적용
# # 즉, Envoy가 만들 Gateway(실제 NLB 및 트래픽을 받을 Pod)에 아래 설정을 영구적으로 적용하는 템플릿 개념
# resource "kubectl_manifest" "envoy_proxy" {
#   yaml_body = <<-YAML
#     apiVersion: gateway.envoyproxy.io/v1alpha1
#     kind: EnvoyProxy
#     metadata:
#       name: envoy-config-9443
#       namespace: envoy-gateway-system
#     spec:
#       provider:
#         type: Kubernetes
#         kubernetes:
#           envoyDaemonSet:
#             pod:
#               nodeSelector:
#                 role: router
#               # tolerations는 내가 eks라서 필요함
#               tolerations:
#               - key: "role"
#                 operator: "Equal"
#                 value: "router"
#                 effect: "NoSchedule"
#             patch:
#               type: StrategicMerge
#               value:
#                 spec:
#                   template:
#                     spec:
#                       containers:
#                       - name: envoy
#                         ports:
#                         - containerPort: 9443
#                           hostPort: 9443
#                           name: https
#                           protocol: TCP
#           envoyService:
#             type: ClusterIP
#   YAML

#   depends_on = [
#     helm_release.envoy_gateway
#   ]
# }

# # Envoy Gateway GatewayClass
# # Gateway 리소스가 어떤 컨트롤러를 사용해서 만들지 정의하는 리소스
# # 파라미터는 각 컨트롤러가 지원하는 항목을 참조하도록 지정가능, 여기서는 envoy이므로 위에서만든 envoyproxy을 지정
# resource "kubectl_manifest" "envoy_gateway_class" {
#   yaml_body = <<-YAML
#     apiVersion: gateway.networking.k8s.io/v1
#     kind: GatewayClass
#     metadata:
#       name: envoygatewayclass-9443
#     spec:
#       controllerName: gateway.envoyproxy.io/gatewayclass-controller
#       parametersRef:
#         group: gateway.envoyproxy.io
#         kind: EnvoyProxy
#         name: envoy-config-9443
#         namespace: ${kubernetes_namespace_v1.envoy_gateway.metadata[0].name}
#   YAML

#   depends_on = [
#     kubectl_manifest.envoy_proxy
#   ]
# }

# # 자체 서명 인증서 생성 (Multi-SAN: joins.net + seungdobae.com)
# resource "tls_private_key" "joins_net" {
#   algorithm = "RSA"
#   rsa_bits  = 2048
# }

# resource "tls_self_signed_cert" "joins_net" {
#   private_key_pem = tls_private_key.joins_net.private_key_pem

#   subject {
#     common_name  = "joins.net"
#     organization = "Contentree Joins"
#   }

#   dns_names = [
#     "joins.net",
#     "*.joins.net",
#     "sd.seungdobae.com",
#     "*.sd.seungdobae.com",       # envoy.sd.seungdobae.com 포함
#     "envoy.sd.seungdobae.com"    # 명시적으로 추가
#   ]

#   validity_period_hours = 8760 # 1년

#   allowed_uses = [
#     "key_encipherment",
#     "digital_signature",
#     "server_auth",
#   ]
# }

# # Kubernetes TLS Secret 생성
# resource "kubernetes_secret_v1" "tls_joins_net" {
#   metadata {
#     name      = "tls-joins.net"
#     namespace = kubernetes_namespace_v1.envoy_gateway.metadata[0].name
#   }

#   type = "kubernetes.io/tls"

#   data = {
#     "tls.crt" = tls_self_signed_cert.joins_net.cert_pem
#     "tls.key" = tls_private_key.joins_net.private_key_pem
#   }
# }

# Envoy Gateway
# 실제 트래픽을 받을 Pod/Service를 만들도록하는 리소스
# Gateway을 만들때는 GatewayClass을 참조하여 만들어진다
# resource "kubectl_manifest" "envoy_gateway" {
#   yaml_body = <<-YAML
#     apiVersion: gateway.networking.k8s.io/v1
#     kind: Gateway
#     metadata:
#       name: envoygateway-9443
#       namespace: envoy-gateway-system
#     spec:
#       gatewayClassName: envoygatewayclass-9443
#       listeners:
#         - name: https
#           protocol: HTTPS
#           port: 9443
#           allowedRoutes:
#             namespaces:
#               from: All
#           tls:
#             mode: Terminate
#             certificateRefs:
#               - name: tls-joins.net # 해당 namespace에 미리 복사
#   YAML

#   depends_on = [
#     kubectl_manifest.envoy_gateway_class,
#     kubernetes_secret_v1.tls_joins_net
#   ]
# }

# # Argo CD 애플리케이션 생성 - Envoy Gateway 사용 시
# resource "kubernetes_manifest" "argocd_app_gateway_envoy" {
#   manifest = {
#     apiVersion = "argoproj.io/v1alpha1"
#     kind       = "Application"

#     metadata = {
#       name      = "ingress-echo-envoy"
#       namespace = kubernetes_namespace_v1.argocd.metadata[0].name
#       finalizers = [
#         "resources-finalizer.argocd.argoproj.io"
#       ]
#     }

#     spec = {
#       project = kubernetes_manifest.argocd_project.manifest.metadata.name

#       sources = [
#         {
#           repoURL        = "https://github.com/HaeDalWang/ingress-controller-test.git"
#           targetRevision = "HEAD"
#           path           = "chart"
#           helm = {
#             releaseName = "ingress-echo-envoy"
#             valueFiles = [
#               "values_envoy.yaml"
#             ]
#           }
#         }
#       ]

#       destination = {
#         name      = "in-cluster"
#         namespace = "app"
#       }

#       syncPolicy = {
#         syncOptions : ["CreateNamespace=true"]
#         automated : {}
#       }
#     }
#   }

#   depends_on = [
#     helm_release.argocd,
#     kubernetes_manifest.argocd_project
#   ]
# }