#!/bin/bash
set -e

echo "🚀 Lambda 패키지 빌드 시작..."

# 현재 스크립트 디렉토리
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
PACKAGE_DIR="$BUILD_DIR/lambda_package"

# 기존 빌드 디렉토리 정리
echo "📁 기존 빌드 디렉토리 정리..."
rm -rf "$BUILD_DIR"
mkdir -p "$PACKAGE_DIR"

# Python 파일 복사 (Lambda 핸들러명 변경)
echo "📄 Python 파일 복사..."
cp "$SCRIPT_DIR/rds_password_rotation.py" "$PACKAGE_DIR/lambda_function.py"

# 의존성 설치 (Lambda 기본 제공 라이브러리만 사용하므로 생략)
echo "📦 의존성 확인..."
if [ -s "$SCRIPT_DIR/requirements.txt" ] && ! grep -q "^#" "$SCRIPT_DIR/requirements.txt"; then
    echo "⚠️  requirements.txt에 실제 의존성이 있습니다. 설치를 진행합니다..."
    # 가상환경이 활성화되어 있지 않으면 pip3 사용 시도
    if command -v pip &> /dev/null; then
        pip install -r "$SCRIPT_DIR/requirements.txt" -t "$PACKAGE_DIR/" --quiet
    elif command -v pip3 &> /dev/null; then
        pip3 install -r "$SCRIPT_DIR/requirements.txt" -t "$PACKAGE_DIR/" --quiet
    else
        echo "❌ pip 또는 pip3를 찾을 수 없습니다."
        echo "💡 가상환경을 활성화하거나 pip을 설치해주세요."
        echo "   예: python3 -m venv venv && source venv/bin/activate"
        exit 1
    fi
else
    echo "✅ 추가 의존성 없음 (Lambda 기본 제공 라이브러리만 사용)"
fi

# ZIP 파일 생성
echo "🗜️ ZIP 파일 생성..."
cd "$PACKAGE_DIR"
zip -r "$BUILD_DIR/rds_password_rotation.zip" . > /dev/null
cd "$SCRIPT_DIR"

# 빌드 결과 확인
PACKAGE_SIZE=$(du -h "$BUILD_DIR/rds_password_rotation.zip" | cut -f1)
echo "✅ Lambda 패키지 빌드 완료!"
echo "📦 패키지 크기: $PACKAGE_SIZE"
echo "📍 패키지 위치: $BUILD_DIR/rds_password_rotation.zip"

# 패키지 내용 확인
echo "📋 패키지 내용:"
unzip -l "$BUILD_DIR/rds_password_rotation.zip" | head -20

echo ""
echo "🎉 빌드 완료! 이제 terraform apply를 실행하세요."
