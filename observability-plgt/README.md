# PLGT Stack on EKS (Prometheus + Loki + Grafana + Tempo, Alloy 통일 수집)

단일 EKS 클러스터에 자체호스팅 관측성 스택을 구성하는 프로덕션 구조 예제입니다.
리소스 request/limit만 최소화되어 있으며, 구조 자체는 프로덕션 운영을 전제로 설계되었습니다.

`lgtm-stack/` (Mimir + 멀티 클러스터 central/agent 구조)와 대비되는 축을 보여줍니다:

| 축 | `lgtm-stack/` | `observability-plgt/` (이 예제) |
|---|---|---|
| 메트릭 LTS | Mimir (항상 켬) | Prometheus + **Thanos (toggle)** |
| 수집 소프트웨어 | Prometheus + Fluent Bit | **Alloy 단일** (Node Exporter/Promtail/Fluent Bit/OTel Collector 미사용) |
| 토폴로지 | 멀티 클러스터 (central/agent) | 단일 클러스터 |
| 로그 백엔드 | Loki SingleBinary | Loki **SimpleScalable(SSD)** |
| 추적 백엔드 | Tempo distributed | Tempo **monolithic + metrics-generator** |

## 핵심 설계 판단

### 1) 수집은 Alloy 소프트웨어로 통일

Node Exporter, Promtail, Fluent Bit, OTel Collector를 따로 굴리지 않고 Alloy 하나가 메트릭 스크레이핑 + 로그 tailing + OTLP 수신을 전부 처리합니다. 역할별로 3개 릴리스로 분리했습니다 (컨트롤러 타입이 다르기 때문에 하나의 Deployment/DaemonSet으로 합칠 수 없습니다):

```
alloy-logs      DaemonSet              노드 로컬 Pod 로그 tailing + node-exporter 대체 메트릭
alloy-metrics   Deployment(clustered)  Pod annotation + kube-state-metrics 스크레이핑 (샤딩)
alloy-receiver  Deployment             OTLP(gRPC 4317 / HTTP 4318) 수신 게이트웨이
```

`alloy-metrics`는 `clustering { enabled = true }`로 레플리카끼리 스크레이핑 대상을 나눠 가집니다. 레플리카 수를 늘리면 스크레이핑 부하가 수평으로 분산됩니다.

### 2) 메트릭 척추: Prometheus는 스크레이핑하지 않는다

```
Alloy-metrics(clustered) --remote_write--> Prometheus (--web.enable-remote-write-receiver)
                                                └─ Thanos sidecar (enable_thanos) --> S3
Grafana --> Prometheus 직결 (off) / Thanos Query Frontend (on)
```

Prometheus는 `serverFiles.prometheus.yml.scrape_configs`를 비워서 아무것도 직접 스크레이핑하지 않습니다. 모든 스크레이핑은 Alloy가 수행하고 remote_write로 밀어넣습니다. 이렇게 해야 "수집은 Alloy로 통일"이라는 설계가 실제로 성립합니다 (Prometheus Operator + ServiceMonitor 패턴을 쓰면 스크레이핑이 다시 두 곳으로 나뉩니다).

### 3) Thanos는 toggle, 그리고 공식 Helm 차트가 없다

`enable_thanos = false`(기본)면 Prometheus 로컬 TSDB만 사용합니다. `true`로 켜면:

| | off | on |
|---|---|---|
| Prometheus | Deployment, 로컬 TSDB(기본 retention) | **StatefulSet** 전환 + retention 6h + thanos-sidecar 컨테이너 |
| 추가 컴포넌트 | 없음 | Store Gateway · Compactor · Query · Query Frontend(+memcached) |
| Grafana 메트릭 datasource | Prometheus 직결 | Thanos Query Frontend |
| S3 `thanos/` prefix | 미사용 | 사용 |

**Thanos에는 Grafana Labs가 관리하는 공식 Helm 차트가 없습니다.**
- `bitnami/thanos`: 2025-08-28부로 신규 게시 중단, 기존 차트도 "out-of-the-box 동작 보장 안 됨"이라고 Bitnami가 공식 문서에 명시
- `thanos-io/kube-thanos`: jsonnet 기반이라 Helm이 아님, 마지막 정식 릴리즈가 2022년
- `thanos-community/helm-charts`: 그나마 활발하지만 star 48개짜리 소규모 커뮤니티 프로젝트

그래서 이 예제는 Thanos 컴포넌트(Store Gateway/Compactor/Query/Query Frontend)를 `thanos.tf`에서 순수 Kubernetes manifest(`kubernetes_deployment_v1`/`kubernetes_stateful_set_v1`)로 직접 작성합니다. 컴포넌트 자체는 평범한 Deployment/StatefulSet이라 외부 차트 의존 없이 관리 가능합니다. 이 방식은 Thanos 생태계에서 실제로 흔히 쓰이는 패턴입니다 (Bitnami 차트 대신 손으로 매니페스트를 짜는 사례가 다수 확인됨).

## 아키텍처

```
┌──────────────────────────────────────────────────────────────────┐
│  단일 EKS 클러스터                                                  │
│                                                                    │
│  ┌─────────┐                                                      │
│  │ Grafana │ ◄── 조회 (metrics datasource는 enable_thanos로 전환)    │
│  └────┬────┘                                                      │
│       │                                                            │
│  ┌────▼──────┬───────────┬───────────┐                            │
│  │Prometheus │   Loki    │  Tempo    │                            │
│  │(+Thanos?) │  (SSD)    │(monolithic│                            │
│  │           │           │+metrics-gen)│                          │
│  └────▲──────┴─────▲─────┴─────▲─────┘                            │
│       │remote_write│push       │OTLP push + metrics-generator RW  │
│  ┌────┴────────────┴───────────┴──────┐                           │
│  │  alloy-metrics   alloy-logs   alloy-receiver                   │
│  │  (Deployment,    (DaemonSet)  (Deployment, OTLP gateway)       │
│  │   clustered)                                                    │
│  └───────────────────────────────────┘                            │
│  + kube-state-metrics (alloy-metrics가 스크레이핑)                  │
│                                                                    │
│  S3: loki/ · tempo/ 항상, thanos/ 는 enable_thanos=true 일 때만     │
└──────────────────────┬─────────────────────────────────────────────┘
                        │ HTTPS (Envoy Gateway + NLB)
                        ▼
                    Grafana 조회 (외부)
```

## 디렉토리 구조

```
observability-plgt/
├── providers.tf              # backend, required_providers
├── variables.tf / terraform.tfvars
├── local.tf                  # metrics_query_service 등 조건부 값
├── data.tf
├── network.tf                # VPC
├── eks.tf                    # EKS + Karpenter + LB Controller + ExternalDNS
├── envoy-gateway.tf          # Envoy Gateway + NLB + ACM
├── storage.tf                # S3 + KMS + Pod Identity (thanos용은 조건부)
├── alloy.tf                  # alloy-logs / alloy-metrics / alloy-receiver + kube-state-metrics
├── prometheus.tf             # Prometheus (RW receiver) + Thanos objstore Secret
├── thanos.tf                 # Store Gateway/Compactor/Query/Query Frontend (순수 manifest, toggle)
├── loki.tf                   # Loki SimpleScalable
├── tempo.tf                  # Tempo monolithic + metrics-generator
├── grafana.tf                # Grafana 단독 배포, 조건부 datasource
├── httproutes.tf             # Grafana HTTPRoute
└── helm-values/
    ├── alloy-logs.alloy / alloy-metrics.alloy / alloy-receiver.alloy
    ├── prometheus.yaml / prometheus-thanos.yaml  (오버레이, enable_thanos=true일 때만 추가 병합)
    ├── loki.yaml / tempo.yaml / grafana.yaml / envoy-gateway.yaml
```

## 배포

```bash
# 변수 수정
vi terraform.tfvars       # domain_name, grafana_admin_password
vi providers.tf           # backend S3 설정

terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

### Thanos 활성화

```hcl
# terraform.tfvars
enable_thanos = true
```

켜면 Prometheus가 Deployment → StatefulSet으로 전환되고 Store Gateway/Compactor/Query/Query Frontend가 추가 배포됩니다. Grafana 메트릭 datasource는 자동으로 Thanos Query Frontend로 전환됩니다 (재배포 필요 없음, `local.metrics_query_service`가 조건부로 계산됨).

## 배포 후 접속

```bash
echo "https://grafana.plgt.<domain_name>"
```

## Grafana Datasource 상호 연동

- **Loki → Tempo**: 로그의 traceId 필드 클릭 → Tempo 트레이스 조회
- **Tempo → Metrics**: Service Graph, RED 메트릭 (Tempo metrics-generator가 직접 Prometheus RW로 전송)
- **Tempo → Loki**: 트레이스에서 관련 로그 필터링

## 애플리케이션에서 OTLP 전송

```yaml
OTEL_EXPORTER_OTLP_ENDPOINT: "http://alloy-receiver.monitoring.svc.cluster.local:4317"  # gRPC
# 또는
OTEL_EXPORTER_OTLP_ENDPOINT: "http://alloy-receiver.monitoring.svc.cluster.local:4318"  # HTTP
```

Pod에서 Alloy가 자동으로 메트릭을 스크레이핑하게 하려면 다음 annotation을 추가합니다:

```yaml
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "8080"
  # prometheus.io/path: "/metrics"  # 기본값 /metrics 가 아니면 지정
```

## 트래픽 입구(Envoy Gateway) 메트릭

트레이스를 입구부터 보려면 실제 요청이 지나가는 **데이터플레인 Envoy Proxy pod**(컨트롤러 아님)의 RED 메트릭이 필요합니다. `envoy-gateway.tf`의 `EnvoyProxy` 리소스에서 두 가지를 설정합니다:

- `spec.telemetry.metrics.prometheus`: Envoy Proxy의 Prometheus pull 방식 메트릭 노출 (기본 활성화, 명시적으로 둠)
- `spec.provider.kubernetes.envoyDeployment.pod.annotations`: 데이터플레인 pod에 `prometheus.io/scrape=true` + `port=19001` + `path=/stats/prometheus` 부여 → Alloy(alloy-metrics)가 annotation 기반으로 자동 스크레이핑

컨트롤러(envoy-gateway 자체) 메트릭은 `gateway-helm` 차트 기본값에 이미 `prometheus.io/scrape` annotation이 있어 별도 설정 없이 스크레이핑됩니다 (`:19001/metrics`). 두 종류를 헷갈리지 않아야 합니다 — 컨트롤러 메트릭은 xDS 동기화/어드미션 등 컨트롤 플레인 지표이고, 실제 요청 latency/에러율/처리량 같은 입구 트래픽 지표는 데이터플레인 쪽에서만 나옵니다.

주요 데이터플레인 메트릭:

- `envoy_http_downstream_rq_total` / `envoy_http_downstream_rq_xx` (상태 코드별 요청 수)
- `envoy_cluster_upstream_rq_time` (백엔드 응답 시간)
- `envoy_cluster_upstream_rq_retry` / `_timeout` (재시도, 타임아웃)

## 보안 (프로덕션 체크리스트)

이 예제는 인증 없이 노출되어 있습니다. 프로덕션에서는 다음을 추가해야 합니다:

- [ ] Grafana 접근에 Envoy Gateway SecurityPolicy(OIDC/JWT/BasicAuth) 또는 Grafana OAuth 연동 추가
- [ ] Alloy가 사용하는 Prometheus RW / Loki push / Tempo OTLP 엔드포인트는 cluster-internal이라 기본적으로 외부 노출 없음. 외부 워크로드에서 수신해야 한다면 mTLS 또는 BasicAuth 추가
- [ ] S3 버킷 암호화는 기본 SSE-KMS 적용됨. KMS 키 정책을 최소 권한으로 검토
- [ ] Thanos Compactor의 retention 정책(`--retention.resolution-*`)을 조직의 보관 요구사항에 맞게 조정
