#!/bin/bash
set -euo pipefail

CONFIG="${1:-release}"
APP_NAME="StatsMenu"
BUILD_DIR=".build/${CONFIG}"
APP_BUNDLE="${APP_NAME}.app"

echo "Building (${CONFIG})…"
swift build -c "${CONFIG}"

echo "Packaging ${APP_BUNDLE}…"
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "Resources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"
echo -n "APPL????" > "${APP_BUNDLE}/Contents/PkgInfo"

codesign --force --deep --sign - "${APP_BUNDLE}" 2>/dev/null || true

echo "Done → ${APP_BUNDLE}"
echo "Run with: open ${APP_BUNDLE}   (or: ./${APP_BUNDLE}/Contents/MacOS/${APP_NAME})"
