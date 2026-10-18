#!/bin/bash
set -e

# Export Dependencies
export JAVA_HOME="/Volumes/bkhmondocteur/Mes Applications/outils/jdk-17.0.2.jdk/Contents/Home"
export ANDROID_HOME="/Volumes/bkhmondocteur/Mes Applications/outils/android-sdk"
export ANDROID_SDK_ROOT="/Volumes/bkhmondocteur/Mes Applications/outils/android-sdk"
export PATH="$JAVA_HOME/bin:/Volumes/bkhmondocteur/Mes Applications/outils/node/bin:$PATH"
export ELECTRON_CACHE="/Volumes/bkhmondocteur/Mes Applications/outils"
export ELECTRON_BUILDER_CACHE="/Volumes/bkhmondocteur/Mes Applications/outils"
export FLUTTER="/Volumes/bkhmondocteur/Mes Applications/outils/flutter/bin/flutter"

TEST_DIR="/Volumes/bkhmondocteur/Mes Applications/ELAA International/test"
mkdir -p "$TEST_DIR"

echo "=== Building ELAA DocPocket Med ==="
cd "/Volumes/bkhmondocteur/Mes Applications/ELAA International/elaa_docpocket_med"

# Build APK
echo "Building APK..."
"$FLUTTER" build apk --release
cp build/app/outputs/flutter-apk/app-release.apk "$TEST_DIR/ELAA DocPocket Med.apk"
cp build/app/outputs/flutter-apk/app-release.apk "$TEST_DIR/elaa_docpocket_med-release.apk"

# Build Web & Electron
echo "Building Web..."
"$FLUTTER" build web --release
rm -rf electron_app/flutter_web
cp -r build/web electron_app/flutter_web

cd electron_app
echo "Building Electron Mac..."
npm run build:mac
echo "Building Electron Win..."
npm run build:win

# Copy Mac DMG & App
cp dist/*.dmg "$TEST_DIR/" 2>/dev/null || true
cp -R dist/mac/*.app "$TEST_DIR/" 2>/dev/null || true

# Copy Win EXE
cp dist/*.exe "$TEST_DIR/" 2>/dev/null || true


echo "=== Building ELAA DocPocket Pro Hub ==="
cd "/Volumes/bkhmondocteur/Mes Applications/ELAA International/elaa_docpocket"

# Build APK
echo "Building APK..."
"$FLUTTER" build apk --release
cp build/app/outputs/flutter-apk/app-release.apk "$TEST_DIR/elaa_docpocket_hub-release.apk"

# Build Web & Electron
echo "Building Web..."
"$FLUTTER" build web --release
rm -rf electron_app/flutter_web
cp -r build/web electron_app/flutter_web

cd electron_app
echo "Building Electron Mac..."
npm run build:mac
echo "Building Electron Win..."
npm run build:win

# Copy Mac DMG & App
cp dist/*.dmg "$TEST_DIR/" 2>/dev/null || true
cp -R dist/mac/*.app "$TEST_DIR/" 2>/dev/null || true

# Copy Win EXE
cp dist/*.exe "$TEST_DIR/" 2>/dev/null || true

echo "=== All compilations finished successfully ==="
