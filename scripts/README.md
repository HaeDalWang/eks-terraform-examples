# Scripts

유틸리티 스크립트 모음

## downtime-test.sh

무중단 배포 테스트를 위한 스크립트입니다.  
지정된 URL로 주기적으로 요청을 보내 응답 상태를 모니터링합니다.

### 사용법

```bash
# 기본 사용 (1초 간격)
./scripts/downtime-test.sh

# URL 지정
./scripts/downtime-test.sh https://your-app.example.com/health

# URL과 간격 지정 (0.5초)
./scripts/downtime-test.sh https://your-app.example.com/health 0.5
```

### 출력 예시

```
==========================================
🚀 무중단 배포 테스트 시작
==========================================
URL: https://app.sd.seungdobae.com/api/intgapp/ping/
Interval: 1s
Log: /tmp/downtime-test-20260111-123456.log
종료: Ctrl+C
==========================================

[2026-01-11 12:34:56] #1 | HTTP: 200 | Time: 0.125s | IP: 3.35.xxx.xxx | ✅ OK
[2026-01-11 12:34:57] #2 | HTTP: 200 | Time: 0.098s | IP: 3.35.xxx.xxx | ✅ OK
[2026-01-11 12:34:58] #3 | HTTP: 502 | Time: 0.045s | IP: 3.35.xxx.xxx | ❌ FAIL
[2026-01-11 12:34:59] #4 | HTTP: 200 | Time: 0.112s | IP: 3.35.xxx.xxx | ✅ OK

^C
==========================================
📊 최종 결과
==========================================
총 요청: 100
성공: 99
실패: 1
성공률: 99.00%
테스트 시간: 100초
로그 파일: /tmp/downtime-test-20260111-123456.log
==========================================
```

### 기능

| 항목 | 설명 |
|------|------|
| HTTP 상태 | 200이면 성공, 그 외 실패 |
| 응답 시간 | 각 요청의 소요 시간 |
| Remote IP | 요청이 도달한 LB/서버 IP |
| 로그 파일 | `/tmp/`에 자동 저장 |
| 종료 | `Ctrl+C` 누르면 통계 출력 |

### 활용 시나리오

- 배포 중 서비스 가용성 모니터링
- Ingress 전환 시 무중단 검증
- 롤링 업데이트 테스트
- Load Balancer 헬스체크 검증
