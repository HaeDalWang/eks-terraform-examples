FROM alpine:latest

# 필요한 패키지 설치
RUN apk add --no-cache tzdata bash curl jq

# 타임존 설정
ENV TZ=UTC

# 작업 디렉토리 생성
RUN mkdir -p /app

# 로그 생성 스크립트 복사
COPY log-generator.sh /app/log-generator.sh

# 실행 권한 부여
RUN chmod +x /app/log-generator.sh

# 작업 디렉토리 설정
WORKDIR /app

# 기본 명령어 설정
CMD ["/bin/bash", "/app/log-generator.sh"]
