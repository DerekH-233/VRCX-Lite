#!/bin/bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# VRCX-Lite: 无签名 IPA 本地构建
#
# 输出干净的未签名 IPA，可用任意自签工具重签。
# 不含任何证书、TeamID 或个人信息。
#
# 前置条件 (Mac): Xcode 16+, brew install xcodegen
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

set -euo pipefail
cd "$(dirname "$0")"

SCHEME="VRCX-Lite"
PROJECT="${SCHEME}.xcodeproj"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " VRCX-Lite Unsigned IPA Builder"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 1. 生成工程
echo "[1/3] 生成 Xcode 工程..."
xcodegen generate

# 2. 编译 (无签名)
echo "[2/3] 编译 (无签名)..."
xcodebuild build \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -sdk iphoneos \
    -destination "generic/platform=iOS" \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    ONLY_ACTIVE_ARCH=NO

# 3. 定位 .app 并打包 IPA
echo "[3/3] 打包 IPA..."

APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData \
    -name "${SCHEME}.app" \
    -path "*/Release-iphoneos/*" \
    -not -path "*/Index.*" \
    | head -1)

if [ -z "$APP_PATH" ]; then
    echo "❌ 找不到 ${SCHEME}.app"
    exit 1
fi

rm -rf ./build
mkdir -p ./build/Payload
cp -R "$APP_PATH" ./build/Payload/
(cd ./build && zip -qr "${SCHEME}.ipa" Payload)
rm -rf ./build/Payload

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " ✅ ./build/${SCHEME}.ipa"
echo "   📦 Bundle ID: com.vrcx-lite"
echo "   🔓 未签名 — 自签即可安装"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
