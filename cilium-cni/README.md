# Cilium CNI을 사용하는 예제

kube-proxy replacement 모드 + BYOCNI Clium 기반 설치
관리형 노드그룹은 coredns + karpenter + cilium 만 설치 그외 모든것은 karpen node로

또한 api-gateway or ingress 또한 cilium
Service Mesh을 사용 가능하도록하는 구성 

---
### cluster 구성
조건
- fargate coredns을 못씀 < fargate가 아직 ebpf기반으로 안됨, 즉 무조건 노드그룹으로

Cilium CNI을 사용하는 클러스터를 만들기 위해서는 아래 순서로 만들 필요가 있습니다
순서가 지켜지지 않으면 재대로 노드와 일부 애드온이 작동하지 않을 수 있습니다
1. EKS 클러스터 생성
2. 3 소요 동시 설치 (원래는 순서대로인데 terraform 구조상 depenon을 걸면 락걸림)
- CoreDNS 애드온 생성
- Cilium CNI 애드온 생성
- NodeGroup 생성 (클러스터와 같이 생성하면 노드 조인이 안됨)
3. Karpenter 생성
4. Karpenter 기본 노드 클래스 생성
5. Karpenter 기본 노드 풀 생성
6. 그외EKS-Addon 생성
그외 Cilium을 사용하면서 주의할 점
ref: https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/

eks.tf을 보면서 이해하기 순서대로 작성되어 잇음

### Cilium 컴포넌트 역할 및 스케줄링 설정

**1. 오퍼레이터 (Cilium Operator)**
- **역할**: IPAM(IP 관리), CRD 관리, 가비지 컬렉션 등 클러스터 전역 제어 플레인 역할.
- **Toleration/Label**: 안정적인 시스템 노드(예: 관리형 노드그룹)에 배치되도록 `nodeSelector`를 설정하고, `CriticalAddonsOnly` 등의 Toleration을 부여합니다.

**2. 엔보이 (Cilium Envoy)**
- **역할**: L7 트래픽 처리 (Ingress, Gateway API, Service Mesh).
- **Toleration/Label**: 보통 Agent 내장 혹은 별도 DaemonSet으로 실행됩니다. 트래픽을 처리해야 하는 모든 노드에 배치되도록 설정합니다.

**3. 실리움 에이전트 (Cilium Agent)**
- **역할**: 각 노드의 네트워크 인터페이스 제어, eBPF 프로그램 로드 (필수 컴포넌트).
- **Toleration/Label**: **가장 중요.** 네트워크가 없으면 노드가 동작하지 않으므로, 모든 노드(Tainted 포함)에 실행되도록 `operator: Exists`로 **모든 Toleration을 허용**해야 합니다.

### Karpenter랑 사용 시 주의
카펜터는 cilium cni 정상조건따위 모름 그러므로 노드풀 작성 시 무조건 테인트를 추가해야함
Cilium이 준비될 때까지 기다릴 수 있도록 테인트를 명시
```
taints:
- key: "node.cilium.io/agent-not-ready"
value: "true"
effect: "NoExecute"
```