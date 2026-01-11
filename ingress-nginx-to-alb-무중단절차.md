# Ingress Nginx → ALB 무중단 마이그레이션 가이드

## 개요

기존 nginx-ingress를 AWS ALB로 무중단 전환하는 절차입니다.  
External DNS의 Route 53 Weighted Routing을 활용하여 트래픽을 점진적으로 이동합니다.

## 아키텍처

```
                    ┌─────────────────────────────────────────┐
                    │           Route 53 (Weighted)           │
                    │  app.sd.seungdobae.com                  │
                    │  ├─ SetId: app-nginx  Weight: 50        │
                    │  └─ SetId: app-alb    Weight: 50        │
                    └─────────────────────────────────────────┘
                                      │
                    ┌─────────────────┴─────────────────┐
                    ▼                                   ▼
           ┌───────────────┐                   ┌───────────────┐
           │  nginx LB     │                   │   AWS ALB     │
           │  (Ingress)    │                   │  (Ingress)    │
           └───────┬───────┘                   └───────┬───────┘
                   │                                   │
                   └─────────────┬─────────────────────┘
                                 ▼
                         ┌─────────────┐
                         │   Service   │
                         │ (ClusterIP) │
                         └──────┬──────┘
                                ▼
                         ┌─────────────┐
                         │    Pods     │
                         └─────────────┘
```

---

## 사전 요구사항

- [x] AWS Load Balancer Controller 설치 (v2.5+)
- [x] External DNS 설치 및 Route 53 권한 설정
- [x] ACM 인증서 (ALB HTTPS용)

---

## 1단계: Helm 템플릿 수정

### 1.1 `templates/ingress-alb.yaml` 생성

```yaml
{{- if .Values.alb.enabled -}}
{{- $fullName := include "app-server.fullname" . -}}
{{- $svcPort := .Values.service.port -}}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ $fullName }}-alb
  labels:
    {{- include "app-server.labels" . | nindent 4 }}
  annotations:
    {{- with .Values.alb.annotations }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
    {{- if .Values.alb.whitelist }}
    alb.ingress.kubernetes.io/inbound-cidrs: {{ join "," .Values.alb.whitelist }}
    {{- end }}
    {{- if .Values.alb.setIdentifier }}
    external-dns.alpha.kubernetes.io/set-identifier: {{ .Values.alb.setIdentifier }}
    external-dns.alpha.kubernetes.io/aws-weight: {{ .Values.alb.weight | default 0 | quote }}
    {{- end }}
spec:
  ingressClassName: {{ .Values.alb.className | default "alb" }}
  {{- if .Values.alb.tls }}
  tls:
    {{- range .Values.alb.tls }}
    - hosts:
        {{- range .hosts }}
        - {{ . | quote }}
        {{- end }}
      {{- if .secretName }}
      secretName: {{ .secretName }}
      {{- end }}
    {{- end }}
  {{- end }}
  rules:
    {{- range .Values.alb.hosts }}
    - host: {{ .host | quote }}
      http:
        paths:
          {{- range .paths }}
          - path: {{ .path }}
            pathType: {{ .pathType | default "Prefix" }}
            backend:
              service:
                name: {{ $fullName }}
                port:
                  number: {{ $svcPort }}
          {{- end }}
    {{- end }}
{{- end }}
```

### 1.2 `templates/ingress.yaml` 수정

External DNS weighted routing annotation 추가:

```yaml
  {{- if $.Values.ingress.setIdentifier }}
    external-dns.alpha.kubernetes.io/set-identifier: {{ $.Values.ingress.setIdentifier }}
    external-dns.alpha.kubernetes.io/aws-weight: {{ $.Values.ingress.weight | default 0 | quote }}
  {{- end }}
```

> ⚠️ **주의**: `weight: 0`은 Helm에서 falsy로 처리되므로, `setIdentifier`가 있으면 `weight`도 항상 출력되도록 구현

---

## 2단계: values.yaml 설정

### 2.1 기본 values.yaml에 ALB 섹션 추가

```yaml
# AWS ALB Ingress Controller 설정
alb:
  enabled: false
  className: alb
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/group.name: my-alb-group
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
    alb.ingress.kubernetes.io/ssl-redirect: "443"
    # Host 헤더 보존
    alb.ingress.kubernetes.io/load-balancer-attributes: routing.http.preserve_host_header.enabled=true
  hosts:
    - host: chart-example.local
      paths:
        - path: /
          pathType: Prefix
```

### 2.2 환경별 values 설정 (예: values_dev.yaml)

```yaml
ingress:
  enabled: true
  className: nginx
  setIdentifier: app-nginx
  weight: 50                    # nginx 50%
  hosts:
    - host: app.sd.seungdobae.com
      path: /
      pathType: Prefix
      whitelist:
        - 58.239.25.4
        - 117.111.5.71

alb:
  enabled: true    
  className: alb
  setIdentifier: app-alb
  weight: 50                    # ALB 50%
  whitelist:
    - 58.239.25.4/32            # ALB는 CIDR 형식 필요
    - 117.111.5.71/32
  hosts:
    - host: app.sd.seungdobae.com
      paths:
        - path: /
          pathType: Prefix
```

---

## 3단계: 무중단 마이그레이션 실행

### 3.1 Phase 1: ALB 생성 및 검증 (nginx 100%)

```yaml
ingress:
  weight: 100    # nginx 100%
alb:
  enabled: true
  weight: 0      # ALB 0% (생성만)
```

```bash
helm upgrade <release> . -f values_dev.yaml -n <namespace>
```

**검증:**
```bash
# ALB DNS 확인
kubectl get ingress -n <namespace> | grep alb

# ALB로 직접 테스트
ALB_DNS=$(kubectl get ingress <release>-alb -n <namespace> -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl -H "Host: app.sd.seungdobae.com" https://$ALB_DNS/api/intgapp/ping/ -k
```

### 3.2 Phase 2: 트래픽 분산 (50:50)

```yaml
ingress:
  weight: 50
alb:
  weight: 50
```

**무중단 테스트 실행:**
```bash
./scripts/downtime-test.sh
```

### 3.3 Phase 3: ALB로 완전 전환 (ALB 100%)

```yaml
ingress:
  weight: 0
alb:
  weight: 100
```

### 3.4 Phase 4: nginx Ingress 제거 (선택)

```yaml
ingress:
  enabled: false
  # setIdentifier 제거
alb:
  weight: 100
  # setIdentifier 제거 (단일 레코드로 전환)
```

---

## 4단계: 롤백 절차

문제 발생 시 즉시 nginx로 롤백:

```yaml
ingress:
  weight: 100
alb:
  weight: 0
```

```bash
helm upgrade <release> . -f values_dev.yaml -n <namespace>
```

> DNS TTL(기본 300초) 이후 완전 롤백됨

---

## 주요 ALB Annotation 참조

| Annotation | 설명 | 예시 |
|------------|------|------|
| `scheme` | internet-facing / internal | `internet-facing` |
| `target-type` | ip / instance | `ip` |
| `group.name` | ALB 공유 그룹명 | `my-alb-group` |
| `listen-ports` | 리스너 포트 | `'[{"HTTPS": 443}]'` |
| `ssl-redirect` | HTTP→HTTPS 리다이렉트 | `"443"` |
| `inbound-cidrs` | IP whitelist (nginx whitelist 대체) | `10.0.0.0/8,1.2.3.4/32` |
| `load-balancer-attributes` | LB 속성 | `routing.http.preserve_host_header.enabled=true` |
| `certificate-arn` | ACM 인증서 (자동 디스커버리 가능) | `arn:aws:acm:...` |

---

## External DNS Weighted Routing

### 동작 원리

1. 동일 호스트에 2개의 A 레코드 생성 (각각 다른 SetIdentifier)
2. Route 53이 weight 비율에 따라 DNS 응답
3. 클라이언트는 받은 IP(nginx LB 또는 ALB)로 접속

### Route 53 레코드 예시

```
Name                      Type   SetId       Weight   Value
app.sd.seungdobae.com     A      app-nginx   50       nginx-lb-xxx.elb...
app.sd.seungdobae.com     A      app-alb     50       alb-xxx.elb...
```

---

## 참고 문서

- [AWS Load Balancer Controller Annotations](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/ingress/annotations/)
- [External DNS - Route 53](https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/aws.md)
- [Route 53 Weighted Routing](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/routing-policy-weighted.html)
