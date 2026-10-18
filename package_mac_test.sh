#!/bin/bash
set -e
export PATH="/Volumes/bkhmondocteur/Mes Applications/outils/node/bin:$PATH"

echo "=== Packaging Hub ==="
cd "/Volumes/bkhmondocteur/Mes Applications/ELAA International/elaa_docpocket"
rm -rf electron_app/flutter_web/*
cp -R build/web/* electron_app/flutter_web/
cd electron_app
npx --no-install electron-builder --mac --dir --config.electronDist="/Volumes/bkhmondocteur/Mes Applications/outils/electron-v31.2.1-darwin-x64.zip" || npx electron-builder --mac --dir
rm -rf "/Volumes/bkhmondocteur/Mes Applications/ELAA International/test/ELAA DocPocket Pro Hub Operateur.app"
cp -R dist/mac-arm64/*.app "/Volumes/bkhmondocteur/Mes Applications/ELAA International/test/ELAA DocPocket Pro Hub Operateur.app" 2>/dev/null || cp -R dist/mac/*.app "/Volumes/bkhmondocteur/Mes Applications/ELAA International/test/ELAA DocPocket Pro Hub Operateur.app"
xattr -cr "/Volumes/bkhmondocteur/Mes Applications/ELAA International/test/ELAA DocPocket Pro Hub Operateur.app" || true
codesign --force --deep --sign - "/Volumes/bkhmondocteur/Mes Applications/ELAA International/test/ELAA DocPocket Pro Hub Operateur.app" || true

echo "=== Packaging Med ==="
cd "/Volumes/bkhmondocteur/Mes Applications/ELAA International/elaa_docpocket_med"
rm -rf electron_app/flutter_web/*
cp -R build/web/* electron_app/flutter_web/
cd electron_app
npx --no-install electron-builder --mac --dir --config.electronDist="/Volumes/bkhmondocteur/Mes Applications/outils/electron-v31.2.1-darwin-x64.zip" || npx electron-builder --mac --dir
rm -rf "/Volumes/bkhmondocteur/Mes Applications/ELAA International/test/ELAA DocPocket Med.app"
cp -R dist/mac-arm64/*.app "/Volumes/bkhmondocteur/Mes Applications/ELAA International/test/ELAA DocPocket Med.app" 2>/dev/null || cp -R dist/mac/*.app "/Volumes/bkhmondocteur/Mes Applications/ELAA International/test/ELAA DocPocket Med.app"
xattr -cr "/Volumes/bkhmondocteur/Mes Applications/ELAA International/test/ELAA DocPocket Med.app" || true
codesign --force --deep --sign - "/Volumes/bkhmondocteur/Mes Applications/ELAA International/test/ELAA DocPocket Med.app" || true

echo "=== Packaging Complete ==="
