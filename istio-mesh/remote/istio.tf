# ########################################################
# Istio Service Mesh - Remote Cluster (Multi-Primary)
# ########################################################
#
# primary와 동일한 meshID, 다른 clusterName/network
# 동일한 Root CA → Intermediate CA만 다르게 생성
#

# ########################################################
# 1. Intermediate CA (이 클러스터 전용, 같은 Root CA)
# ########################################################
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
  ca_private_key_pem = var.root_ca_key_pem
  ca_cert_pem        = var.root_ca_cert_pem

  validity_period_hours = 43800 # 5년
  is_ca_certificate     = true
  set_subject_key_id    = true

  allowed_uses = [
    "cert_signing",
    "crl_signing",
  ]
}

# ########################################################
# 2. istio-system + cacerts + Gateway API CRDs
# ########################################################
resource "kubernetes_namespace_v1" "istio_system" {
  metadata {
    name = "istio-system"
    labels = {
      "topology.istio.io/network" = var.network_name
    }
  }
}

resource "kubernetes_secret_v1" "cacerts" {
  metadata {
    name      = "cacerts"
    namespace = kubernetes_namespace_v1.istio_system.metadata[0].name
  }

  data = {
    "ca-cert.pem"    = tls_locally_signed_cert.intermediate_ca.cert_pem
    "ca-key.pem"     = tls_private_key.intermediate_ca.private_key_pem
    "root-cert.pem"  = var.root_ca_cert_pem
    "cert-chain.pem" = "${tls_locally_signed_cert.intermediate_ca.cert_pem}${var.root_ca_cert_pem}"
  }
}

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
}

# ########################################################
# 3. istio-base + istiod
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
# 4. East-West Gateway (Cross-Cluster)
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

# Cross-network Gateway (auto-passthrough)
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
