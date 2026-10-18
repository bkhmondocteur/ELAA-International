#!/bin/bash
set -e

# Java / JDK
export JAVA_HOME="/Volumes/bkhmondocteur/Mes Applications/outils/jdk-17.0.2.jdk/Contents/Home"
export PATH="$JAVA_HOME/bin:$PATH"

# Android SDK
export ANDROID_HOME="/Volumes/bkhmondocteur/Mes Applications/outils/android-sdk"
export ANDROID_SDK_ROOT="/Volumes/bkhmondocteur/Mes Applications/outils/android-sdk"

# Flutter
export FLUTTER="/Volumes/bkhmondocteur/Mes Applications/outils/flutter/bin/flutter"

TEST_DIR="/Volumes/bkhmondocteur/Mes Applications/ELAA International/test"
mkdir -p "$TEST_DIR"

echo "=== Building APK for ELAA DocPocket Med ==="
cd "/Volumes/bkhmondocteur/Mes Applications/ELAA International/elaa_docpocket_med"
"$FLUTTER" build apk --release

cp build/app/outputs/flutter-apk/app-release.apk "$TEST_DIR/ELAA_DocPocket_Med.apk"
echo "=== Compilation APK terminée avec succès ==="
