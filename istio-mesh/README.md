# Istio Service Mesh on EKS (Multi-Account Multi-Cluster)

멀티 어카운트 멀티 클러스터 환경에서 Istio Service Mesh를 운영하기 위한 프로덕션 구조 예제입니다.

**모델: Multi-Primary on Different Networks**
- 각 클러스터에 독립 Istiod (고가용성, 단일 장애점 없음)
- Shared Root CA → 클러스터간 mTLS 신뢰
- East-West Gateway → 클러스터간 서비스 디스커버리

## 아키텍처

```
┌─────────────────────────────────┐   ┌─────────────────────────────────┐
│  Primary Cluster (Mgmt Account)  │   │  Remote Cluster (Wkld Account)  │
│                                  │   │                                  │
│  ┌──────────┐  ┌──────────────┐ │   │ ┌──────────────┐  ┌──────────┐ │
│  │  Istiod   │  │Ingress GW   │ │   │ │  Istiod       │  │          │ │
│  │(Control   │  │(NLB, public)│ │   │ │ (Control      │  │          │ │
│  │ Plane)    │  └──────────────┘ │   │ │  Plane)       │  │          │ │
│  └──────────┘                    │   │ └──────────────┘  │          │ │
│                                  │   │                    │          │ │
│  ┌──────────────────────────┐   │   │  ┌──────────────────────┐    │ │
│  │  East-West GW            │◄──┼mTLS┼──►  East-West GW       │    │ │
│  │  (NLB, internal)         │   │15443│  │  (NLB, internal)    │    │ │
│  └──────────────────────────┘   │   │  └──────────────────────┘    │ │
│                                  │   │                              │ │
│  Shared Root CA ─────────────────┼───┼── Shared Root CA             │ │
│  (Intermediate CA-1)             │   │   (Intermediate CA-2)        │ │
│                                  │   │                              │ │
│  network-1                       │   │   network-2                  │ │
│  meshID: istio-mesh              │   │   meshID: istio-mesh         │ │
└──────────────────────────────────┘   └──────────────────────────────┘
        VPC Peering / Transit Gateway
```

## 디렉토리 구조

```
istio-mesh/
├── primary/                     # Management 클러스터 (EKS + Istio)
│   ├── providers.tf
│   ├── variables.tf / terraform.tfvars
│   ├── local.tf / data.tf
│   ├── network.tf               # VPC
│   ├── eks.tf                   # EKS + Karpenter + LB Controller + ExternalDNS
│   ├── istio.tf                 # Root CA + istio-base + istiod + gateways
│   ├── sample-app.tf            # httpbin + HTTPRoute + PeerAuthentication
│   └── helm-values/
│       ├── istiod.yaml
│       ├── ingress-gateway.yaml
│       └── eastwest-gateway.yaml
└── remote/                      # Workload 클러스터 (기존 EKS + Istio)
    ├── providers.tf
    ├── variables.tf / terraform.tfvars
    ├── data.tf
    ├── istio.tf                 # Intermediate CA + istio-base + istiod + East-West GW
    └── helm-values/
        ├── istiod.yaml
        └── eastwest-gateway.yaml
```

## 멀티 클러스터 핵심 개념

### Shared Root CA
```
Root CA (공유)
├── Intermediate CA - primary (클러스터 1 전용)
└── Intermediate CA - remote  (클러스터 2 전용)
```
- 같은 Root CA → 클러스터간 mTLS 상호 인증 가능
- 각 클러스터는 독립 Intermediate CA → CA 유출 시 영향 범위 제한
- primary에서 TLS provider로 Root CA 생성 → output으로 remote에 전달

### Network Model
- `network-1` (primary), `network-2` (remote) → 서로 다른 네트워크
- East-West Gateway가 15443 포트로 Auto-Passthrough mTLS 제공
- VPC Peering 또는 Transit Gateway로 East-West GW 간 통신

### Service Discovery
- `istioctl create-remote-secret`로 상대 클러스터의 API Server 접근 권한 등록
- 각 Istiod가 상대 클러스터의 서비스 엔드포인트를 발견

## 배포 순서

### 1. Primary 클러스터 배포

```bash
cd primary/

vi terraform.tfvars     # domain_name 등 수정
vi providers.tf         # backend S3 설정

terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

### 2. Root CA 추출

```bash
# primary 출력값을 remote에 전달
terraform -chdir=primary output -raw root_ca_cert_pem > /tmp/root-ca-cert.pem
terraform -chdir=primary output -raw root_ca_key_pem > /tmp/root-ca-key.pem
```

### 3. Remote 클러스터 배포

```bash
cd remote/

# Root CA를 환경변수로 전달
export TF_VAR_root_ca_cert_pem=$(cat /tmp/root-ca-cert.pem)
export TF_VAR_root_ca_key_pem=$(cat /tmp/root-ca-key.pem)

vi terraform.tfvars     # eks_cluster_name 수정
vi providers.tf         # backend S3 설정

terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

### 4. Remote Secret 등록 (클러스터간 서비스 디스커버리)

```bash
# primary 클러스터의 kubeconfig가 remote를 발견하도록 등록
istioctl create-remote-secret \
  --kubeconfig=<remote-kubeconfig> \
  --name=remote | \
  kubectl apply -f - --kubeconfig=<primary-kubeconfig>

# remote 클러스터의 kubeconfig가 primary를 발견하도록 등록
istioctl create-remote-secret \
  --kubeconfig=<primary-kubeconfig> \
  --name=primary | \
  kubectl apply -f - --kubeconfig=<remote-kubeconfig>
```

### 5. 네트워크 연결 (AWS)

East-West Gateway 간 통신을 위해 VPC를 연결해야 합니다:
- **VPC Peering**: 2개 VPC 연결 (간단, 소규모)
- **Transit Gateway**: 다수 VPC 허브 연결 (프로덕션 권장)

연결 후 보안 그룹에서 포트 15443, 15012, 15017 허용 필요.

## 검증

```bash
# Istio 상태 확인
istioctl analyze --context=<primary-context>
istioctl analyze --context=<remote-context>

# 멀티 클러스터 연결 상태
istioctl remote-clusters --context=<primary-context>

# 사이드카 주입 확인
kubectl get pods -n sample-app -o jsonpath='{.items[*].spec.containers[*].name}'
# 출력: httpbin istio-proxy

# mTLS 상태 확인
istioctl x describe pod <httpbin-pod> -n sample-app
```

## 주요 설정

### Istio Gateway API
- `GatewayClass`: Istio가 Gateway API 컨트롤러로 동작
- `Gateway`: NLB 기반 Ingress (Istio Ingress Gateway)
- `HTTPRoute`: L7 라우팅 (Ingress NGINX 대체)

### mTLS
- `meshConfig.enableAutoMtls: true` → 자동 mTLS 활성화
- `PeerAuthentication`: 네임스페이스별 STRICT/PERMISSIVE 제어

### 트래픽 관리
- `VirtualService`: 가중치 기반 라우팅, 재시도, 타임아웃
- `DestinationRule`: 로드밸런싱, 서킷브레이커, 커넥션풀

## 보안 (프로덕션 체크리스트)

- [ ] Root CA를 AWS Private CA 또는 Vault로 교체
- [ ] East-West Gateway에 NetworkPolicy 추가
- [ ] AuthorizationPolicy로 서비스간 접근 제어
- [ ] PeerAuthentication STRICT 모드 전체 적용
- [ ] Istio CNI 플러그인 활성화 (init container 대체)
- [ ] Sidecar 리소스에 resource scope 설정 (불필요한 config push 방지)
