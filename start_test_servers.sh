#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

echo "=== Arrêt des serveurs existants ==="
pkill -f "http.server 3000" || true
pkill -f "http.server 3001" || true
pkill -f "http.server 8080" || true

echo "=== Démarrage des serveurs PWA ==="
python3 -m http.server 3000 --directory "$DIR/docs/hub" > /dev/null 2>&1 &
python3 -m http.server 3001 --directory "$DIR/docs/med" > /dev/null 2>&1 &
python3 -m http.server 8080 --directory "$DIR/docs" > /dev/null 2>&1 &

sleep 1

echo "Serveurs actifs :"
echo "  • Hub (Opérateur) : http://localhost:3000"
echo "  • Med (Médecin)   : http://localhost:3001"
echo "  • Portail Suite   : http://localhost:8080"

echo "=== Ouverture automatique de deux onglets dans Google Chrome ==="
if [ -d "/Applications/Google Chrome.app" ]; then
  open -a "Google Chrome" "http://localhost:3000" "http://localhost:3001"
  echo "✓ 2 onglets Chrome ouverts (Hub & Médecin) !"
else
  open "http://localhost:3000"
  open "http://localhost:3001"
fi
