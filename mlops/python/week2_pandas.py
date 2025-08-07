# Week 2: Pandas 기초 따라하기
# 강의: https://www.youtube.com/playlist?list=PL-osiE80TeTsWmV9i9c58mdDCSskIFdDS

import pandas as pd
import numpy as np

print("=== Pandas 기초 실습 ===")

# 1. 데이터프레임 생성
print("\n1. 데이터프레임 생성")
data = {
    '이름': ['김철수', '이영희', '박민수', '최지영'],
    '나이': [25, 30, 35, 28],
    '도시': ['서울', '부산', '대구', '인천'],
    '연봉': [3000, 4000, 5000, 3500]
}

df = pd.DataFrame(data)
# dataframe?
print(df)

# 2. 데이터 탐색
print(f"\n2. 데이터 정보")
print(f"데이터 모양: {df.shape}") # 행렬을 보여줌
print(f"컬럼명: {list(df.columns)}") # 컬럼 즉 첫번졔 열들의 값 
print(f"\n데이터 타입:")
print(df.dtypes)

# 3. 데이터 선택
print(f"\n3. 데이터 선택")
print(f"이름 컬럼:\n{df['이름']}") # 컬럼을 지정 후 나열
print(f"\n첫 2행:\n{df.head(2)}") # 첫번쨰 부터 2개까지
print(f"\n나이가 30 이상인 사람:\n{df[df['나이'] >= 30]}") 

# 4. 통계 정보
print(f"\n4. 통계 정보")
print(df.describe()) # 예시용 

# 5. 새로운 컬럼 추가
df['연봉등급'] = df['연봉'].apply(lambda x: '고액' if x >= 4000 else '일반')
print(f"\n5. 연봉등급 추가:")
print(df)

# 6. 그룹별 집계
print(f"\n6. 도시별 평균 연봉:")
city_avg = df.groupby('도시')['연봉'].mean()
print(city_avg)

print("\n✅ Pandas 기초 완료!")