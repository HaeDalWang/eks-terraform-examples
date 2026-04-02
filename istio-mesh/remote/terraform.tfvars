# =============================================================================
# Istio Mesh Remote Cluster - Terraform 변수
# =============================================================================

# 기존 EKS 클러스터 이름
eks_cluster_name = "my-workload-cluster"

# Istio (primary와 버전 동일 필수)
istio_chart_version = "1.25.2"
mesh_id             = "istio-mesh"      # primary와 동일
cluster_name        = "remote"
network_name        = "network-2"       # primary와 다른 값

# Root CA는 primary에서 출력된 값을 사용
# terraform -chdir=../primary output -raw root_ca_cert_pem > /tmp/root-ca-cert.pem
# terraform -chdir=../primary output -raw root_ca_key_pem > /tmp/root-ca-key.pem
#
# 방법 1: 환경변수
#   export TF_VAR_root_ca_cert_pem=$(cat /tmp/root-ca-cert.pem)
#   export TF_VAR_root_ca_key_pem=$(cat /tmp/root-ca-key.pem)
#
# 방법 2: terraform.tfvars에 직접 입력 (보안 주의)
#   root_ca_cert_pem = <<-EOT
#     -----BEGIN CERTIFICATE-----
#     ...
#     -----END CERTIFICATE-----
#   EOT
