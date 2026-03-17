## eks-terraform-examples

실제 고객사 환경 구성이나 PoC 를 빠르게 진행하기 위해,
**검증된 EKS + 주변 솔루션 템플릿들을 폴더별로 모아둔 레포지토리**입니다.  
필요한 예제를 골라 `terraform init/plan/apply` 로 그대로 가져다 쓸 수 있게 하는 것이 목적입니다.

### 공통 특징

- `terraform-aws-modules` 계열 공식 모듈 활용
  - `terraform-aws-modules/vpc/aws`
  - `terraform-aws-modules/eks/aws`
  - `terraform-aws-modules/eks/aws//modules/karpenter`
  - `terraform-aws-modules/ecr/aws`
  - `terraform-aws-modules/security-group/aws`
- AWS EKS, VPC, IAM, Route53, ACM, ALB/NLB, Observability, Gateway API 등  
  자주 쓰는 구성을 **폴더 단위 시나리오**로 분리
- 각 폴더는 **서로 독립적인 예제**를 지향 (필요 시만 cross-reference)

---

### 폴더별 시나리오 및 마지막 수정일

| 폴더명 | 설명 | 마지막 수정일 |
|--------|------|----------------|
| `seungdo/` | 개인 실환경/PoC용 **EKS + Karpenter + 여러가지 | **2026-03-16** |
| `envoy-gateway-nlb-integration/` | Envoy Gateway + **AWS NLB(TLS termination)** + **ExternalDNS + Gateway API(HTTPRoute)** 최소 예제 (샘플 nginx 앱/HTTPRoute 포함) | **2026-03-16** |
| `cilium-cni/` | Cilium CNI + Gateway API (Envoy/Cilium/Traefik 조합) 실험용 예제. 네트워크 정책·IngressRoute·HTTPRoute 패턴 포함 | **2026-01-01** |
| `mlops/` | ML 워크로드용 아직 미완성임 **MLOps 파이프라인/관측** 관련 예제 | **2025-10-22** |
| `scripts/` | Downtime 테스트 및 유틸리티 쉘 스크립트 모음 | (git log 기준으로 필요 시 업데이트) |
| `customer/` | 고객 특정케이스 마다 임시작성에 사용한 tf파일들 | (git log 기준으로 필요 시 업데이트) |


> **주의**  
> 위 “마지막 수정일”은 `git log -1 -- <폴더>` 기준입니다.  
> 서브 디렉터리/파일 단위의 더 최신 변경이 있을 수 있으니, 실제 사용 전에는  
> 각 폴더의 `README.md`, `variables.tf`, `terraform.tfvars(.example)` 를 함께 확인하는 것을 권장합니다.

---

### 사용 방법 (공통)

1. **폴더 선택**  
   - 예: `seungdo/`, `envoy-gateway-nlb-integration/`, `cilium-cni/`, `mlops/` 등

2. **해당 디렉터리에서 Terraform 실행**

   ```bash
   cd <folder>
   terraform init
   terraform plan
   terraform apply