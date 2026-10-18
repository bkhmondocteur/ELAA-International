# ELAA International — DocPocket Pro Suite

[![Deploy to GitHub Pages](https://github.com/bkhmondocteur/ELAA-International/actions/workflows/deploy.yml/badge.svg)](https://github.com/bkhmondocteur/ELAA-International/actions/workflows/deploy.yml)
[![PWA Ready](https://img.shields.io/badge/PWA-Ready-success.svg)](https://bkhmondocteur.github.io/ELAA-International/)
[![Security: AES-GCM 256](https://img.shields.io/badge/Security-AES--GCM%20256-blue.svg)](https://bkhmondocteur.github.io/ELAA-International/)

Plateforme médicale et logistique unifiée pour l'assistance d'urgence médicale connectée **ELAA International**.

---

## 🌐 Liens Rapides PWA (Accès Direct)

| Application | Description | Accès En Ligne |
|---|---|---|
| **Portail Suite** | Portail d'accueil & sélecteur de profil | [Ouvrir le Portail](https://bkhmondocteur.github.io/ELAA-International/) |
| **DocPocket Hub** | Cockpit Opérateur & Régulation Assurance | [Lancer le Hub](https://bkhmondocteur.github.io/ELAA-International/hub/) |
| **DocPocket Med** | Module Médecin Praticien & Secret Médical | [Lancer le Module Med](https://bkhmondocteur.github.io/ELAA-International/med/) |

---

## 🏗️ Architecture Multi-Acteurs

- **Séparation Chirurgicale des Données** :
  - **Volet Administratif & Financier** (Clair) : Statuts de mission, géolocalisation, honoraires HT/TTC, prise en charge partenaire.
  - **Volet Médical & Clinique** (Chiffré de bout en bout AES-GCM 256 bits) : Diagnostic, antécédents, constantes vitales, ordonnances, explorations.
- **Télémétrie GPS Live & Geofencing** :
  - Suivi en temps réel de la progression du médecin vers l'hôtel ou le patient avec carte interactive.
  - Détection automatique d'arrivée sur site (rayon 150m).
- **Expédition E-mail Universelle** :
  - Génération automatique des rapports au format PDF (Rapport Médical sans prix, Rapport Financier, Ordonnance).
  - Intégration directe des pièces justificatives (Passeport/CNI, Prise en charge, Examens/Analyses).
  - Connexion native Apple Mail (macOS) et partage sécurisé (Android/Web).

---

## 🚀 Démarrage et Tests Locaux

Pour lancer les serveurs locaux et ouvrir automatiquement les deux versions dans Google Chrome :

```bash
# Démarrer les serveurs et ouvrir 2 fenêtres Chrome (Hub & Médecin)
./start_test_servers.sh

# Ou via le script dédié :
./open_test_chrome.sh
```

Pour ouvrir directement la version hébergée en ligne dans 2 fenêtres Chrome :

```bash
./open_test_chrome.sh --live
```

---

## 📦 Structure du Répertoire

```text
ELAA International/
├── docs/                      # PWA Suite hébergée sur GitHub Pages
│   ├── index.html             # Portail unifié d'accueil
│   ├── hub/                   # PWA Flutter Web Hub Opérateur
│   └── med/                   # PWA Flutter Web Médecin
├── elaa_docpocket/            # Code source Flutter Hub
├── elaa_docpocket_med/        # Code source Flutter Med
├── elaa_shared/               # Bibliothèque partagée (modèles, chiffrement, GPS)
├── start_test_servers.sh      # Serveur local + ouverture 2 fenêtres Chrome
├── open_test_chrome.sh        # Sélecteur de test 2 fenêtres (local / live)
└── rebuild_web.sh             # Script de build et packaging Web PWA
```

---

## 🔒 Confidentialité & Sécurité

- Conforme RGPD et secret médical strict.
- Chiffrement symétrique AES-GCM 256 bits et asymétrique RSA pour l'échange de clés de session.
