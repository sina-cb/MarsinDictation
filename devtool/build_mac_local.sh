#!/bin/sh
# Reproducible local Release app. No installation, launch, credentials, or model download.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
# XcodeGen resolves these ignored config references even for credential-free builds.
# Preserve any existing personal signing configuration without reading it.
if [ ! -e mac/Local.xcconfig ]; then
  printf '%s\n' '// Empty local config for credential-free builds.' > mac/Local.xcconfig
fi
XCODEGEN_BIN=${XCODEGEN:-xcodegen}
"$XCODEGEN_BIN" generate --spec mac/project.yml --project mac
xcodebuild -project mac/MarsinDictation.xcodeproj -scheme MarsinDictation \
  -configuration Release -derivedDataPath tmp/mac-api-release \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGNING_ALLOWED=NO build
APP="$ROOT/tmp/mac-api-release/Build/Products/Release/MarsinDictation.app"
LICENSES="$APP/Contents/Resources/Licenses"
mkdir -p "$LICENSES"
install -m 644 LICENSE "$LICENSES/MarsinDictation-MIT.txt"
install -m 644 tmp/mac-api-release/SourcePackages/checkouts/SwiftWhisper/LICENSE "$LICENSES/SwiftWhisper-MIT.txt"
install -m 644 tmp/mac-api-release/SourcePackages/checkouts/SwiftWhisper/whisper.cpp/LICENSE "$LICENSES/whisper.cpp-MIT.txt"
# Ad-hoc signing uses no certificate, keychain, account, notarization, or network service.
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
printf '%s\n' "$APP"
