# Lambda Functions

이 폴더는 RDS 비밀번호 자동 변경 시스템의 Lambda 함수들을 포함합니다.

## 파일 구조

```
lambdas/
├── README.md                           # 이 파일
└── rds_password_rotation.py            # 30일마다 RDS 비밀번호 변경
```

## Lambda 함수 설명

### rds_password_rotation.py
- **목적**: 30일마다 RDS 비밀번호를 자동으로 변경
- **트리거**: EventBridge Scheduler
- **기능**:
  - 16자리 복잡한 비밀번호 생성 (대소문자, 숫자, 특수문자 보장)
  - RDS 인스턴스 비밀번호 변경 (`modify_db_instance`)
  - RDS 수정 완료 대기 (최대 5분)
  - Secrets Manager의 `ezl-app-server-secrets`에 새 비밀번호 업데이트 (`put_secret_value`)
  - 실제 DB 연결 테스트로 비밀번호 변경 검증
  - 실패 시 상세한 에러 로깅 및 알림

## 환경 변수

### rds_password_rotation.py
- `DB_INSTANCE_IDENTIFIER`: RDS 인스턴스 식별자
- `SECRETS_MANAGER_SECRET`: Secrets Manager 시크릿 이름

## 배포 방법

### 1. Lambda 패키지 빌드
먼저 Lambda 패키지를 빌드해야 합니다:

```bash
cd lambdas

# 가상환경 활성화 (선택사항)
python3 -m venv venv
source venv/bin/activate

# 또는 기존 가상환경 활성화
# source your_venv/bin/activate

# Lambda 패키지 빌드
./build.sh
```

이 스크립트는:
- Python 파일을 `lambda_function.py`로 복사
- `requirements.txt`의 의존성을 설치
- 모든 파일을 ZIP으로 압축
- `build/rds_password_rotation.zip` 파일 생성

### 2. Terraform 배포
Lambda 패키지 빌드 후 Terraform으로 배포:

```bash
cd ..
terraform apply
```

## 로그 확인

CloudWatch Logs에서 Lambda 함수 실행 로그를 확인할 수 있습니다:

```bash
# RDS 비밀번호 변경 Lambda 로그
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/mlops-rds-password-rotation"
```

## 수동 테스트

Lambda 함수를 수동으로 테스트할 수 있습니다:

```bash
# RDS 비밀번호 변경 테스트
aws lambda invoke \
  --function-name mlops-rds-password-rotation \
  --payload '{"test": true}' \
  response.json
```

## 보안 고려사항

- Lambda 함수는 최소 권한 원칙에 따라 필요한 권한만 부여
- RDS 비밀번호는 16자리 복잡한 문자열로 생성
- Secrets Manager를 통해 비밀번호 안전하게 저장
- CloudWatch Logs를 통한 실행 로그 추적
