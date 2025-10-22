#!/bin/bash

# =============================================================================
# Linkerd mTLS 인증서 생성 스크립트
# =============================================================================
# 
# 이 스크립트는 Linkerd mTLS에 필요한 Trust Anchor와 Issuer 인증서를 생성합니다.
# 생성된 인증서는 회사 비밀저장소에 백업하고 AWS Secrets Manager에 등록해야 합니다.
#
# 출력:
#   - ca-cert.pem (Trust Anchor 인증서)
#   - ca-key.pem (Trust Anchor 개인키)
#   - issuer-cert.pem (Issuer 인증서)
#   - issuer-key.pem (Issuer 개인키)
#   - linkerd-certs.json (AWS Secrets Manager 등록용 JSON)
# =============================================================================

set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 로그 함수들
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 스크립트 디렉토리로 이동
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CERTS_DIR="$PROJECT_ROOT/certs"

log_info "Linkerd mTLS 인증서 생성을 시작합니다..."
log_info "프로젝트 루트: $PROJECT_ROOT"
log_info "인증서 저장 디렉토리: $CERTS_DIR"

# 인증서 디렉토리 생성
mkdir -p "$CERTS_DIR"
cd "$CERTS_DIR"

# 기존 인증서 파일이 있으면 백업
if [ -f "ca-cert.pem" ] || [ -f "ca-key.pem" ] || [ -f "issuer-cert.pem" ] || [ -f "issuer-key.pem" ]; then
    log_warning "기존 인증서 파일이 발견되었습니다. 백업을 생성합니다..."
    BACKUP_DIR="backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    mv -f *.pem "$BACKUP_DIR/" 2>/dev/null || true
    mv -f *.csr "$BACKUP_DIR/" 2>/dev/null || true
    mv -f *.json "$BACKUP_DIR/" 2>/dev/null || true
    log_success "백업 완료: $BACKUP_DIR"
fi

log_info "1/4 Trust Anchor 인증서 생성 중..."
openssl req -x509 -newkey rsa:4096 -keyout ca-key.pem -out ca-cert.pem -days 365 -nodes \
    -subj "/CN=identity.linkerd.cluster.local" \
    -addext "keyUsage=critical,keyCertSign,cRLSign" \
    -addext "basicConstraints=critical,CA:true"

log_success "Trust Anchor 인증서 생성 완료"

log_info "2/4 Issuer 개인키 생성 중..."
openssl genrsa -out issuer-key.pem 4096

log_success "Issuer 개인키 생성 완료"

log_info "3/4 Issuer 인증서 서명 요청(CSR) 생성 중..."
openssl req -new -key issuer-key.pem -out issuer.csr \
    -subj "/CN=identity.linkerd.cluster.local" \
    -addext "keyUsage=critical,keyCertSign,cRLSign,digitalSignature,keyEncipherment" \
    -addext "basicConstraints=critical,CA:true,pathlen:0"

log_success "Issuer CSR 생성 완료"

log_info "4/4 Trust Anchor로 Issuer 인증서 서명 중..."
openssl x509 -req -in issuer.csr -CA ca-cert.pem -CAkey ca-key.pem -CAcreateserial \
    -out issuer-cert.pem -days 365 \
    -extensions v3_ca -extfile <(cat <<EOF
[v3_ca]
keyUsage=critical,keyCertSign,cRLSign,digitalSignature,keyEncipherment
basicConstraints=critical,CA:true,pathlen:0
EOF
)

log_success "Issuer 인증서 서명 완료"

# 임시 파일 정리
rm -f issuer.csr

log_info "AWS Secrets Manager 등록용 JSON 파일 생성 중..."

# 인증서 내용을 안전하게 JSON으로 변환
# 1. 임시 JSON 파일 생성 (jq를 사용하여 안전하게 처리)
TEMP_JSON=$(mktemp)

# 2. jq를 사용하여 JSON 생성 (제어 문자 자동 이스케이프)
if command -v jq >/dev/null 2>&1; then
    log_info "jq를 사용하여 JSON 생성"
    
    jq -n \
        --rawfile trust_anchor_crt ca-cert.pem \
        --rawfile trust_anchor_key ca-key.pem \
        --rawfile issuer_crt issuer-cert.pem \
        --rawfile issuer_key issuer-key.pem \
        '{
            trust_anchor: {
                crt: $trust_anchor_crt,
                key: $trust_anchor_key
            },
            issuer: {
                crt: $issuer_crt,
                key: $issuer_key
            }
        }' > linkerd-certs.json
    
    log_success "JSON 파일 생성 완료 (jq 사용)"
    
    # 3. JSON 유효성 검증
    if jq . linkerd-certs.json >/dev/null 2>&1; then
        log_success "JSON 파일 유효성 검증 통과"
    else
        log_error "JSON 파일 유효성 검증 실패"
        log_error "JSON 내용 확인:"
        cat linkerd-certs.json
        exit 1
    fi
    
else
    # jq가 없으면 Python을 사용한 안전한 방법
    log_warning "jq가 없어서 Python을 사용하여 JSON 생성"
    
    python3 -c "
import json
import sys

try:
    # 인증서 파일들 읽기
    with open('ca-cert.pem', 'r') as f:
        trust_anchor_crt = f.read().strip()
    with open('ca-key.pem', 'r') as f:
        trust_anchor_key = f.read().strip()
    with open('issuer-cert.pem', 'r') as f:
        issuer_crt = f.read().strip()
    with open('issuer-key.pem', 'r') as f:
        issuer_key = f.read().strip()
    
    # JSON 생성
    data = {
        'trust_anchor': {
            'crt': trust_anchor_crt,
            'key': trust_anchor_key
        },
        'issuer': {
            'crt': issuer_crt,
            'key': issuer_key
        }
    }
    
    # 압축된 JSON으로 출력
    with open('linkerd-certs.json', 'w') as f:
        json.dump(data, f, separators=(',', ':'))
    
    print('JSON 파일 생성 완료 (Python 사용)')
    
except Exception as e:
    print(f'오류: {e}', file=sys.stderr)
    sys.exit(1)
"
    
    if [ $? -eq 0 ]; then
        log_success "JSON 파일 생성 완료 (Python 사용)"
    else
        log_error "JSON 파일 생성 실패"
        exit 1
    fi
fi

# 4. 임시 파일 정리
rm -f "$TEMP_JSON"

log_success "JSON 파일 생성 완료: linkerd-certs.json"

# 인증서 유효성 검증
log_info "인증서 유효성 검증 중..."

# Trust Anchor 검증
if openssl x509 -in ca-cert.pem -noout -checkend 0 >/dev/null 2>&1; then
    log_success "Trust Anchor 인증서 유효성 검증 통과"
else
    log_error "Trust Anchor 인증서 유효성 검증 실패"
    exit 1
fi

# Issuer 인증서 검증
if openssl x509 -in issuer-cert.pem -noout -checkend 0 >/dev/null 2>&1; then
    log_success "Issuer 인증서 유효성 검증 통과"
else
    log_error "Issuer 인증서 유효성 검증 실패"
    exit 1
fi

# 인증서 체인 검증
if openssl verify -CAfile ca-cert.pem issuer-cert.pem >/dev/null 2>&1; then
    log_success "인증서 체인 검증 통과"
else
    log_error "인증서 체인 검증 실패"
    exit 1
fi

# 생성된 파일 목록 출력
echo ""
log_success "인증서 생성이 완료되었습니다!"
echo ""
echo "생성된 파일들:"
echo "  📄 ca-cert.pem        (Trust Anchor 인증서)"
echo "  🔐 ca-key.pem         (Trust Anchor 개인키)"
echo "  📄 issuer-cert.pem    (Issuer 인증서)"
echo "  🔐 issuer-key.pem     (Issuer 개인키)"
echo "  📋 linkerd-certs.json (AWS Secrets Manager 등록용)"
echo ""

# AWS Secrets Manager 등록 명령어 출력
echo "다음 단계:"
echo ""
echo "1. 회사 비밀저장소에 백업:"
echo "   cp -r $CERTS_DIR /path/to/company/secret/store/"
echo ""
echo "2. AWS Secrets Manager 등록:"
echo "   aws secretsmanager put-secret-value \\"
echo "     --secret-id 'your-project/linkerd/certificates' \\"
echo "     --secret-string file://linkerd-certs.json"
echo ""
echo "3. 또는 직접 JSON 내용 복사:"
echo "   cat linkerd-certs.json"
echo ""

# 인증서 만료일 출력
TRUST_ANCHOR_EXPIRY=$(openssl x509 -in ca-cert.pem -noout -enddate | cut -d= -f2)
ISSUER_EXPIRY=$(openssl x509 -in issuer-cert.pem -noout -enddate | cut -d= -f2)

echo "인증서 만료일:"
echo "  Trust Anchor: $TRUST_ANCHOR_EXPIRY"
echo "  Issuer:       $ISSUER_EXPIRY"
echo ""

log_success "모든 작업이 완료되었습니다! 🎉"
