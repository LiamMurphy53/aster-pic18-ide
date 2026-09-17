#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
STAGING=$(mktemp -d /tmp/aster-build.XXXXXX)
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/Aster.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
if [[ "${1:-}" == "--universal" ]]; then
    ARCHITECTURES=(arm64 x86_64)
elif [[ $# -eq 0 ]]; then
    ARCHITECTURES=("$(uname -m)")
else
    printf 'Usage: bash build.sh [--universal]\n' >&2
    exit 2
fi
BINARIES=()
for ARCH in "${ARCHITECTURES[@]}"; do
    BINARY="$STAGING/Aster-$ARCH"
    xcrun swiftc -swift-version 5 -target "$ARCH-apple-macos13.0" -O \
        -module-cache-path "$STAGING/module-cache" -framework AppKit -framework WebKit -framework CryptoKit \
        Sources/Core.swift Sources/App.swift -o "$BINARY"
    BINARIES+=("$BINARY")
done
if [[ ${#BINARIES[@]} -gt 1 ]]; then
    xcrun lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/Aster"
else
    cp "${BINARIES[0]}" "$APP/Contents/MacOS/Aster"
fi
cp -R -X Web "$APP/Contents/Resources/"
cp -R -X Resources/. "$APP/Contents/Resources/"
cp LICENSE "$APP/Contents/Resources/LICENSE.txt"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Aster</string><key>CFBundleDisplayName</key><string>Aster</string>
<key>CFBundleIdentifier</key><string>local.aster.picide</string><key>CFBundleExecutable</key><string>Aster</string>
<key>CFBundlePackageType</key><string>APPL</string><key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string><key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/><key>NSPrincipalClass</key><string>NSApplication</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
mkdir -p build
ditto --norsrc --noextattr "$APP" 'build/Aster.app'
printf 'Built: %s/build/Aster.app\n' "$PWD"
