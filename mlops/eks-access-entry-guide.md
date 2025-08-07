# EKS AccessEntry 설정 단계별 가이드

## 개요
"saltware-kor" IAM Role에 EKS 클러스터 접근 권한을 부여하고, AWS 관리형 정책을 사용하여 간단하게 설정하는 가이드입니다.

## 1단계: IAM Policy 생성 및 연결

### 1.1 IAM Policy 생성
```bash
# AWS CLI를 사용한 IAM Policy 생성
aws iam create-policy \
    --policy-name EKSChecklistPolicy \
    --policy-document '{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": [
                    "eks:ListClusters",
                    "eks:DescribeCluster",
                    "eks:ListNodegroups",
                    "eks:DescribeNodegroup",
                    "ec2:Describe*",
                    "ec2:GetConsoleOutput",
                    "ec2:GetPasswordData",
                    "iam:Get*",
                    "iam:List*",
                    "vpc:Describe*"
                ],
                "Resource": "*"
            }
        ]
    }'
```

### 1.2 IAM Role에 Policy 연결
```bash
# Policy를 saltware-kor Role에 연결
aws iam attach-role-policy \
    --role-name saltware-kor \
    --policy-arn arn:aws:iam::YOUR_ACCOUNT_ID:policy/EKSChecklistPolicy
```

## 2단계: EKS AccessEntry 생성

### 2.1 AccessEntry 생성
```bash
# EKS AccessEntry 생성
aws eks create-access-entry \
    --cluster-name YOUR_CLUSTER_NAME \
    --principal-arn arn:aws:iam::YOUR_ACCOUNT_ID:role/saltware-kor \
    --type STANDARD
```

### 2.2 AWS 관리형 정책 연결
```bash
# AmazonEKSViewPolicy 연결 (읽기 전용 권한)
aws eks associate-access-policy \
    --cluster-name YOUR_CLUSTER_NAME \
    --principal-arn arn:aws:iam::YOUR_ACCOUNT_ID:role/saltware-kor \
    --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy \
    --access-scope type=cluster
```

## 3단계: 설정 검증

### 3.1 AccessEntry 확인
```bash
# AccessEntry 목록 확인
aws eks list-access-entries --cluster-name YOUR_CLUSTER_NAME

# 특정 AccessEntry 상세 정보 확인
aws eks describe-access-entry \
    --cluster-name YOUR_CLUSTER_NAME \
    --principal-arn arn:aws:iam::YOUR_ACCOUNT_ID:role/saltware-kor

# 연결된 정책 확인
aws eks list-associated-access-policies \
    --cluster-name YOUR_CLUSTER_NAME \
    --principal-arn arn:aws:iam::YOUR_ACCOUNT_ID:role/saltware-kor
```

### 3.2 kubeconfig 업데이트
```bash
# kubeconfig 업데이트
aws eks update-kubeconfig \
    --region YOUR_REGION \
    --name YOUR_CLUSTER_NAME \
    --role-arn arn:aws:iam::YOUR_ACCOUNT_ID:role/saltware-kor
```

### 3.3 권한 테스트
```bash
# saltware-kor Role을 사용하여 kubectl 명령 테스트
aws sts assume-role \
    --role-arn arn:aws:iam::YOUR_ACCOUNT_ID:role/saltware-kor \
    --role-session-name test-session

# 환경변수 설정 후 테스트 (위 명령 결과로 나온 값들 사용)
export AWS_ACCESS_KEY_ID=ASSUMED_ROLE_ACCESS_KEY
export AWS_SECRET_ACCESS_KEY=ASSUMED_ROLE_SECRET_KEY
export AWS_SESSION_TOKEN=ASSUMED_ROLE_SESSION_TOKEN

# 권한 테스트 (읽기 전용)
kubectl get nodes
kubectl get pods --all-namespaces
kubectl get services --all-namespaces
kubectl get deployments --all-namespaces
kubectl get configmaps --all-namespaces
kubectl get secrets --all-namespaces
```

## 4단계: EKS-Checklist 실행해보기