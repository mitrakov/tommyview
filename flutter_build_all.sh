#!/bin/bash
set -e

echo "This is a build script for MacOS. Make sure to update version in pubspec.yaml!"

echo
echo "Cleaning..."
flutter clean

echo
echo "Building MacOS..."
flutter build macos
cd build/macos/Build/Products/Release/
zip -r9 TommyView-macos.zip TommyView.app/
cd ../../../../..
cp build/macos/Build/Products/Release/TommyView-macos.zip dist/

echo
echo "Done ✅"
