#!/usr/bin/env bash
# Build Checkpoint.app from source.
#
#   ./build.sh                 universal Release build → dist/Checkpoint.app (ad-hoc signed)
#   ./build.sh --dmg --zip     also package dist/Checkpoint-<version>.dmg / .zip
#   ./build.sh --install       copy the app to /Applications
#   ./build.sh --open          launch it when done
#   ./build.sh --debug         Debug configuration (faster, native arch only)
#   ./build.sh --sign "Developer ID Application: Name (TEAMID)"   sign with your identity
#   ./build.sh --version 0.2.0 set the marketing version
#
# Requirements: macOS 26+, Xcode 26+, XcodeGen (offered via Homebrew if missing).
set -euo pipefail

cd "$(dirname "$0")"
APP_NAME="Checkpoint"
CONFIG="Release"
DMG=0; ZIP=0; INSTALL=0; OPEN=0
IDENTITY="-"
VERSION="$(sed -n 's/^ *MARKETING_VERSION: *"\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' project.yml | head -1)"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
info() { printf '\033[36m▸\033[0m %s\n' "$*"; }
fail() { printf '\033[31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --dmg) DMG=1 ;;
    --zip) ZIP=1 ;;
    --install) INSTALL=1 ;;
    --open) OPEN=1 ;;
    --debug) CONFIG="Debug" ;;
    --sign) IDENTITY="${2:?--sign needs an identity}"; shift ;;
    --version) VERSION="${2:?--version needs a value}"; shift ;;
    -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) fail "Unknown option: $1 (see ./build.sh --help)" ;;
  esac
  shift
done

# --- Prerequisites ---------------------------------------------------------
[ "$(uname)" = "Darwin" ] || fail "Checkpoint builds on macOS only."
command -v xcodebuild >/dev/null || fail "Xcode not found. Install Xcode 26+ from the App Store, then run: sudo xcode-select -s /Applications/Xcode.app"
XCODE_MAJOR="$(xcodebuild -version | awk 'NR==1 {split($2, v, "."); print v[1]}')"
[ "${XCODE_MAJOR:-0}" -ge 26 ] || fail "Xcode 26 or later is required (found $(xcodebuild -version | head -1))."

if ! command -v xcodegen >/dev/null; then
  if command -v brew >/dev/null; then
    read -r -p "XcodeGen is required. Install it with Homebrew now? [Y/n] " reply
    case "${reply:-Y}" in [Yy]*) brew install xcodegen ;; *) fail "Install XcodeGen: brew install xcodegen" ;; esac
  else
    fail "XcodeGen is required: https://github.com/yonaskolb/XcodeGen (or install Homebrew, then: brew install xcodegen)"
  fi
fi

# --- Build -----------------------------------------------------------------
bold "Building $APP_NAME $VERSION ($CONFIG)"
info "Generating Xcode project"
xcodegen generate --quiet

ARCH_FLAGS=()
[ "$CONFIG" = "Release" ] && ARCH_FLAGS=(ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO)
if [ "$IDENTITY" = "-" ]; then
  SIGN_FLAGS=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=)
  info "Signing: ad-hoc (pass --sign to use your own identity)"
else
  SIGN_FLAGS=(CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=$IDENTITY" OTHER_CODE_SIGN_FLAGS=--timestamp)
  info "Signing: $IDENTITY"
fi

info "Compiling (this takes a minute or two)…"
LOG="build/build.log"
mkdir -p build
if ! xcodebuild \
      -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" -configuration "$CONFIG" \
      -destination 'generic/platform=macOS' -derivedDataPath build \
      "${ARCH_FLAGS[@]}" CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
      MARKETING_VERSION="$VERSION" "${SIGN_FLAGS[@]}" \
      build > "$LOG" 2>&1; then
  grep -E "error:" "$LOG" | sort -u | head -20 >&2 || true
  fail "Build failed — full log: $LOG"
fi

rm -rf "dist/$APP_NAME.app"
mkdir -p dist
cp -R "build/Build/Products/$CONFIG/$APP_NAME.app" dist/
APP="dist/$APP_NAME.app"
codesign --verify --deep --strict "$APP" 2>/dev/null || fail "Code signature didn't verify."
info "Built $APP ($(lipo -archs "$APP/Contents/MacOS/$APP_NAME"))"

# --- Package ---------------------------------------------------------------
if [ "$DMG" = 1 ]; then
  STAGE="$(mktemp -d)"
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "dist/$APP_NAME-$VERSION.dmg"
  rm -rf "$STAGE"
  [ "$IDENTITY" != "-" ] && codesign --sign "$IDENTITY" --timestamp "dist/$APP_NAME-$VERSION.dmg"
  info "Packaged dist/$APP_NAME-$VERSION.dmg"
fi
if [ "$ZIP" = 1 ]; then
  (cd dist && rm -f "$APP_NAME-$VERSION.zip" && ditto -c -k --keepParent "$APP_NAME.app" "$APP_NAME-$VERSION.zip")
  info "Packaged dist/$APP_NAME-$VERSION.zip"
fi

# --- Install / open --------------------------------------------------------
if [ "$INSTALL" = 1 ]; then
  pkill -x "$APP_NAME" 2>/dev/null || true
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP" /Applications/
  APP="/Applications/$APP_NAME.app"
  info "Installed to $APP"
fi
[ "$OPEN" = 1 ] && open "$APP"

bold "✓ Done → $APP"
if [ "$IDENTITY" = "-" ]; then
  echo "  Ad-hoc signed: if macOS blocks it, right-click → Open, or: xattr -dr com.apple.quarantine \"$APP\""
fi
