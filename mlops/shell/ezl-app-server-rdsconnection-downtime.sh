#!/bin/bash
# downtime_monitor.sh

APP_URL="https://app.seungdobae.com/api/db/test"
LOG_FILE="downtime_log.txt"
DOWN_START_TIME=""
TOTAL_DOWNTIME=0

echo "🔍 DB 다운타임 모니터링 시작..."
echo "시간,상태,다운타임 시작,총 다운타임" > $LOG_FILE

while true; do
    timestamp=$(date '+%H:%M:%S')
    
    # API 호출
    response=$(curl -s $APP_URL)
    success=$(echo $response | jq -r '.test_result.success')
    
    if [ "$success" = "true" ]; then
        status="✅ 연결됨"
        
        # 다운타임이 있었다면 계산
        if [ ! -z "$DOWN_START_TIME" ]; then
            current_time=$(date +%s)
            downtime_seconds=$((current_time - DOWN_START_TIME))
            TOTAL_DOWNTIME=$((TOTAL_DOWNTIME + downtime_seconds))
            
            echo "$timestamp | $status | 다운타임 종료! 지속시간: ${downtime_seconds}초 | 총 다운타임: ${TOTAL_DOWNTIME}초"
            echo "$timestamp,$status,$DOWN_START_TIME,${downtime_seconds}초" >> $LOG_FILE
            
            # 다운타임 시작 시간 초기화
            DOWN_START_TIME=""
        else
            echo "$timestamp | $status | 정상 운영 중"
        fi
        
    else
        status="❌ 연결실패"
        
        # 다운타임 시작 시간 기록
        if [ -z "$DOWN_START_TIME" ]; then
            DOWN_START_TIME=$(date +%s)
            echo "$timestamp | $status | 다운타임 시작! ($(date '+%H:%M:%S'))"
            echo "$timestamp,$status,$(date '+%H:%M:%S'),-" >> $LOG_FILE
        else
            echo "$timestamp | $status | 다운타임 지속 중..."
        fi
    fi
    
    sleep 2
done