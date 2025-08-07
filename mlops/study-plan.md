# 추천 학습 순서

## 현재 학습자 상태
AI/ML 이 뭔지모름
MLops의 ML이 무엇을 의미하는지도 모름
AI 개발 경험 없음
GPU 워크로드 경험 없음
python 코딩 실력은 초급자
그외 AI/ML을 히해하기 위한 기초지식 전무

## 보유한 강점
✅ Cloud 지식 보유  
✅ Kubernetes 지식 보유 (MLOps의 핵심!)  
✅ Infrastructure 이해도 (Terraform 경험)

---

## 📚 MLOps 마스터 로드맵

### 1단계: AI/ML 개념 잡기 (2-3주)
**목표**: "ML이 뭔지, 왜 필요한지" 이해하기

#### 핵심 개념
- **인공지능(AI)**: 사람처럼 생각하고 학습하는 컴퓨터 시스템
- **머신러닝(ML)**: AI를 구현하는 방법 중 하나. 데이터로부터 패턴을 학습
- **딥러닝(DL)**: ML의 한 분야. 인간의 뇌 신경망을 모방

#### 쉬운 예제로 이해하기
```
🎯 넷플릭스 추천 시스템 예제:
- 데이터: 사용자가 본 영화들 + 평점
- 목표: 사용자가 좋아할 만한 새로운 영화 추천
- ML 과정: 
  1. 과거 데이터 학습 → 2. 패턴 발견 → 3. 새로운 추천 생성
```

#### 실습 미션
- [완료!] YouTube에서 "머신러닝이 뭔가요?" 3Blue1Brown 시리즈 시청
- [1주차 완료] Coursera Andrew Ng 머신러닝 강의 Week 1 완료

---

### 2단계: Python 기초 다지기 (3-4주)
**목표**: ML에 필요한 Python 스킬 습득

#### 핵심 라이브러리
- **NumPy**: 수치 계산 (행렬, 배열)
- **Pandas**: 데이터 조작 (Excel 같은 역할)
- **Matplotlib**: 그래프 그리기
- **Scikit-learn**: 머신러닝 툴킷

#### 실습 미션
- [ ] Python 기초 문법 복습 (리스트, 딕셔너리, 함수)
- [ ] NumPy 배열 다루기 연습
- [ ] Pandas로 간단한 CSV 파일 읽고 분석해보기
- [ ] Matplotlib으로 그래프 그려보기

---

### 3단계: 머신러닝 기초 실습 (4-5주)
**목표**: 실제로 ML 모델을 만들어보기

#### 핵심 개념
- **지도학습**: 정답이 있는 데이터로 학습 (분류, 회귀)
- **비지도학습**: 정답 없이 패턴 찾기 (클러스터링)
- **모델 평가**: 만든 모델이 얼마나 좋은지 측정

#### 실전 프로젝트 예제
```
🏠 집값 예측 프로젝트:
입력: 집 크기, 방 개수, 위치 등
출력: 집값 예측
사용할 알고리즘: 선형 회귀 (Linear Regression)
```

#### 실습 미션
- [ ] Scikit-learn으로 첫 번째 모델 만들기
- [ ] 집값 예측 모델 완성하기
- [ ] 모델 성능 평가해보기 (RMSE, R² 점수)
- [ ] 결과를 그래프로 시각화하기

---

### 4단계: MLOps 개념과 도구 (3-4주)
**목표**: ML 모델을 실제 서비스에 배포하고 관리하기

#### 핵심 개념 (드디어 당신의 강점 활용!)
- **MLOps**: ML + DevOps. ML 모델의 전체 생명주기 관리
- **모델 배포**: 만든 모델을 실제 서비스에서 사용할 수 있게 하기
- **모델 모니터링**: 배포된 모델이 잘 작동하는지 계속 지켜보기
- **CI/CD for ML**: 코드뿐만 아니라 데이터와 모델도 자동화

#### 실제 업무 시나리오
```
🚀 실제 회사에서 일어나는 일:
1. 데이터 사이언티스트가 모델 개발 (Jupyter Notebook)
2. MLOps 엔지니어(당신!)가 모델을 Kubernetes에 배포
3. API로 서비스하여 실제 사용자들이 이용
4. 모델 성능 모니터링 및 재배포
```

#### MLOps 도구 스택 (기존 지식 + α)
- **컨테이너**: Docker (이미 익숙할 거예요!)
- **오케스트레이션**: Kubernetes (당신의 강점!)
- **ML 특화 도구**: 
  - MLflow (모델 추적 및 관리)
  - Kubeflow (Kubernetes에서 ML 워크플로우)
  - Seldon Core (모델 배포)

#### 실습 미션
- [ ] 간단한 ML 모델을 Docker 컨테이너로 만들기
- [ ] Flask/FastAPI로 모델 API 서버 만들기
- [ ] Kubernetes에 모델 서비스 배포해보기
- [ ] MLflow로 모델 버전 관리해보기

---

### 5단계: GPU & 고급 MLOps (4-5주)
**목표**: 딥러닝과 대규모 ML 시스템 다루기

#### 핵심 개념
- **GPU 워크로드**: 딥러닝 모델 훈련에는 GPU가 필수
- **분산 훈련**: 큰 모델은 여러 GPU/서버에서 함께 훈련
- **모델 서빙 최적화**: 빠른 추론을 위한 모델 경량화

#### Kubernetes + GPU 활용
```yaml
# GPU를 사용하는 Pod 예제
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: gpu-container
    image: tensorflow/tensorflow:latest-gpu
    resources:
      limits:
        nvidia.com/gpu: 1  # GPU 1개 요청
```

#### 실습 미션
- [ ] TensorFlow/PyTorch 기초 익히기
- [ ] 간단한 신경망 모델 훈련해보기
- [ ] EKS에서 GPU 노드 그룹 설정해보기
- [ ] 분산 훈련 실험해보기

---

## 🎯 실전 프로젝트: End-to-End MLOps 파이프라인

### 최종 미션 (2-3주)
**목표**: 실제 회사에서 사용할 수 있는 MLOps 시스템 구축

#### 프로젝트 구조
```
📊 이미지 분류 서비스 만들기:
1. 데이터 수집 및 전처리 자동화
2. 모델 훈련 파이프라인 (Kubeflow)
3. 모델 배포 및 API 서비스 (Kubernetes)
4. 모니터링 및 로깅 (Prometheus + Grafana)
5. CI/CD 파이프라인 (GitHub Actions)
```

#### 최종 아키텍처
```
GitHub → CI/CD → Container Registry → Kubernetes
    ↓
Data Pipeline → Model Training → Model Registry → Model Serving
    ↓
Monitoring ← Model Performance ← Production Traffic
```

---

## 📝 학습 진행 체크리스트

### Week 1-3: AI/ML 기초
- [ ] 1단계 완료 (AI/ML 개념)
- [ ] 간단한 용어집 작성
- [ ] 첫 번째 Coursera 강의 완료

### Week 4-7: Python 실력 향상  
- [ ] 2단계 완료 (Python 기초)
- [ ] NumPy, Pandas 자유자재로 사용
- [ ] 간단한 데이터 시각화 가능

### Week 8-12: ML 실전
- [ ] 3단계 완료 (ML 기초 실습)
- [ ] 최소 3개의 ML 프로젝트 완성
- [ ] 모델 평가 개념 이해

### Week 13-16: MLOps 입문
- [ ] 4단계 완료 (MLOps 기초)
- [ ] Kubernetes에 ML 모델 배포 성공
- [ ] MLflow 활용 경험

### Week 17-21: 고급 MLOps
- [ ] 5단계 완료 (GPU & 고급)
- [ ] 딥러닝 모델 훈련 경험
- [ ] 분산 시스템 이해

### Week 22-24: 최종 프로젝트
- [ ] End-to-End MLOps 파이프라인 구축
- [ ] GitHub에 포트폴리오 업로드
- [ ] 실무 준비 완료

---

## 💡 학습 팁

### 당신만의 장점 활용하기
- ✅ **Infrastructure 경험**: MLOps의 가장 어려운 부분을 이미 알고 있어요!
- ✅ **Kubernetes 지식**: 대부분 ML 엔지니어들이 어려워하는 부분
- ✅ **Cloud 이해도**: AWS EKS, ECS 등 ML 워크로드 배포에 큰 도움

### 효율적인 학습 전략
1. **이론 30% + 실습 70%**: 개념보다는 직접 해보는 것이 중요
2. **매일 조금씩**: 하루 1-2시간씩 꾸준히
3. **포트폴리오 중심**: 모든 프로젝트를 GitHub에 정리
4. **커뮤니티 활용**: MLOps Korea, 캐글 등에서 질문하고 답변하기

---

