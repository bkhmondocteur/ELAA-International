#!/bin/bash
set -e
export JAVA_HOME="/Volumes/bkhmondocteur/Mes Applications/outils/jdk-17.0.2.jdk/Contents/Home"
export ANDROID_HOME="/Volumes/bkhmondocteur/Mes Applications/outils/android-sdk"
export ANDROID_SDK_ROOT="/Volumes/bkhmondocteur/Mes Applications/outils/android-sdk"
export PATH="$JAVA_HOME/bin:/Volumes/bkhmondocteur/Mes Applications/outils/flutter/bin:/Volumes/bkhmondocteur/Mes Applications/outils/node/bin:$PATH"
export CI=true
export FLUTTER_SUPPRESS_ANALYTICS=true

mkdir -p "/Volumes/bkhmondocteur/Mes Applications/ELAA International/release"
mkdir -p "/Volumes/bkhmondocteur/Mes Applications/ELAA International/test"

echo "=== Building Android APK for ELAA DocPocket Med ==="
cd "/Volumes/bkhmondocteur/Mes Applications/ELAA International/elaa_docpocket_med"
flutter build apk --release
cp build/app/outputs/flutter-apk/app-release.apk "/Volumes/bkhmondocteur/Mes Applications/ELAA International/release/ELAA DocPocket Med.apk"
cp build/app/outputs/flutter-apk/app-release.apk "/Volumes/bkhmondocteur/Mes Applications/ELAA International/test/ELAA DocPocket Med.apk"
echo "✓ ELAA DocPocket Med.apk copied to release and test directories!"

echo "=== Building Android APK for ELAA DocPocket Pro Hub ==="
cd "/Volumes/bkhmondocteur/Mes Applications/ELAA International/elaa_docpocket"
flutter build apk --release
cp build/app/outputs/flutter-apk/app-release.apk "/Volumes/bkhmondocteur/Mes Applications/ELAA International/release/ELAA DocPocket Pro Hub Operateur.apk"
cp build/app/outputs/flutter-apk/app-release.apk "/Volumes/bkhmondocteur/Mes Applications/ELAA International/test/ELAA DocPocket Pro Hub Operateur.apk"
echo "✓ ELAA DocPocket Pro Hub Operateur.apk copied to release and test directories!"

# Synchroniser aussi les .app vers release
cp -R "/Volumes/bkhmondocteur/Mes Applications/ELAA International/test/ELAA DocPocket Med.app" "/Volumes/bkhmondocteur/Mes Applications/ELAA International/release/" 2>/dev/null || true
cp -R "/Volumes/bkhmondocteur/Mes Applications/ELAA International/test/ELAA DocPocket Pro Hub Operateur.app" "/Volumes/bkhmondocteur/Mes Applications/ELAA International/release/" 2>/dev/null || true

echo "=== Android APK Build Complete! ==="
