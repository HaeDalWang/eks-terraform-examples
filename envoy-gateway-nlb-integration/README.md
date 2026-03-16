# Envoy Gateway + NLB(TLS Termination) + ExternalDNS 예제

이 디렉터리는 **Envoy Gateway + AWS NLB + ExternalDNS** 를 조합해,

- TLS 종료(TLS termination)를 **NLB** 에서 수행하고
- **Envoy Gateway(Gateway API)** 로 L7 라우팅을 하고
- **ExternalDNS** 가 Route53 DNS 레코드를 자동 관리하는

구조를 **작게 재현한 독립 예제**입니다.

---

## 구성 요소

- `vpc.tf`  
  - 예제용 VPC, 서브넷, 인터넷 게이트웨이, 라우팅 테이블 등을 생성합니다.

- `eks.tf`  
  - 예제용 EKS 클러스터 및 Karpenter(또는 노드 그룹)를 생성합니다.

- `external-dns.tf`  
  - `external-dns` Helm 차트를 배포합니다.
  - `sources: [service, gateway-httproute]` 로,
    - NLB Service annotation
    - Envoy Gateway + HTTPRoute  
    를 DNS 소스로 사용합니다.

- `envoy-gateway.tf`  
  - Envoy Gateway Helm 차트와 다음 리소스를 생성합니다.
    - `EnvoyProxy`  
      - NLB 타입 Service 및 다음과 같은 annotation을 설정:
        - `service.beta.kubernetes.io/aws-load-balancer-type: external`
        - `service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing`
        - `service.beta.kubernetes.io/aws-load-balancer-ssl-cert: ...`
        - `service.beta.kubernetes.io/aws-load-balancer-ssl-ports: "443"`
        - `service.beta.kubernetes.io/aws-load-balancer-backend-protocol: tcp`
        - `external-dns.alpha.kubernetes.io/hostname: "argocd....,nge...."` 등
    - `GatewayClass` / `Gateway(default)`  
      - Gateway API 기반의 L7 엔드포인트를 정의합니다.
    - `ClientTrafficPolicy`  
      - 필요 시 Proxy Protocol 등 클라이언트 트래픽 관련 정책을 설정합니다.
    - `BackendTrafficPolicy`  
      - `requestBuffer.limit: "100Mi"` 로 요청 body 최대 크기를 제한합니다.

- `local.tf`, `terraform.tfvars`, `providers.tf`  
  - 공통 로컬 값, 변수, Provider 버전 등을 정의합니다.

---

## 요구 사항

- Terraform 1.6+ (권장 1.10+)
- AWS 계정 및 다음 권한
  - EKS, VPC, IAM, Route53, ACM, ELB, S3
- Route53 Hosted Zone
  - `terraform.tfvars` 의 `domain_name` 에 설정된 도메인에 대한 Hosted Zone 이 존재해야 합니다.

---

## 배포 방법

```bash
cd /Users/seungdo/work/eks-terraform-examples/envoy-gateway-nlb-integration

terraform init
terraform plan
terraform apply
```

적용 후:

```bash
# Envoy Gateway NLB 주소 확인
kubectl get gateway -A

# HTTPRoute 확인
kubectl get httproute -A

# ExternalDNS 로그 확인 (DNS 레코드 생성 여부)
kubectl logs -n kube-system -l app.kubernetes.io/name=external-dns --tail=50
```

---

## HTTPRoute 예제 (새 애플리케이션)

이 예제는 **nginx Pod + Service + HTTPRoute** 한 세트를 만들어,
Envoy Gateway를 통해 새 도메인으로 트래픽을 받는 패턴을 보여줍니다.

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: httproute-example
---
apiVersion: v1
kind: Pod
metadata:
  name: nginx-example
  namespace: httproute-example
  labels:
    app: nginx-example
spec:
  containers:
    - name: nginx
      image: nginx:stable
      ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-example
  namespace: httproute-example
spec:
  selector:
    app: nginx-example
  ports:
    - name: http
      port: 80
      targetPort: 80
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: nginx-example
  namespace: httproute-example
spec:
  parentRefs:
    - name: default
      namespace: envoy-gateway-system
      sectionName: https
  hostnames:
    - "nginx-example.<your-domain>"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: nginx-example
          port: 80
```

**주의:**  
- 새 도메인을 사용하려면, Envoy NLB Service 의  
  `external-dns.alpha.kubernetes.io/hostname` annotation 에도  
  해당 호스트명을 추가해야 ExternalDNS 가 Route53 레코드를 생성합니다.

---

## 이 예제의 목적

- Ingress(nginx) 대신 **Gateway API + Envoy Gateway** 를 사용하는 패턴을 보여줍니다.
- **NLB에서 TLS 종료**, Envoy는 HTTP로 처리하는 구조를 재현합니다.
- **ExternalDNS + Gateway-HTTPRoute** 조합으로, HTTPRoute 기반 라우팅에서도
  DNS 자동 관리를 어떻게 구성할 수 있는지 보여줍니다.

실서비스에 적용하기 전에, 이 디렉터리만 별도로 배포해 동작을 검증하는 용도의
**작은 블루프린트**로 사용하는 것을 의도했습니다.