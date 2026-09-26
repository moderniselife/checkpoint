#!/usr/bin/env bash
# Build Checkpoint from source: the Mac app, the iPhone/iPad app, or both.
#
#   ./build.sh                 universal Release Mac build → dist/Checkpoint.app (ad-hoc signed)
#   ./build.sh --platform ios  iPhone/iPad build → dist/Checkpoint-<version>-iOS.ipa (unsigned)
#   ./build.sh --platform all  both
#   ./build.sh --dmg --zip     also package dist/Checkpoint-<version>.dmg / .zip
#   ./build.sh --install       copy the app to /Applications
#   ./build.sh --open          launch it when done
#   ./build.sh --debug         Debug configuration (faster, native arch only)
#   ./build.sh --sign "Developer ID Application: Name (TEAMID)"   sign with your identity
#   ./build.sh --version 0.2.0 set the marketing version
#
# The iOS .ipa is unsigned: install it with a sideloading tool that signs it with
# your Apple ID (AltStore, Sideloadly), or open the project in Xcode and run the
# CheckpointMobile scheme on your device.
#
# Requirements: macOS 26+, Xcode 26+, XcodeGen (offered via Homebrew if missing).
set -euo pipefail

cd "$(dirname "$0")"
APP_NAME="Checkpoint"
CONFIG="Release"
DMG=0; ZIP=0; INSTALL=0; OPEN=0
PLATFORM="macos"
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
    --platform) PLATFORM="$(echo "${2:?--platform needs macos, ios or all}" | tr '[:upper:]' '[:lower:]')"; shift ;;
    --ios) PLATFORM="ios" ;;
    --all) PLATFORM="all" ;;
    -h|--help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) fail "Unknown option: $1 (see ./build.sh --help)" ;;
  esac
  shift
done

case "$PLATFORM" in macos|mac|ios|iphone|ipad|all) ;; *) fail "--platform must be macos, ios or all" ;; esac
[ "$PLATFORM" = "mac" ] && PLATFORM="macos"
case "$PLATFORM" in iphone|ipad) PLATFORM="ios" ;; esac

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
info "Generating Xcode project"
xcodegen generate --quiet
mkdir -p build dist

# --- iOS / iPadOS ----------------------------------------------------------
build_ios() {
  bold "Building $APP_NAME for iPhone and iPad $VERSION ($CONFIG)"
  info "Compiling for iOS (unsigned)…"
  local log="build/build-ios.log"
  if ! xcodebuild \
        -project "$APP_NAME.xcodeproj" -scheme CheckpointMobile -configuration "$CONFIG" \
        -destination 'generic/platform=iOS' -derivedDataPath build \
        MARKETING_VERSION="${VERSION%%-*}" \
        CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= DEVELOPMENT_TEAM= \
        build > "$log" 2>&1; then
    grep -E "error:" "$log" | sort -u | head -20 >&2 || true
    fail "iOS build failed — full log: $log"
  fi
  local app="build/Build/Products/$CONFIG-iphoneos/$APP_NAME.app"
  [ -d "$app" ] || fail "iOS build produced no app at $app"
  local stage
  stage="$(mktemp -d)"
  mkdir -p "$stage/Payload"
  cp -R "$app" "$stage/Payload/"
  rm -f "dist/$APP_NAME-$VERSION-iOS.ipa"
  (cd "$stage" && zip -qry "$OLDPWD/dist/$APP_NAME-$VERSION-iOS.ipa" Payload)
  rm -rf "$stage"
  info "Packaged dist/$APP_NAME-$VERSION-iOS.ipa (unsigned — sign it with AltStore or Sideloadly, or run from Xcode)"
}

if [ "$PLATFORM" = "ios" ] || [ "$PLATFORM" = "all" ]; then
  build_ios
fi
if [ "$PLATFORM" = "ios" ]; then
  bold "✓ Done → dist/$APP_NAME-$VERSION-iOS.ipa"
  exit 0
fi

# --- macOS -----------------------------------------------------------------
bold "Building $APP_NAME for Mac $VERSION ($CONFIG)"

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
      MARKETING_VERSION="${VERSION%%-*}" "${SIGN_FLAGS[@]}" \
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
