# Terraform 관리 Makefile

.PHONY: help login plan apply destroy fmt validate

# 기본 타겟
.DEFAULT_GOAL := help

help: ## 도움말 표시
	@echo "사용 가능한 명령어:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

login: ## ECR Public 로그인
	@echo "🔐 ECR Public 로그인 중..."
	@aws ecr-public get-login-password --region us-east-1 | helm registry login --username AWS --password-stdin public.ecr.aws
	@echo "✅ 로그인 완료"

plan: login ## Terraform 계획 확인 (자동 로그인 포함)
	@echo "📋 Terraform 계획 확인 중..."
	terraform plan

apply: login ## Terraform 적용 (자동 로그인 포함)
	@echo "🚀 Terraform 적용 중..."
	terraform apply

apply-auto: login ## Terraform 자동 적용 (확인 없이)
	@echo "🚀 Terraform 자동 적용 중..."
	terraform apply -auto-approve

destroy: login ## Terraform 리소스 삭제
	@echo "💥 Terraform 리소스 삭제 중..."
	terraform destroy

fmt: ## Terraform 코드 포맷팅
	terraform fmt -recursive

validate: ## Terraform 코드 유효성 검사
	terraform validate

init: ## Terraform 초기화
	terraform init

refresh: login ## Terraform 상태 새로고침
	terraform refresh

# 아침 배포용 원스톱 명령어
morning-deploy: login plan apply-auto ## 🌅 아침 배포 (로그인 → 계획 → 자동 적용)
	@echo "☕ 아침 배포 완료! 커피 한 잔 하세요~"
