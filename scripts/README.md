# EKS AccessEntry 설정 스크립트

## 개요
`saltware-kor` IAM Role에 EKS 클러스터 접근 권한을 부여하는 자동화 스크립트입니다.

## 스크립트 기능
- IAM Role 자동 생성 (존재하지 않는 경우)
- IAM Policy 생성 및 연결
- EKS AccessEntry 생성
- AWS 관리형 정책 연결 (AmazonEKSAdminViewPolicy)
- kubeconfig 자동 업데이트

## 사용법

### 기본 사용법
```bash
./setup-eks-access.sh -c CLUSTER_NAME -a ACCOUNT_ID -r REGION
```

### 파라미터
- `-c`: EKS 클러스터 이름 (필수)
- `-a`: AWS 계정 ID (필수)
- `-r`: AWS 리전 (필수)
- `-h`: 도움말 출력

### 사용 예시
```bash
# mlops 클러스터에 대한 접근 권한 설정
./setup-eks-access.sh -c mlops -a 863422182520 -r ap-northeast-2

# 다른 클러스터 예시
./setup-eks-access.sh -c my-cluster -a 123456789012 -r us-west-2
```

## 실행 전 준비사항
1. AWS CLI 설치 및 구성
2. 적절한 IAM 권한 (IAM Role/Policy 생성, EKS 관리 권한)
3. kubectl 설치

## 생성되는 리소스
- **IAM Role**: `saltware-kor`
- **IAM Policy**: `EKSChecklistPolicy`
- **EKS AccessEntry**: 클러스터별로 생성
- **연결된 정책**: `AmazonEKSAdminViewPolicy`

## 권한 테스트
스크립트 실행 후 다음 명령으로 권한을 확인할 수 있습니다:
```bash
kubectl get nodes
kubectl get pods --all-namespaces
kubectl get services --all-namespaces
```

## 문제 해결

### AccessEntry 삭제 (재설정 시)
```bash
aws eks delete-access-entry --cluster-name CLUSTER_NAME --principal-arn arn:aws:iam::ACCOUNT_ID:role/saltware-kor
```

### Role 삭제 (완전 재생성 시)
```bash
aws iam detach-role-policy --role-name saltware-kor --policy-arn arn:aws:iam::ACCOUNT_ID:policy/EKSChecklistPolicy
aws iam delete-role --role-name saltware-kor
```

## 주의사항
- 스크립트는 기존 리소스가 있으면 건너뛰고 진행합니다
- Role 생성 후 AWS 전파를 위해 10초 대기합니다
- AWS CLI pager가 자동으로 비활성화됩니다