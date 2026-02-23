#!/usr/bin/env bash
# v1.0.0 (2026-02-23)
set -eo pipefail
clear

BUILD_PATH=build/linux/x64/release

# check tools
function require() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: required command '$cmd' not found in PATH ($PATH)"
    exit 1
  fi
}
require flutter
require zip
require git

# switch to main flutter dir
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$WORK_DIR" && pwd

# get current version
[ -f "pubspec.yaml" ] || { echo "pubspec.yaml not found"; exit 1; }
fullVersion=$(grep "version: " pubspec.yaml)
VERSION=$(echo "$fullVersion" | cut -d " " -f 2 | cut -d "+" -f 1)   # BUILD_NUMBER=$(echo "$fullVersion" | cut -d "+" -f 2)

# build for Linux
flutter -v build linux

# make a *.zip
pushd $BUILD_PATH && pwd
mv -v bundle/ tommyview/
zip -r9 "tommyview-linux-$VERSION.zip" tommyview/
popd && pwd

# move to dist/ folder
(cd dist/ && rm -f tommyview-linux-*.zip)
mv -v "$BUILD_PATH/tommyview-linux-$VERSION.zip" dist/

# finish
flutter clean

# git
git status
git add .
git status
git commit -m "Release $VERSION for Linux"
git status
read -p "Git push? (Y/n): " -r
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
  git push
fi
git status

echo "Done..."
