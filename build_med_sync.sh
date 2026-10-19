#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
export PATH="/Volumes/bkhmondocteur/Mes Applications/outils/flutter/bin:/Volumes/bkhmondocteur/Mes Applications/outils/node/bin:$PATH"
export CI=true
export FLUTTER_SUPPRESS_ANALYTICS=true

echo "=== 2/4 Compilation Med (elaa_docpocket_med) ==="
cd "$DIR/elaa_docpocket_med"
flutter build web --release --no-pub

echo "=== 3/4 Synchronisation PWA Suite dans docs/ ==="
mkdir -p "$DIR/docs/hub" "$DIR/docs/med"
rsync -av --delete "$DIR/elaa_docpocket/build/web/" "$DIR/docs/hub/"
rsync -av --delete "$DIR/elaa_docpocket_med/build/web/" "$DIR/docs/med/"

# Patch base href relatif pour GitHub Pages et localhost universel
python3 -c "
for path in ['$DIR/docs/hub/index.html', '$DIR/docs/med/index.html']:
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()
    if '<base href=\"/\">' in content:
        content = content.replace('<base href=\"/\">', '<script>if(!window.location.pathname.endsWith(\"/\")&&!window.location.pathname.endsWith(\".html\")){window.location.replace(window.location.pathname+\"/\"+window.location.search+window.location.hash);}</script><base href=\"./\">')
        with open(path, 'w', encoding='utf-8') as f:
            f.write(content)
"

touch "$DIR/docs/.nojekyll"

echo "=== 4/4 Succès ! PWA Suite assemblée dans docs/ ==="
