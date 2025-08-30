#!/bin/bash

# Secret에서 DB_PASSWORD 읽기 함수
get_db_password() {
  if [[ -f "/mnt/secrets-store/DB_PASSWORD" ]]; then
    cat /mnt/secrets-store/DB_PASSWORD
  else
    echo "SECRET_NOT_FOUND"
  fi
}

# 시작 시 Secret 확인
echo "$(date -Iseconds | cut -d'T' -f1)T$(date -Iseconds | cut -d'T' -f2 | cut -d'+' -f1) | INFO | app.py:1 | Application starting... Checking secrets..."

# Secrets 디렉토리 내용 확인
if [[ -d "/mnt/secrets-store" ]]; then
  echo "$(date -Iseconds | cut -d'T' -f1)T$(date -Iseconds | cut -d'T' -f2 | cut -d'+' -f1) | DEBUG | app.py:5 | Available secrets: $(ls -la /mnt/secrets-store/ | grep -v '^total' | wc -l) files"
  if [[ -f "/mnt/secrets-store/DB_PASSWORD" ]]; then
    DB_PWD=$(get_db_password)
    echo "$(date -Iseconds | cut -d'T' -f1)T$(date -Iseconds | cut -d'T' -f2 | cut -d'+' -f1) | INFO | app.py:7 | Database connection initialized with password: ${DB_PWD}"
  else
    echo "$(date -Iseconds | cut -d'T' -f1)T$(date -Iseconds | cut -d'T' -f2 | cut -d'+' -f1) | WARNING | app.py:9 | DB_PASSWORD secret not found, using default"
  fi
else
  echo "$(date -Iseconds | cut -d'T' -f1)T$(date -Iseconds | cut -d'T' -f2 | cut -d'+' -f1) | ERROR | app.py:11 | Secrets store not mounted at /mnt/secrets-store"
fi

counter=0
while true; do            
  case $counter in
    0)
      echo "$(date -Iseconds | cut -d'T' -f1)T$(date -Iseconds | cut -d'T' -f2 | cut -d'+' -f1) | INFO | ezlwalk.py:188 | EzlwalkDailyMission Check DailyUserStepCountLog updated: user_id=527972 device_id=603148 last_date=$(date -Iseconds | cut -d'T' -f1) step_count=2812"
      ;;
    1)
      echo "$(date -Iseconds | cut -d'T' -f1)T$(date -Iseconds | cut -d'T' -f2 | cut -d'+' -f1) | DEBUG | hyphen.py:75 | {\"sucsFalr\": \"success\", \"rsltCd\": \"HCO000\", \"rsltMesg\": \"정상으로 처리되었어요\", \"rsltObj\": {\"uscoSno\": 23, \"mbrID\": \"prod:59bdc3d4-0126-4fb6-a77b-e05d40917d8c\", \"mbrNm\": \"****\", \"rmdAmt\": 106, \"ttlPsbAmt\": 106, \"ttlExAmt\": 0, \"psbFAmt\": 106, \"psbPAmt\": 0, \"payAmt\": 0, \"freeAmt\": 106, \"exPAmt\": 0, \"exFAmt\": 0}}"
      ;;
    2)
      echo "$(date -Iseconds | cut -d'T' -f1)T$(date -Iseconds | cut -d'T' -f2 | cut -d'+' -f1) | INFO | glogging.py:363 | 10.243.12.131 - - \"GET /api/intgapp/ping/ HTTP/1.1\" 200 4 | duration=0.001143"
      ;;
    3)
      # DB 패스워드를 포함한 로그 (주기적으로)
      DB_PWD=$(get_db_password)
      echo "$(date -Iseconds | cut -d'T' -f1)T$(date -Iseconds | cut -d'T' -f2 | cut -d'+' -f1) | INFO | database.py:42 | Database health check completed with password: ${DB_PWD} | status=OK"
      ;;
    4)
      echo "$(date -Iseconds | cut -d'T' -f1)T$(date -Iseconds | cut -d'T' -f2 | cut -d'+' -f1) | WARNING | log.py:241 | Unauthorized: /v1/intgapp/ezlwalk/users/step_count/"
      ;;
    5)
      echo "$(date -Iseconds | cut -d'T' -f1)T$(date -Iseconds | cut -d'T' -f2 | cut -d'+' -f1) | INFO | glogging.py:363 | 10.243.11.125 - - \"POST /api/intgapp/ezlwalk/users/mission/daily/ HTTP/1.1\" 200 263 | duration=0.035754"
      ;;
    6)
      echo "{\"timestamp\": \"$(date -Iseconds)\", \"level\": \"INFO\", \"message\": \"User action completed\", \"user_id\": 12345, \"action\": \"login\", \"ip\": \"10.243.11.125\"}"
      ;;
    7)
      # 환경변수도 체크해보기
      if [[ -n "$DB_PASSWORD" ]]; then
        echo "$(date -Iseconds | cut -d'T' -f1)T$(date -Iseconds | cut -d'T' -f2 | cut -d'+' -f1) | DEBUG | config.py:15 | Environment DB_PASSWORD loaded: ${DB_PASSWORD}"
      else
        echo "$(date -Iseconds | cut -d'T' -f1)T$(date -Iseconds | cut -d'T' -f2 | cut -d'+' -f1) | DEBUG | config.py:17 | Environment DB_PASSWORD not set"
      fi
      ;;
    8)
      echo ""
      ;;
  esac
  counter=$((($counter + 1) % 9))
  sleep 3
done
