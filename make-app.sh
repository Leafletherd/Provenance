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

# Compile xcassets Color Sets → Assets.car
if [ -d "Sources/Resources/Assets.xcassets" ]; then
    echo "→ Compiling asset catalog…"
    xcrun actool \
        --output-format human-readable-text \
        --notices --warnings \
        --platform macosx \
        --minimum-deployment-target 13.0 \
        --target-device mac \
        --compile "${APP}/Contents/Resources" \
        "Sources/Resources/Assets.xcassets" 2>&1 | grep -E "error:|warning:" || true
fi

echo "→ Ad-hoc code signing…"
codesign --force --deep --sign - "${APP}"

echo ""
echo "✓ Done: ${APP}"
echo ""
echo "To install:"
echo "  cp -r '$(pwd)/${APP}' /Applications/"
echo ""
echo "Or just double-click the .app in Finder."
