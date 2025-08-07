# Week 1: NumPy 기초 따라하기
# 강의: https://www.youtube.com/watch?v=QUT1VHiLmmI

import numpy as np

print("=== NumPy 기초 실습 ===")

# 1. 배열 생성
print("\n1. 배열 생성")
arr1d = np.array([1, 2, 3, 4, 5])
print(f"1차원 배열: {arr1d}")

arr2d = np.array([[1, 2, 3], [4, 5, 6]])
print(f"2차원 배열:\n{arr2d}")

# 2. 배열 정보
print(f"배열 모양: {arr2d.shape}")
print(f"배열 타입: {arr2d.dtype}")
print(f"배열 크기: {arr2d.size}")

# 3. 배열 생성 함수들
zeros = np.zeros((2, 3))
ones = np.ones((2, 3))
full = np.full((2, 3), 7)

print(f"\n0으로 채운 배열:\n{zeros}")
print(f"1로 채운 배열:\n{ones}")
print(f"7로 채운 배열:\n{full}")

# 4. 수학 연산
arr = np.array([1, 2, 3, 4, 5])
print(f"\n원본 배열: {arr}")
# 기본적으로 모든 요소에 더해진다
print(f"배열 + 10: {arr + 10}")
print(f"배열 * 2: {arr * 2}") 
print(f"배열 제곱: {arr ** 2}")

# 5. 통계 함수
print(f"\n합계: {np.sum(arr)}")
print(f"평균: {np.mean(arr)}") 
print(f"최대값: {np.max(arr)}")
print(f"최소값: {np.min(arr)}")

print("\n✅ NumPy 기초 완료!")