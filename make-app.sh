#!/bin/bash
set -e

PRODUCT="Provenance"
APP="build/${PRODUCT}.app"

echo "→ Building release binary…"
swift build -c release 2>&1 | grep -v "^warning:"

echo "→ Creating .app bundle…"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS"
mkdir -p "${APP}/Contents/Resources"

cp ".build/release/${PRODUCT}" "${APP}/Contents/MacOS/${PRODUCT}"
cp "Sources/Resources/Info.plist" "${APP}/Contents/Info.plist"
cp "Sources/Resources/provenance.icns" "${APP}/Contents/Resources/provenance.icns"

echo "→ Ad-hoc code signing…"
codesign --force --deep --sign - "${APP}"

echo ""
echo "✓ Done: ${APP}"
echo ""
echo "To install:"
echo "  cp -r '$(pwd)/${APP}' /Applications/"
echo ""
echo "Or just double-click the .app in Finder."
