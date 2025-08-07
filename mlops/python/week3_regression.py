# Week 3: 첫 번째 회귀 모델 따라하기 (상세 주석 버전)
# 강의: https://www.youtube.com/watch?v=0Lt9w-BxKFQ

# 필요한 라이브러리들을 가져오기
import numpy as np                    # 수치 계산용 (배열, 행렬)
import pandas as pd                   # 데이터 처리용 (엑셀 같은 테이블)
import matplotlib.pyplot as plt       # 그래프 그리기용
from sklearn.linear_model import LinearRegression      # 선형회귀 모델
from sklearn.model_selection import train_test_split   # 데이터를 훈련/테스트로 나누기
from sklearn.metrics import mean_squared_error, r2_score  # 모델 성능 측정

print("=== 첫 번째 회귀 모델 실습 ===")

# 1. 간단한 선형 회귀 (집 크기 → 집값)
print("\n1. 간단한 선형 회귀")

# 가상 데이터 생성
# reshape(-1, 1): 1차원 배열을 2차원으로 변환 (sklearn이 2차원 배열을 요구함)
# -1은 "알아서 계산해라"는 뜻, 1은 "열을 1개로 만들어라"는 뜻
# 결과: [30, 50, 70] → [[30], [50], [70]] 형태로 변환
house_size = np.array([30, 50, 70, 90, 110, 130, 150]).reshape(-1, 1)  # 평수 (입력 데이터)
house_price = np.array([1.5, 2.5, 3.5, 4.5, 5.5, 6.5, 7.5])  # 억원 (정답 데이터)

# 모델 생성 및 훈련
model = LinearRegression()  # 선형회귀 모델 객체 생성 (y = ax + b 형태의 직선을 찾는 모델)
model.fit(house_size, house_price)  # fit() = 훈련하기. 입력(평수)과 정답(집값)을 주고 패턴을 학습시킴
                                   # 결과: "평수가 1 증가하면 집값이 얼마나 오르는지" 학습됨

# 예측하기
predicted_price = model.predict(house_size)  # predict() = 예측하기. 훈련된 모델로 집값 예측
                                             # 입력: 평수 → 출력: 예상 집값

# 학습된 모델의 파라미터 확인
print(f"기울기 (평수당 가격): {model.coef_[0]:.2f}억원")  # coef_ = 기울기(계수). 평수 1 증가시 집값 증가량
print(f"절편: {model.intercept_:.2f}억원")              # intercept_ = y절편. 평수가 0일 때의 기본 집값
                                                      # 공식: 집값 = 기울기 × 평수 + 절편

# 새로운 집 크기로 예측해보기
new_size = np.array([[80], [120]])           # 80평, 120평 집 (2차원 배열로 만들어야 함)
new_prediction = model.predict(new_size)     # 훈련된 모델로 새로운 평수의 집값 예측
print(f"\n80평 집 예상 가격: {new_prediction[0]:.2f}억원")   # 첫 번째 예측값 (80평)
print(f"120평 집 예상 가격: {new_prediction[1]:.2f}억원")  # 두 번째 예측값 (120평)

# 2. 다중 회귀 모델 (여러 개의 입력 변수 사용)
print("\n\n2. 다중 회귀 모델")

# 가상의 주택 데이터 생성
np.random.seed(42)  # seed() = 랜덤 숫자를 고정. 실행할 때마다 같은 결과가 나오도록 함
n_samples = 100     # 생성할 데이터 개수 (100개 집 정보)

# 딕셔너리로 여러 특성의 데이터 생성
data = {
    # normal(평균, 표준편차, 개수) = 정규분포를 따르는 랜덤 숫자 생성
    '평수': np.random.normal(80, 20, n_samples),        # 평균 80평, 편차 20인 랜덤 평수
    # randint(최소, 최대, 개수) = 정수 랜덤 숫자 생성
    '방개수': np.random.randint(2, 6, n_samples),       # 2~5개 방 랜덤 생성
    '화장실개수': np.random.randint(1, 4, n_samples),   # 1~3개 화장실 랜덤 생성
    '지하철거리': np.random.normal(500, 200, n_samples), # 평균 500m, 편차 200m
    '학교거리': np.random.normal(300, 150, n_samples)    # 평균 300m, 편차 150m
}

# 집값 계산 (가상의 공식으로 실제같은 집값 만들기)
house_prices = (
    data['평수'] * 0.05 +                    # 평수가 클수록 집값 상승 (평수 × 0.05)
    data['방개수'] * 0.3 +                   # 방이 많을수록 집값 상승 (방개수 × 0.3)
    data['화장실개수'] * 0.2 -               # 화장실이 많을수록 집값 상승 (화장실 × 0.2)
    data['지하철거리'] * 0.001 -             # 지하철이 멀수록 집값 하락 (거리 × -0.001)
    data['학교거리'] * 0.0005 +              # 학교가 멀수록 집값 하락 (거리 × -0.0005)
    np.random.normal(0, 0.5, n_samples)     # 노이즈 추가 (현실적인 변동성)
)

# 딕셔너리를 pandas DataFrame으로 변환 (엑셀 테이블 같은 형태)
df = pd.DataFrame(data)  # DataFrame() = 딕셔너리를 테이블로 변환
df['집값'] = house_prices  # 계산된 집값을 새로운 열로 추가

print("데이터 샘플:")
print(df.head())  # head() = 처음 5행만 출력해서 데이터 확인

# 특성(입력)과 타겟(정답) 분리
X = df[['평수', '방개수', '화장실개수', '지하철거리', '학교거리']]  # X = 입력 특성들 (집의 정보)
y = df['집값']  # y = 예측하고 싶은 값 (집값)

# 훈련용과 테스트용 데이터로 분할
# train_test_split() = 데이터를 훈련용과 테스트용으로 나누기
# test_size=0.2 = 전체의 20%를 테스트용으로 사용
# random_state=42 = 랜덤 분할을 고정 (실행할 때마다 같은 결과)
X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)
# 결과: X_train(80개), X_test(20개), y_train(80개), y_test(20개)

# 다중 선형 회귀 모델 훈련
model = LinearRegression()  # 새로운 선형회귀 모델 생성
model.fit(X_train, y_train)  # fit() = 훈련용 데이터로 모델 학습
                            # 5개 특성(평수, 방개수 등)과 집값의 관계를 학습

# 테스트 데이터로 예측
y_pred = model.predict(X_test)  # predict() = 테스트용 입력으로 집값 예측
                               # 훈련에 사용하지 않은 새로운 20개 집의 가격 예측

# 모델 성능 평가
mse = mean_squared_error(y_test, y_pred)  # MSE = 실제값과 예측값의 차이의 제곱 평균
                                         # 값이 작을수록 정확한 예측
r2 = r2_score(y_test, y_pred)            # R² = 결정계수. 0~1 사이 값, 1에 가까울수록 좋음
                                         # 0.8이면 "80% 정확도"라고 생각하면 됨

print(f"\n모델 성능:")
print(f"평균 제곱 오차 (MSE): {mse:.4f}")  # MSE가 낮을수록 좋음
print(f"결정 계수 (R²): {r2:.4f}")        # R²가 1에 가까울수록 좋음

# 각 특성이 집값에 미치는 영향 분석
feature_importance = pd.DataFrame({  # DataFrame으로 표 만들기
    '특성': X.columns,              # 특성 이름들 (평수, 방개수 등)
    '계수': model.coef_             # coef_ = 각 특성의 계수 (영향력)
})                                  # 양수면 증가 효과, 음수면 감소 효과
print(f"\n특성별 중요도:")
# sort_values() = 계수의 절댓값 기준으로 내림차순 정렬 (영향력 큰 순서)
print(feature_importance.sort_values('계수', key=abs, ascending=False))

# 3. 결과를 그래프로 시각화
plt.figure(figsize=(10, 4))  # figure() = 그래프 캔버스 생성, 크기 10x4

# 첫 번째 그래프: 실제값 vs 예측값
plt.subplot(1, 2, 1)  # subplot(행, 열, 번호) = 1행 2열 중 첫 번째 그래프
plt.scatter(y_test, y_pred, alpha=0.7)  # scatter() = 산점도 그리기, alpha=투명도
# 완벽한 예측이라면 점들이 이 빨간 선 위에 있어야 함
plt.plot([y_test.min(), y_test.max()], [y_test.min(), y_test.max()], 'r--', lw=2)
plt.xlabel('실제 집값')    # x축 라벨
plt.ylabel('예측 집값')    # y축 라벨
plt.title('실제값 vs 예측값')  # 그래프 제목

# 두 번째 그래프: 평수 vs 집값 관계
plt.subplot(1, 2, 2)  # 1행 2열 중 두 번째 그래프
plt.scatter(df['평수'], df['집값'], alpha=0.7)  # 평수와 집값의 관계를 점으로 표시
plt.xlabel('평수')
plt.ylabel('집값')
plt.title('평수 vs 집값')

plt.tight_layout()  # 그래프들 사이 간격 자동 조정
# 그래프를 파일로 저장
plt.savefig('/Users/seungdo/work/eks-terraform-examples/mlops/python/regression_results.png')
print(f"\n그래프가 저장되었습니다: regression_results.png")

print("\n✅ 첫 번째 회귀 모델 완료!")