# 로컬 환경변수 지정
locals {
  project             = "cilium"
  project_prefix      = "cl"
  domain_name         = var.domain_name                                # 클러스터에 기반이 되는 루트 도메인
  project_domain_name = "${local.project_prefix}.${local.domain_name}" # 프로젝트에서만 사용하는 도메인
  tags = {                                                             # 모든 리소스에 적용되는 전역 태그
    "terraform" = "true"
  }
}

# 화이트리스트 목록
locals {
  # Ingress nginx 사용 시 IP를 기반으로 보안그룹 제어
  whitelist_ip_range = []
  # Data 컴포넌트 Ingress nginx 사용 시 IP를 기반으로 보안그룹 제어
  whitelist_ip_range_data = [
  ]
}

# App 배열을 만들어서 ECR, ArgoCD APP, CI/CD pipeline에 적용
locals {
  app = [
    "env-loader",
  ]
}