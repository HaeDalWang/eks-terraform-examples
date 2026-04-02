# LGTM Stack on EKS (Multi-Account Multi-Cluster)

멀티 어카운트 멀티 클러스터 환경에서 Grafana LGTM (Loki, Grafana, Tempo, Mimir) 관측성 스택을 운영하기 위한 프로덕션 구조 예제입니다.

리소스 request/limit만 PoC 수준으로 최소화되어 있으며, 구조 자체는 프로덕션 운영을 전제로 설계되었습니다.

## 아키텍처

```
┌──────────────────────────────────────────────────────────┐
│  Management Account - Central Cluster                     │
│                                                           │
│  ┌─────────────┐  ┌──────┐  ┌──────┐  ┌───────┐         │
│  │    Mimir     │  │ Loki │  │Tempo │  │Grafana│         │
│  │ (메트릭저장) │  │(로그) │  │(추적)│  │(조회) │         │
│  └──────▲───────┘  └──▲───┘  └──▲───┘  └───────┘         │
│         │             │         │                         │
│  ┌──────┴─────────────┴─────────┴──────┐                 │
│  │       Envoy Gateway + NLB            │  ◄── HTTPS     │
│  │  (TLS 종료, L7 HTTPRoute 라우팅)      │                │
│  └──────▲─────────────▲─────────▲──────┘                 │
│         │             │         │                         │
│  [자체 모니터링]                                           │
│  Prometheus ─→ Mimir (cluster-internal)                   │
│  FluentBit  ─→ Loki  (cluster-internal)                   │
│  S3 Bucket (Mimir/Loki/Tempo 공용)                        │
└─────────┬─────────────┬─────────┬────────────────────────┘
          │             │         │
          │ remote-write│ log push│ OTLP
          │ (HTTPS)     │ (HTTPS) │ (HTTPS)
          │             │         │
┌─────────▼──┐  ┌──────▼────┐  ┌─▼──────────┐
│ dev cluster │  │stg cluster│  │prod cluster│  ← 다른 Account
│             │  │           │  │            │
│ Prometheus  │  │Prometheus │  │ Prometheus │
│ FluentBit   │  │FluentBit  │  │ FluentBit  │
│ ksm + ne    │  │ksm + ne   │  │ ksm + ne   │
│             │  │           │  │            │
│ ❌ Grafana  │  │❌ Grafana │  │❌ Grafana  │
│ ❌ Mimir    │  │❌ Loki    │  │❌ Tempo    │
└─────────────┘  └───────────┘  └────────────┘
```

## 디렉토리 구조

```
lgtm-stack/
├── central/                 # Management 클러스터 (LGTM 중앙 저장소)
│   ├── providers.tf
│   ├── variables.tf / terraform.tfvars
│   ├── local.tf / data.tf
│   ├── network.tf           # VPC
│   ├── eks.tf               # EKS + Karpenter + LB Controller + ExternalDNS
│   ├── envoy-gateway.tf     # Envoy Gateway + NLB + ACM + Gateway API
│   ├── observability.tf     # S3 + Pod Identity + Mimir + Loki + Tempo
│   ├── prometheus.tf        # kube-prometheus-stack (Grafana 포함)
│   ├── fluent-bit.tf
│   ├── httproutes.tf        # Grafana/Mimir/Loki/Tempo HTTPRoute 노출
│   └── helm-values/
└── agent/                   # Workload 클러스터 (수집 에이전트만)
    ├── providers.tf         # 기존 EKS 클러스터에 연결
    ├── variables.tf / terraform.tfvars
    ├── data.tf
    ├── prometheus.tf        # kube-prometheus-stack (Grafana ❌)
    ├── fluent-bit.tf        # → Central Loki (HTTPS)
    └── helm-values/
```

## kube-prometheus-stack 배포 범위

| 컴포넌트 | central | agent | 비고 |
|---------|:-------:|:-----:|------|
| Prometheus Operator | O | O | CRD 관리 |
| Prometheus | O | O | 메트릭 수집 → Mimir remote-write |
| **Grafana** | **O** | **X** | Central에서만 통합 조회 |
| **Alertmanager** | **X** | **X** | Mimir Alertmanager 사용 |
| node-exporter | O | O | 노드 메트릭 |
| kube-state-metrics | O | O | K8s 리소스 메트릭 |
| PrometheusRules | O | O | 로컬 평가, alert은 Mimir AM으로 |

## 데이터 흐름

| 신호 | Central (cluster-internal) | Agent (→ Central HTTPS) |
|------|--------------------------|------------------------|
| 메트릭 | Prometheus → `mimir-gateway:80` | Prometheus → `https://mimir.lgtm.example.com` |
| 로그 | Fluent Bit → `loki-gateway:80` | Fluent Bit → `https://loki.lgtm.example.com` |
| 추적 | App OTLP → `tempo-distributor:4318` | App OTLP → `https://tempo.lgtm.example.com` |
| 알림 | Rules → Mimir AM (internal) | Rules → Mimir AM (HTTPS) |

## S3 버킷 구조

하나의 버킷을 prefix로 분리:
```
s3://lgtm-central-obs-xxxxx/
├── mimir/
│   ├── blocks/
│   ├── alertmanager/
│   └── ruler/
├── loki/
└── tempo/
```

## 배포 순서

### 1. Central 클러스터

```bash
cd central/

# 변수 수정
vi terraform.tfvars       # domain_name, grafana_admin_password
vi providers.tf           # backend S3 설정

terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

### 2. Agent 클러스터 (기존 EKS에 추가)

```bash
cd agent/

# 변수 수정
vi terraform.tfvars       # eks_cluster_name, central_mimir_endpoint, central_loki_endpoint
vi providers.tf           # backend S3 설정

terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

## 배포 후 접속

```bash
# Grafana (Central)
echo "https://grafana.lgtm.<domain_name>"

# Grafana에서 클러스터별 메트릭 조회
# externalLabels.cluster로 구분: {cluster="lgtm-central"}, {cluster="my-workload-cluster"}
```

## Grafana Datasource 상호 연동

자동으로 설정되는 Cross-reference:
- **Loki → Tempo**: 로그의 traceId 필드 클릭 → Tempo 트레이스 조회
- **Tempo → Mimir**: Service Graph, RED 메트릭 자동 생성
- **Tempo → Loki**: 트레이스에서 관련 로그 필터링

## Tempo 트레이스 전송 (애플리케이션)

```yaml
# Central 클러스터 내부
OTEL_EXPORTER_OTLP_ENDPOINT: "http://tempo-distributor.monitoring.svc.cluster.local:4318"

# Agent 클러스터 → Central (HTTPS)
OTEL_EXPORTER_OTLP_ENDPOINT: "https://tempo.lgtm.<domain_name>"
```

## 보안 (프로덕션 체크리스트)

PoC에서는 인증 없이 노출되어 있습니다. 프로덕션에서는 다음을 추가해야 합니다:

- [ ] Mimir/Loki/Tempo 수신 엔드포인트에 인증 추가 (Envoy Gateway SecurityPolicy)
- [ ] BasicAuth, JWT, OIDC, 또는 mTLS 중 선택
- [ ] Agent Prometheus remote-write에 basicAuth 설정
- [ ] Agent Fluent Bit에 HTTP basicAuth 또는 bearer token 설정
- [ ] S3 버킷 암호화 (SSE-S3 또는 SSE-KMS)
- [ ] VPC Peering 또는 PrivateLink로 cross-account 네트워크 분리
