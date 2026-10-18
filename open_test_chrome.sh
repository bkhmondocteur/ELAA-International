#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

MODE="${1:-local}"

if [ "$MODE" == "--live" ] || [ "$MODE" == "live" ]; then
  URL_HUB="https://bkhmondocteur.github.io/ELAA-International/hub/"
  URL_MED="https://bkhmondocteur.github.io/ELAA-International/med/"
  echo "=== Test en ligne (GitHub Pages) ==="
else
  URL_HUB="http://localhost:3000"
  URL_MED="http://localhost:3001"
  echo "=== Test local (localhost) ==="
  bash "$DIR/start_test_servers.sh"
  exit 0
fi

echo "Ouverture de deux fenêtres Google Chrome :"
echo " - Fenêtre 1 (Hub)     : $URL_HUB"
echo " - Fenêtre 2 (Médecin) : $URL_MED"

if [ -d "/Applications/Google Chrome.app" ]; then
  open -na "Google Chrome" --args --new-window "$URL_HUB"
  sleep 1
  open -na "Google Chrome" --args --new-window "$URL_MED"
else
  open "$URL_HUB"
  sleep 1
  open "$URL_MED"
fi

echo "✓ 2 fenêtres Chrome ouvertes !"
