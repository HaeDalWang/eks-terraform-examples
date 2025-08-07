# MLOps 학습 진행 현황 및 새로운 학습 계획

## 📊 현재 진행 상황 분석

### ✅ 완료된 항목
- **1단계 (AI/ML 개념)**: 부분 완료
  - YouTube 3Blue1Brown 시리즈 시청 완료
  - Coursera Andrew Ng 강의 Week 1 완료
- **2단계 (Python 기초)**: 진행 중
  - 기본 ML 라이브러리 활용 가능 (NumPy, Pandas, Scikit-learn)
  - 집값 예측 모델 구현 완료 (`python/main.py`)

### 🔄 현재 위치
**2단계 후반 → 3단계 초반** (전체 로드맵의 약 30% 진행)

### 💪 확인된 강점
- DevOps/Kubernetes 경험으로 인프라 이해도 높음
- Terraform을 통한 EKS 환경 구축 완료
- Python 기초 문법과 ML 라이브러리 사용법 습득

---

## 🎯 다음 4주간 집중 학습 계획

### Week 1: Python ML 기초 완성
**목표**: 현재 작성한 코드를 확장하여 다양한 ML 알고리즘 경험

#### 실습 과제
```python
# 1. 현재 코드 개선
- 다중 특성 회귀 (집 크기 + 방 개수 + 위치)
- 교차 검증 (Cross-validation) 적용
- 특성 스케일링 (Feature Scaling)

# 2. 새로운 알고리즘 실습
- 분류 문제: 붓꽃 분류 (Iris Classification)
- 클러스터링: 고객 세분화 (K-means)
```

#### 구체적 할일
- [ ] `python/house_prediction_advanced.py` 생성
- [ ] `python/iris_classification.py` 생성  
- [ ] `python/customer_clustering.py` 생성
- [ ] 각 모델의 성능 비교 분석 문서 작성

### Week 2: 모델 배포 기초
**목표**: ML 모델을 API로 서비스하기

#### 실습 과제
```python
# Flask/FastAPI로 모델 서빙
- 집값 예측 API 서버 구축
- Docker 컨테이너화
- 간단한 웹 인터페이스 추가
```

#### 구체적 할일
- [ ] `python/api_server.py` (FastAPI 기반 API) ← 변경
- [ ] Pydantic 모델로 요청/응답 검증
- [ ] 자동 API 문서화 (Swagger UI)
- [ ] 비동기 처리 기초 학습

### Week 3: Kubernetes 배포
**목표**: 기존 K8s 지식을 활용한 ML 모델 배포

#### 실습 과제
```yaml
# Kubernetes 매니페스트 작성
- Deployment: ML API 서버
- Service: 로드밸런싱
- Ingress: 외부 접근
- ConfigMap: 모델 설정
```

#### 구체적 할일
- [ ] `manifest/ml-api-deployment.yaml` 생성
- [ ] `manifest/ml-api-service.yaml` 생성
- [ ] EKS 클러스터에 배포 및 테스트
- [ ] 모니터링 설정 (기본 메트릭)

### Week 4: MLOps 도구 도입
**목표**: MLflow를 활용한 모델 관리

#### 실습 과제
```python
# MLflow 실습
- 실험 추적 (Experiment Tracking)
- 모델 레지스트리 (Model Registry)  
- 모델 버전 관리
```

#### 구체적 할일
- [ ] MLflow 서버 구축 (Kubernetes)
- [ ] 기존 모델들을 MLflow로 관리
- [ ] 모델 A/B 테스트 환경 구축
- [ ] CI/CD 파이프라인 기초 설계

---

## 📋 주간 체크리스트

### Week 1 체크포인트
- [ ] 3개의 새로운 Python ML 스크립트 완성
- [ ] 각 알고리즘별 성능 비교 보고서 작성
- [ ] 코드 리뷰 및 리팩토링 완료

### Week 2 체크포인트  
- [ ] ML API 서버 로컬 실행 성공
- [ ] Docker 이미지 빌드 및 실행 확인
- [ ] API 문서화 (Swagger/OpenAPI)

### Week 3 체크포인트
- [ ] EKS에 ML 서비스 배포 성공
- [ ] 외부에서 API 호출 가능
- [ ] 기본 모니터링 대시보드 구축

### Week 4 체크포인트
- [ ] MLflow UI에서 실험 결과 확인 가능
- [ ] 모델 버전 관리 시스템 구축
- [ ] 자동화된 모델 배포 파이프라인 설계

---

## 🛠 필요한 기술 스택 정리

### 이미 보유한 기술
- ✅ Kubernetes (EKS)
- ✅ Terraform
- ✅ Docker
- ✅ Python 기초
- ✅ AWS 클라우드

### 새로 학습할 기술
- 🔄 **Flask/FastAPI**: API 서버 구축
- 🔄 **MLflow**: 모델 생명주기 관리
- 🔄 **Prometheus/Grafana**: ML 모델 모니터링
- 🔄 **GitHub Actions**: ML CI/CD

---

## 📚 추천 학습 자료

### Week 1-2: Python ML 심화
- **책**: "핸즈온 머신러닝 2판" (오렐리앙 제롱)
- **온라인**: Kaggle Learn (무료 마이크로 코스)
- **실습**: Kaggle 초급 대회 참여

### Week 3-4: MLOps 도구
- **공식 문서**: MLflow Documentation
- **YouTube**: "MLOps with Kubernetes" 시리즈
- **GitHub**: MLOps 예제 프로젝트들

---

## 🎯 4주 후 목표 상태

### 기술적 성과
- [ ] 3가지 이상의 ML 알고리즘 구현 경험
- [ ] Kubernetes에서 ML 서비스 운영 가능
- [ ] MLflow를 활용한 모델 관리 시스템 구축
- [ ] 기본적인 ML 모니터링 환경 구축

### 포트폴리오
- [ ] GitHub에 정리된 MLOps 프로젝트
- [ ] 실제 동작하는 ML API 서비스
- [ ] 학습 과정 블로그 포스팅 3편 이상

### 다음 단계 준비
- [ ] 딥러닝 학습 계획 수립
- [ ] GPU 워크로드 실습 환경 준비
- [ ] 고급 MLOps 도구 학습 로드맵 작성

---

## 💡 학습 효율화 팁

### 기존 강점 활용 전략
1. **Kubernetes 경험** → ML 워크로드 배포에 집중
2. **인프라 지식** → 모니터링/로깅 시스템 구축
3. **DevOps 경험** → CI/CD 파이프라인 설계

### 약점 보완 전략
1. **Python 실력** → 매일 30분 코딩 연습
2. **ML 이론** → 실습 위주로 필요한 것만 학습
3. **수학 기초** → 당장 필요한 통계만 학습

### 동기 유지 방법
- 매주 작은 성과물 완성하기
- 학습 내용을 블로그에 정리하기
- MLOps 커뮤니티에서 질문하고 답변하기
- 실무에 바로 적용 가능한 프로젝트 위주로 진행

---

## 📅 다음 리뷰 일정

**2주 후 중간 점검**: Week 1-2 진행 상황 리뷰  
**4주 후 최종 평가**: 전체 계획 달성도 평가 및 다음 단계 계획 수립

---

*"DevOps 경험이 있는 당신에게 MLOps는 새로운 도전이 아니라 기존 지식의 확장입니다. 차근차근 진행하면 반드시 성공할 수 있습니다!"* 🚀