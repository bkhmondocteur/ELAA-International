#!/bin/bash
set -e

# Export Dependencies
export PATH="/Volumes/bkhmondocteur/Mes Applications/outils/node/bin:$PATH"
export ELECTRON_CACHE="/Volumes/bkhmondocteur/Mes Applications/outils"
export ELECTRON_BUILDER_CACHE="/Volumes/bkhmondocteur/Mes Applications/outils"
export FLUTTER="/Volumes/bkhmondocteur/Mes Applications/outils/flutter/bin/flutter"

TEST_DIR="/Volumes/bkhmondocteur/Mes Applications/ELAA International/test"
mkdir -p "$TEST_DIR"

echo "=== Building ELAA DocPocket Med (Mac Only) ==="
cd "/Volumes/bkhmondocteur/Mes Applications/ELAA International/elaa_docpocket_med"
echo "Building Web..."
"$FLUTTER" build web --release
rm -rf electron_app/flutter_web
cp -r build/web electron_app/flutter_web
cd electron_app
echo "Installing Node modules (offline)..."
npm install --prefer-offline
echo "Building Electron Mac..."
npm run build:mac
cp dist/*.dmg "$TEST_DIR/" 2>/dev/null || true
cp -R dist/mac/*.app "$TEST_DIR/" 2>/dev/null || true

echo "=== Building ELAA DocPocket Pro Hub (Mac Only) ==="
cd "/Volumes/bkhmondocteur/Mes Applications/ELAA International/elaa_docpocket"
echo "Building Web..."
"$FLUTTER" build web --release
rm -rf electron_app/flutter_web
cp -r build/web electron_app/flutter_web
cd electron_app
echo "Installing Node modules (offline)..."
npm install --prefer-offline
echo "Building Electron Mac..."
npm run build:mac
cp dist/*.dmg "$TEST_DIR/" 2>/dev/null || true
cp -R dist/mac/*.app "$TEST_DIR/" 2>/dev/null || true

echo "=== Compilation Mac terminée avec succès ==="
