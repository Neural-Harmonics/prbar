#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "Usage: $0 <app_path> <version> <output_dir>"
  exit 1
fi

APP_PATH="$1"
VERSION="$2"
OUTPUT_DIR="$3"
APP_NAME="PRBar.app"
DMG_NAME="PRBar-${VERSION}.dmg"
ZIP_NAME="PRBar.app.zip"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found at $APP_PATH"
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
WORK_DIR="$(mktemp -d)"
STAGE_DIR="$WORK_DIR/dmg-root"
mkdir -p "$STAGE_DIR"

rm -f "$OUTPUT_DIR/$ZIP_NAME" "$OUTPUT_DIR/$DMG_NAME"

/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$OUTPUT_DIR/$ZIP_NAME"

cp -R "$APP_PATH" "$STAGE_DIR/$APP_NAME"
ln -s /Applications "$STAGE_DIR/Applications"

hdiutil create \
  -volname "PRBar ${VERSION}" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$OUTPUT_DIR/$DMG_NAME"

rm -rf "$WORK_DIR"

echo "ZIP_PATH=$OUTPUT_DIR/$ZIP_NAME" >> "$GITHUB_ENV"
echo "DMG_PATH=$OUTPUT_DIR/$DMG_NAME" >> "$GITHUB_ENV"
