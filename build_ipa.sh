#!/usr/bin/env bash
# Build LoopTimer and package it as an .ipa
#
# Usage:
#   ./build_ipa.sh                          # unsigned .ipa (for Sideloadly/AltStore/ESign re-signing)
#   ./build_ipa.sh --team <TEAM_ID>         # signed .ipa via archive + export (paid Apple Developer account)
#   ./build_ipa.sh --team <TEAM_ID> --method development
#
# Output: build/ipa/LoopTimer-<mode>.ipa
set -euo pipefail

cd "$(dirname "$0")"

SCHEME="LoopTimer"
PROJECT="LoopTimer.xcodeproj"
OUT_DIR="build/ipa"
DD_DEVICE="build/dd-device"
DD_ARCHIVE="build/dd-archive"
TEAM_ID=""
METHOD="development"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --team)   TEAM_ID="$2"; shift 2 ;;
    --method) METHOD="$2"; shift 2 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

if [[ -z "$TEAM_ID" ]]; then
  echo "==> Unsigned device build (CODE_SIGNING_ALLOWED=NO)"
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
    -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
    -derivedDataPath "$DD_DEVICE" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
    build

  APP="$DD_DEVICE/Build/Products/Release-iphoneos/LoopTimer.app"
  rm -rf "$OUT_DIR/Payload"
  mkdir -p "$OUT_DIR/Payload"
  cp -R "$APP" "$OUT_DIR/Payload/"
  # keep bundle tidy: drop non-runtime docs
  rm -f "$OUT_DIR/Payload/LoopTimer.app/AUDIO_FILES_README.md"
  ( cd "$OUT_DIR" && zip -qry LoopTimer-unsigned.ipa Payload && rm -rf Payload )

  echo
  echo "==> $OUT_DIR/LoopTimer-unsigned.ipa"
  echo "    Unsigned: install it with Sideloadly / AltStore / ESign (they re-sign with your Apple ID)."
else
  echo "==> Archive + export (team $TEAM_ID, method $METHOD)"
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
    -configuration Release -destination 'generic/platform=iOS' \
    -archivePath "build/LoopTimer.xcarchive" \
    -derivedDataPath "$DD_ARCHIVE" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    -allowProvisioningUpdates \
    archive

  cat > build/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>${METHOD}</string>
  <key>teamID</key><string>${TEAM_ID}</string>
  <key>signingStyle</key><string>automatic</string>
  <key>stripSwiftSymbols</key><true/>
  <key>compileBitcode</key><false/>
</dict>
</plist>
PLIST

  xcodebuild -exportArchive \
    -archivePath "build/LoopTimer.xcarchive" \
    -exportOptionsPlist build/ExportOptions.plist \
    -exportPath "$OUT_DIR" \
    -allowProvisioningUpdates

  echo
  echo "==> $OUT_DIR/LoopTimer.ipa"
fi
