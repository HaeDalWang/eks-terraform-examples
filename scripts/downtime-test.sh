#!/bin/bash
#
# 무중단 배포 테스트 스크립트
# 지정된 URL로 1초마다 요청을 보내 응답 상태를 모니터링합니다.
#
# 사용법:
#   ./downtime-test.sh [URL] [INTERVAL]
#
# 예시:
#   ./downtime-test.sh https://app.sd.seungdobae.com/api/intgapp/ping/ 1
#

# 설정 (인자로 오버라이드 가능)
URL="${1:-https://app.sd.seungdobae.com/api/intgapp/ping/}"
INTERVAL="${2:-1}"
LOG_FILE="/tmp/downtime-test-$(date +%Y%m%d-%H%M%S).log"

# 색상
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo "=========================================="
echo -e "${CYAN}🚀 무중단 배포 테스트 시작${NC}"
echo "=========================================="
echo "URL: $URL"
echo "Interval: ${INTERVAL}s"
echo "Log: $LOG_FILE"
echo -e "종료: ${YELLOW}Ctrl+C${NC}"
echo "=========================================="
echo ""

# 카운터
total=0
success=0
fail=0

# 시작 시간
start_time=$(date +%s)

# 종료 시 통계 출력
cleanup() {
    echo ""
    echo "=========================================="
    echo -e "${CYAN}📊 최종 결과${NC}"
    echo "=========================================="
    echo "총 요청: $total"
    echo -e "성공: ${GREEN}$success${NC}"
    echo -e "실패: ${RED}$fail${NC}"
    if [ $total -gt 0 ]; then
        success_rate=$(echo "scale=2; $success * 100 / $total" | bc)
        echo "성공률: ${success_rate}%"
    fi
    
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    echo "테스트 시간: ${duration}초"
    echo "로그 파일: $LOG_FILE"
    echo "=========================================="
    exit 0
}

trap cleanup SIGINT SIGTERM

while true; do
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    ((total++))
    
    # curl 실행 (타임아웃 5초)
    response=$(curl -s -o /dev/null -w "%{http_code}|%{time_total}|%{remote_ip}" \
        --connect-timeout 3 \
        --max-time 5 \
        -H "Host: $(echo $URL | sed -e 's|https\?://||' -e 's|/.*||')" \
        "$URL" 2>/dev/null)
    
    http_code=$(echo "$response" | cut -d'|' -f1)
    time_total=$(echo "$response" | cut -d'|' -f2)
    remote_ip=$(echo "$response" | cut -d'|' -f3)
    
    # 결과 판정
    if [[ "$http_code" == "200" ]]; then
        ((success++))
        status="${GREEN}✅ OK${NC}"
    elif [[ "$http_code" == "000" ]]; then
        ((fail++))
        status="${RED}❌ TIMEOUT${NC}"
    else
        ((fail++))
        status="${RED}❌ FAIL${NC}"
    fi
    
    # 출력
    log_line="[$timestamp] #$total | HTTP: $http_code | Time: ${time_total}s | IP: $remote_ip"
    echo -e "$log_line | $status"
    echo "$log_line | HTTP_CODE=$http_code" >> "$LOG_FILE"
    
    sleep $INTERVAL
done
