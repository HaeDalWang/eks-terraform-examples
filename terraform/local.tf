# 로컬 환경변수 지정
locals {
  project             = "seungdobae"             # 클러스터의 이름/ArgoCD 클러스터 이름/리소스의 Prefix 등 사용
  service_domain_name = "mgm.${var.domain_name}" # 클러스터에 기반이 되는 도메인
  tags = {                                       # 모든 리소스에 적용되는 전역 태그
    "terraform" = "true"
  }
}

# 화이트리스트 목록 Ingress nginx 사용 시 IP를 기반으로 보안그룹 제어
locals {
  whitelist_ip_range = [
    "0.0.0.0/0" # 임시
  ]
}

# App 배열을 만들어서 ECR, ArgoCD APP, CodeBuild pipeline에 적용
locals {
  app = [
    "app-server",
  ]
}