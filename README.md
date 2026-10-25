# Faye Facturation

Application de **caisse, facturation et carnet de crédit** pour les commerçants sénégalais, pensée pour le terminal Android **ZCS Z108** (imprimante 80 mm intégrée, caméra, sous-écran client) et qui fonctionne aussi sur téléphone et tablette.

> **Hors ligne d'abord.** Tout est enregistré dans une base SQLite embarquée : l'application marche sans internet, sans API externe, sans WhatsApp, sans notification. La sauvegarde en ligne (Supabase) est facultative et automatique dès qu'il y a du réseau.

Développée par **Ousmane Gueye** — © 2026, voir [LICENSE](LICENSE).

## Pour qui ?

Boutiquiers, grossistes et demi-grossistes (alimentation générale, céréales, graines, boissons…) qui vendent au détail, en demi-gros et en gros, et qui font du **crédit** à leurs clients.

## Fonctionnalités principales

| | |
|---|---|
| **Vente rapide** | Grille de produits, recherche sans accents, rayons, « Populaires », article libre, remise, client comptoir ou client nommé |
| **3 niveaux de prix** | Détail, demi-gros, gros, par produit |
| **Vente au poids** | 250 g, 500 g, ou « pour 500 F » pour les produits en kg / litre |
| **Ardoise** | Crédit, acompte, paiement par tranches, paiement libre réparti sur les plus anciennes factures |
| **QR codes** | Sur chaque facture et reçu ; le scan retrouve la facture (encaisser, dupliquer, rembourser) ou le client |
| **Remboursement** | Annule la vente, rend l'argent encaissé, remet le stock |
| **Tableau de bord** | Ventes, net en caisse, crédits, dettes, encaissements par mode ; filtres jour / semaine / mois / année / période |
| **Clôture de caisse** | Imprimable |
| **Produits et stock** | Icônes, rayons, code-barres, stock facultatif, alerte stock bas |
| **Tickets** | ESC/POS Bluetooth, logo, QR, montant en lettres, reconnaissance de dette à signer |
| **Sous-écran client** | Affiche la vente en cours (si le terminal le permet) |
| **Sauvegarde en ligne** | Supabase, automatique, restauration sur un appareil neuf |
| **Personnalisation** | Nom, adresse, téléphones, logo, couleur du thème, clair / sombre |

Détail complet : [docs/FONCTIONNALITES.md](docs/FONCTIONNALITES.md).

## Documentation

- [Fonctionnalités](docs/FONCTIONNALITES.md)
- [Guide utilisateur](docs/GUIDE-UTILISATEUR.md)
- [Installation et compilation](docs/INSTALLATION.md)
- [Architecture technique](docs/ARCHITECTURE.md)
- [Impression et ticket](docs/IMPRESSION.md)
- [Synchronisation Supabase](docs/SYNCHRONISATION.md)
- [Historique des versions](CHANGELOG.md)

## Démarrage rapide (développeur)

```bash
flutter pub get
flutter test
flutter run                      # code d'activation de démonstration : DEMO-2026
flutter build apk --release --dart-define=ACTIVATION_HASH=<empreinte>
```

Prérequis : Flutter 3.47+ (Dart ^3.13), Android SDK. Voir [docs/INSTALLATION.md](docs/INSTALLATION.md).

## Stack

Flutter (Material 3) · SQLite (`sqflite`) · ESC/POS brut sur Bluetooth (`print_bluetooth_thermal`) · `mobile_scanner` · Supabase (REST + Auth) · aucune autre dépendance serveur.
