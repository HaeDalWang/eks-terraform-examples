# Makefile 문법 설명서

## 기본 문법

### 1. 주석
```makefile
# 이것은 주석입니다
```

### 2. 타겟(Target) 정의
```makefile
타겟이름: 의존성
	명령어
```

### 3. 특별한 설정들

#### .PHONY
```makefile
.PHONY: help login plan apply
```
- 실제 파일이 아닌 '명령어'라는 것을 Make에게 알려줌
- 같은 이름의 파일이 있어도 명령어를 실행하도록 보장

#### .DEFAULT_GOAL
```makefile
.DEFAULT_GOAL := help
```
- `make`만 입력했을 때 실행할 기본 타겟 지정

### 4. 의존성(Dependencies)
```makefile
apply: login  # apply를 실행하기 전에 login을 먼저 실행
	terraform apply
```

### 5. @ 기호
```makefile
@echo "메시지"  # 명령어 자체를 출력하지 않고 결과만 출력
echo "메시지"   # 명령어도 함께 출력
```

## 우리 Makefile 분석

### login 타겟
```makefile
login: ## ECR Public 로그인
	@echo "🔐 ECR Public 로그인 중..."
	@aws ecr-public get-login-password --region us-east-1 | helm registry login --username AWS --password-stdin public.ecr.aws
	@echo "✅ 로그인 완료"
```

### apply 타겟 (의존성 있음)
```makefile
apply: login ## Terraform 적용 (자동 로그인 포함)
	@echo "🚀 Terraform 적용 중..."
	terraform apply
```
- `apply`를 실행하면 먼저 `login`이 자동 실행됨

### morning-deploy 타겟 (복합 의존성)
```makefile
morning-deploy: login plan apply-auto ## 🌅 아침 배포
	@echo "☕ 아침 배포 완료! 커피 한 잔 하세요~"
```
- 실행 순서: login → plan → apply-auto → 완료 메시지

