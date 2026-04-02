# ########################################################
# Istio Service Mesh (Multi-Primary, Different Networks)
# ########################################################
#
# 설치 순서:
#   1. Root CA 생성 + Intermediate CA (클러스터별)
#   2. istio-system 네임스페이스 + cacerts Secret
#   3. Gateway API CRDs
#   4. istio-base (Istio CRDs)
#   5. istiod (Control Plane)
#   6. Ingress Gateway (North-South, internet-facing NLB)
#   7. East-West Gateway (Cross-Cluster, internal NLB)
#
# 멀티 클러스터 구성:
#   - meshID: 모든 클러스터 동일
#   - clusterName: 클러스터별 고유
#   - network: 클러스터별 고유 (different networks 모델)
#   - trustDomain: 모든 클러스터 동일 (shared root CA)
#

# ########################################################
# 1. Root CA + Intermediate CA
# ########################################################

# Root CA (모든 클러스터에서 공유해야 함)
# 프로덕션에서는 Vault 또는 AWS Private CA 사용 권장
# PoC에서는 Terraform TLS provider로 생성
resource "tls_private_key" "root_ca" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_self_signed_cert" "root_ca" {
  private_key_pem = tls_private_key.root_ca.private_key_pem

  subject {
    common_name  = "Istio Root CA"
    organization = "Istio"
  }

  validity_period_hours = 87600 # 10년
  is_ca_certificate     = true
  set_subject_key_id    = true

  allowed_uses = [
    "cert_signing",
    "crl_signing",
  ]
}

# Intermediate CA (이 클러스터 전용)
resource "tls_private_key" "intermediate_ca" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_cert_request" "intermediate_ca" {
  private_key_pem = tls_private_key.intermediate_ca.private_key_pem

  subject {
    common_name  = "Istio Intermediate CA - ${var.cluster_name}"
    organization = "Istio"
  }
}

resource "tls_locally_signed_cert" "intermediate_ca" {
  cert_request_pem   = tls_cert_request.intermediate_ca.cert_request_pem
  ca_private_key_pem = tls_private_key.root_ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.root_ca.cert_pem

  validity_period_hours = 43800 # 5년
  is_ca_certificate     = true
  set_subject_key_id    = true

  allowed_uses = [
    "cert_signing",
    "crl_signing",
  ]
}

# ########################################################
# 2. istio-system 네임스페이스 + cacerts + 네트워크 라벨
# ########################################################
resource "kubernetes_namespace_v1" "istio_system" {
  metadata {
    name = "istio-system"
    labels = {
      # 멀티 클러스터: Istio가 이 클러스터의 네트워크를 식별
      "topology.istio.io/network" = var.network_name
    }
  }
}

# Istiod가 사용할 CA 인증서 (cacerts Secret)
# Istio는 이 Secret이 존재하면 자동으로 사용, 없으면 자체 생성 (단일 클러스터만 가능)
resource "kubernetes_secret_v1" "cacerts" {
  metadata {
    name      = "cacerts"
    namespace = kubernetes_namespace_v1.istio_system.metadata[0].name
  }

  data = {
    "ca-cert.pem"    = tls_locally_signed_cert.intermediate_ca.cert_pem
    "ca-key.pem"     = tls_private_key.intermediate_ca.private_key_pem
    "root-cert.pem"  = tls_self_signed_cert.root_ca.cert_pem
    "cert-chain.pem" = "${tls_locally_signed_cert.intermediate_ca.cert_pem}${tls_self_signed_cert.root_ca.cert_pem}"
  }
}

# ########################################################
# 3. Gateway API CRDs (Istio Gateway API 모드 사용 시 필수)
# ########################################################
resource "helm_release" "gateway_api_crds" {
  name       = "gateway-api-crds"
  repository = "https://kubernetes-sigs.github.io/gateway-api"
  chart      = "gateway-api"
  version    = "1.2.1"
  namespace  = "default"

  set {
    name  = "installCRDs"
    value = "true"
  }

  depends_on = [kubectl_manifest.karpenter_default_nodepool]
}

# ########################################################
# 4. istio-base (Istio CRDs)
# ########################################################
resource "helm_release" "istio_base" {
  name       = "istio-base"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "base"
  version    = var.istio_chart_version
  namespace  = kubernetes_namespace_v1.istio_system.metadata[0].name

  depends_on = [
    kubernetes_secret_v1.cacerts,
    helm_release.gateway_api_crds
  ]
}

# ########################################################
# 5. istiod (Control Plane)
# ########################################################
resource "helm_release" "istiod" {
  name       = "istiod"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "istiod"
  version    = var.istio_chart_version
  namespace  = kubernetes_namespace_v1.istio_system.metadata[0].name

  values = [
    templatefile("${path.module}/helm-values/istiod.yaml", {
      mesh_id      = var.mesh_id
      cluster_name = var.cluster_name
      network_name = var.network_name
    })
  ]

  depends_on = [helm_release.istio_base]
}

# ########################################################
# 6. Ingress Gateway (North-South, internet-facing NLB)
# ########################################################
resource "kubernetes_namespace_v1" "istio_ingress" {
  metadata {
    name = "istio-ingress"
    labels = {
      "istio-injection" = "enabled"
    }
  }
}

resource "helm_release" "istio_ingress_gateway" {
  name       = "istio-ingressgateway"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "gateway"
  version    = var.istio_chart_version
  namespace  = kubernetes_namespace_v1.istio_ingress.metadata[0].name

  values = [
    templatefile("${path.module}/helm-values/ingress-gateway.yaml", {
      acm_certificate_arn = join(",", [
        data.aws_acm_certificate.existing.arn,
        aws_acm_certificate_validation.project.certificate_arn,
      ])
    })
  ]

  depends_on = [
    helm_release.istiod,
    helm_release.aws_load_balancer_controller
  ]
}

# ACM Certificate for Ingress
resource "aws_acm_certificate" "project" {
  domain_name       = "*.${local.project_domain_name}"
  validation_method = "DNS"
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "acm_validation" {
  for_each = {
    for dvo in aws_acm_certificate.project.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }
  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.this.zone_id
}

resource "aws_acm_certificate_validation" "project" {
  certificate_arn         = aws_acm_certificate.project.arn
  validation_record_fqdns = [for record in aws_route53_record.acm_validation : record.fqdn]
}

# ########################################################
# 7. East-West Gateway (Cross-Cluster, internal NLB)
# ########################################################
resource "helm_release" "istio_eastwest_gateway" {
  name       = "istio-eastwestgateway"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "gateway"
  version    = var.istio_chart_version
  namespace  = kubernetes_namespace_v1.istio_system.metadata[0].name

  values = [
    templatefile("${path.module}/helm-values/eastwest-gateway.yaml", {
      network_name = var.network_name
    })
  ]

  depends_on = [helm_release.istiod]
}

# East-West Gateway 용 Gateway 리소스
# 다른 네트워크(클러스터)의 트래픽을 자동으로 수신하는 설정
resource "kubectl_manifest" "expose_services" {
  yaml_body = <<-YAML
    apiVersion: networking.istio.io/v1
    kind: Gateway
    metadata:
      name: cross-network-gateway
      namespace: istio-system
    spec:
      selector:
        istio: eastwestgateway
      servers:
        - port:
            number: 15443
            name: tls
            protocol: TLS
          tls:
            mode: AUTO_PASSTHROUGH
          hosts:
            - "*.local"
  YAML

  depends_on = [helm_release.istio_eastwest_gateway]
}

# ########################################################
# Outputs (remote/ 클러스터에서 사용)
# ########################################################
output "root_ca_cert_pem" {
  description = "Root CA 인증서 (remote 클러스터에 전달)"
  value       = tls_self_signed_cert.root_ca.cert_pem
  sensitive   = true
}

output "root_ca_key_pem" {
  description = "Root CA 개인키 (remote 클러스터에 전달)"
  value       = tls_private_key.root_ca.private_key_pem
  sensitive   = true
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "mesh_id" {
  value = var.mesh_id
}
