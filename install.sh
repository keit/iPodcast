#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

BUILD_DIR="build"
APP_NAME="iPodcast.app"
RELEASE_PATH="$BUILD_DIR/Build/Products/Release/$APP_NAME"
INSTALL_PATH="/Applications/$APP_NAME"

echo "Building Release configuration..."
xcodebuild \
    -scheme iPodcast \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    clean build

echo "Installing to $INSTALL_PATH..."
rm -rf "$INSTALL_PATH"
cp -R "$RELEASE_PATH" "$INSTALL_PATH"

echo "Done. Installed $APP_NAME to /Applications."
