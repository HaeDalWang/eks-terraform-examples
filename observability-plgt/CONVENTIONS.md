# Terraform 작성 규칙 — 생성/삭제가 모두 깨끗하게 되도록

이 프로젝트(EKS + 클러스터 내 컨트롤러)에서 `terraform destroy`가 무한 대기(stuck)에 걸리는
사고는 거의 전부 **하나의 근본 패턴**에서 나온다. 새 리소스를 추가할 때 아래 규칙을 따른다.

## 근본 패턴

> **Terraform이 만든 리소스가 클러스터 안 컨트롤러에게 "AWS 리소스를 대신 만들어라"고 시키는 순간,
> Terraform 의존성 그래프가 모르는 숨은 의존성(orphan)이 생긴다.**

destroy 시 Terraform은 자기가 만든 것만 순서대로 지운다. 컨트롤러가 뒤에서 만든 부산물
(NLB, EBS 볼륨, Route53 레코드, EC2 인스턴스)은 그래프에 없어서, **컨트롤러를 먼저 죽여버리면
그 부산물을 정리할 주체가 사라지고** subnet/namespace/VPC가 영원히 대기한다.

이 프로젝트에서 실제로 겪은 사례:

| Terraform 리소스 | 컨트롤러가 뒤에서 만든 것 (그래프 밖) | destroy 시 터진 것 |
|---|---|---|
| `EnvoyProxy(type: LoadBalancer)` | NLB + 보안그룹 + TargetGroupBinding | subnet/IGW/VPC stuck |
| PVC 쓰는 helm (loki/tempo 등) | EBS 볼륨 + VolumeAttachment | pod Terminating stuck |
| `HTTPRoute` | Route53 레코드 | orphan DNS |
| karpenter `NodePool` | EC2 인스턴스 + NodeClaim finalizer | CRD stuck + VPC stuck |

---

## 규칙 1 — 컨트롤러 부산물을 만드는 리소스는 `time_sleep`으로 감싼다

컨트롤러(A)와, 컨트롤러에게 부산물 생성을 지시하는 leaf 리소스(B) 사이에 `time_sleep`을 끼운다.

```hcl
# A(컨트롤러 helm)  →  time_sleep  →  B(leaf CR)
resource "time_sleep" "wait_for_xxx" {
  depends_on       = [helm_release.controller]  # A
  destroy_duration = "300s"                      # 부산물 정리에 필요한 시간
}
# B의 depends_on을 A가 아니라 time_sleep으로 건다
resource "kubectl_manifest" "leaf" {
  depends_on = [time_sleep.wait_for_xxx]
}
```

동작:
- **생성**: A → sleep → B (당연한 순서)
- **삭제**: B 먼저 → **destroy_duration 대기(그동안 A 생존)** → A 나중
  → leaf 삭제로 컨트롤러가 부산물 정리를 시작하고, 대기 시간 동안 컨트롤러가 살아있어 정리가 완료됨.

이 프로젝트의 적용 예 (모두 동일 관용구):
- [`envoy-gateway.tf`](envoy-gateway.tf) `time_sleep.wait_for_envoy_lb` (300s) — NLB 정리
- [`eks.tf`](eks.tf) `time_sleep.wait_for_ebs_csi` (120s) — EBS 볼륨 detach
- [`eks.tf`](eks.tf) `time_sleep.wait_for_dns_cleanup` (60s) — Route53 레코드 정리

`destroy_duration` 가이드: NLB 5분, EBS 볼륨 2분, DNS 1분. 부산물이 무거울수록 길게.

---

## 규칙 2 — 새 리소스 추가 시 체크리스트 3문항

리소스를 하나 추가할 때마다 자문한다.

```
□ 이게 클러스터 안 컨트롤러에게 AWS 리소스를 만들게 하나? (LB / EBS / Route53 / EC2)
    → YES면 규칙 1 적용 (time_sleep 브래킷)

□ 이게 finalizer를 붙이는 k8s 객체인가? (LoadBalancer Service, PVC, NodeClaim, TargetGroupBinding)
    → 그 finalizer를 푸는 컨트롤러가 이 객체보다 반드시 더 오래 살도록 순서를 보장 (규칙 3)

□ 이게 AWS 상태 저장소인가? (S3 / ECR / EBS)
    → force_destroy = true 또는 삭제 정책을 명시
```

---

## 규칙 3 — 컨트롤러는 "가장 먼저 생성, 가장 나중 삭제"

다음 컨트롤러들은 자기 부산물보다 **항상 더 오래 살아야** 한다:
`aws-load-balancer-controller`, `aws-ebs-csi-driver`, `external-dns`, `karpenter`.

대부분은 규칙 1의 `time_sleep`이 자동 보장한다. 단, **finalizer 방식이 다른 것은 예외 처리**한다.

### 예외: karpenter (NodeClaim은 Terraform 리소스가 아님)

karpenter가 만든 NodeClaim/EC2는 `time_sleep`으로 못 잡는다(TF 그래프에 없음).
대신 **destroy-time provisioner**로 컨트롤러 생존 중에 NodeClaim을 비운다.

```hcl
resource "null_resource" "drain_karpenter_nodes" {
  triggers = {
    cluster_name = module.eks.cluster_name
    region       = data.aws_region.current.id
  }
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      aws eks update-kubeconfig --name ${self.triggers.cluster_name} --region ${self.triggers.region}
      kubectl delete nodeclaims --all --timeout=300s || true
    EOT
  }
  depends_on = [kubectl_manifest.karpenter_default_nodepool, helm_release.karpenter]
}
```
- `depends_on`으로 karpenter보다 나중에 생성 → destroy 시 **가장 먼저** 실행
- provisioner는 변수 직접 참조 불가. 필요한 값은 반드시 `triggers`에 담아 `self.triggers.*`로 참조
- 적용: [`eks.tf`](eks.tf) `null_resource.drain_karpenter_nodes`

---

## 만약 그래도 stuck에 걸렸다면 (수동 복구 순서)

stuck의 원인은 항상 "그래프 밖 orphan 부산물"이다. 아래 순서로 실물부터 제거한다.

1. **orphan AWS 실물 먼저 삭제** (컨트롤러가 이미 죽어 자동 정리 불가한 경우)
   - NLB: `aws elbv2 delete-load-balancer` → ENI 자동 해제
   - EC2(karpenter): `aws ec2 terminate-instances`
   - LB 컨트롤러가 만든 보안그룹(`k8s-*`): `aws ec2 delete-security-group` (VPC 삭제 막는 흔한 범인)
2. **k8s finalizer 제거** (실물이 없어진 뒤 유령 객체만 남은 경우)
   - `kubectl patch <obj> -p '{"metadata":{"finalizers":[]}}' --type=merge`
   - 대상: LoadBalancer Service / TargetGroupBinding / PVC(pod force-delete로 해제) / NodeClaim
3. **`terraform destroy` 재실행** — helm release가 이미 지워졌으면 다음 실행에서 즉시 통과.

> 핵심: helm 5분 타임아웃 직전에 수동 개입하면 terraform이 exit 1로 빠지지만, 실물은 정리되므로
> 재실행하면 이어서 완주한다. 위 규칙 1~3을 적용해 두면 이런 수동 개입 자체가 필요 없어진다.
