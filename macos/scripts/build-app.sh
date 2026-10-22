#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP_PATH="$PWD/dist/NowDo 计时点.app"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp .build/release/NowDoDot "$APP_PATH/Contents/MacOS/NowDoDot"
cp scripts/Info.plist "$APP_PATH/Contents/Info.plist"
cp LICENSE "$APP_PATH/Contents/Resources/LICENSE"
swift scripts/make-icon.swift "$PWD/dist"
iconutil -c icns "$PWD/dist/AppIcon.iconset" -o "$APP_PATH/Contents/Resources/AppIcon.icns"
codesign --force --sign - --identifier com.even.nowdo-dot "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"
echo "$APP_PATH"
