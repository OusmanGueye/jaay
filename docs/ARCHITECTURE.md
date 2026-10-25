# Architecture technique

## Vue d'ensemble
Application Flutter unique (`sn.ardoise.ardoise`), Material 3, sans framework d'état externe : un singleton `AppState` (réglages, panier, notifiers `dataVersion` et `tab`) et des `ListenableBuilder` / `ValueNotifier`.

```
UI (lib/screens, lib/ui.dart)
   │  AppState.i  (settings, cart, dataVersion)
   ▼
Db (lib/db.dart, sqflite)  ──triggers──▶ sync_log ──▶ SyncService (lib/sync.dart) ──HTTPS──▶ Supabase
   ▲
Receipts (lib/receipts.dart) ─▶ EscPos (lib/escpos.dart) + Raster (lib/raster.dart) ─▶ PrinterService (Bluetooth)
```

## Organisation du code
| Fichier | Rôle |
|---|---|
| `main.dart` | Démarrage, thème Material 3, activation, sync au démarrage et à la reprise |
| `activation.dart` | Nom, mention légale, empreinte SHA-256 salée du code d'activation |
| `app_state.dart` | `Cart` (lignes, client, niveau, remise) et `AppState` |
| `models.dart` | Client, Product, CartLine, Sale, Payment, AppSettings, formats de quantités, QR |
| `db.dart` | Schéma SQLite, migrations, ventes, paiements, remboursement, statistiques, journal de synchro |
| `period.dart` | Périodes du tableau de bord |
| `format.dart` | FCFA, dates, `fold` (recherche sans accents), `amountInWords` |
| `escpos.dart` | Constructeur ESC/POS (texte, lignes, double hauteur, images en points) |
| `raster.dart` | QR, logo (rognage, redimensionnement, tramage Floyd–Steinberg) |
| `receipts.dart` | Facture, reçu, remboursement, relevé, clôture, test |
| `printer_service.dart` | Connexion et envoi Bluetooth |
| `sync.dart` | Authentification, envoi, restauration Supabase |
| `customer_display.dart` + `MainActivity.kt` | Sous-écran client (API Android `Presentation`) |
| `product_icons.dart` | Base d'icônes et suggestion |
| `screens/` | Écrans (accueil, vente, factures, clients, produits, réglages, scan, À propos…) |

## Données (SQLite, version 4)
Tables : `settings`, `clients`, `products`, `sales`, `sale_items`, `payments`, `stock_moves`, `sync_log`.
- Montants en FCFA stockés en **entiers** ; quantités en **REAL** (poids décimaux).
- Une vente porte `subtotal`, `discount`, `total`, `status` (`active` / `refunded`) ; le **payé** est la somme des `payments` (un remboursement est un paiement négatif). Reste dû = total − payé.
- Un client comptoir n'a pas de `client_id` et doit payer en totalité.
- `products.category` (v4) : rayon ; `products.icon` : emoji.
- Migrations : `onUpgrade` pas à pas (v1 → v2 refonte, v3 icône + journal de synchro, v4 rayon).

### Journal de synchronisation
Des **triggers** SQLite (`trg_<table>_i/u/d`) écrivent chaque insertion / modification / suppression dans `sync_log(tbl, row_id, op)`. `SyncService` regroupe les opérations (`collapseLog`), envoie des lots, puis les acquitte (`ackSync`).

## Règles métier clés
- **FIFO des dettes** : un paiement libre est réparti sur les factures impayées les plus anciennes.
- **Remboursement** : statut `refunded`, paiement négatif du montant encaissé, mouvement de stock inverse.
- **Prix** : `priceFor(level)` retombe sur le prix détail si le niveau n'a pas de prix.
- **Vente au poids** : `askQuantity` (modes unité / g (ml) / montant) ; `qtyLine` formate « 500 g x 2 500 F/kg ».
- **QR** : `ARD:F:<id>` et `ARD:C:<id>` ; `ScanTarget.parse` accepte aussi « F-000123 » ou « 123 ».

## Interface
- Breakpoint `kWide = 720` : `NavigationRail` + deux colonnes (tablette, terminal) ou `NavigationBar` (téléphone).
- `AmountText` (FittedBox) évite les débordements de gros montants.
- Taille de texte limitée à 0,9–1,15 pour rester lisible sur terminal.

## Sécurité et données
- Le code d'activation est un **moyen de dissuasion** : seule son empreinte salée est dans l'application. Ce n'est pas une protection forte (le code source est public).
- La sauvegarde en ligne est cloisonnée par utilisateur via la **Row Level Security** Supabase (voir [SYNCHRONISATION.md](SYNCHRONISATION.md)).
- Aucune donnée n'est envoyée ailleurs que vers votre projet Supabase, et seulement si vous créez un compte de sauvegarde.

## Dépendances
sqflite, path, intl, print_bluetooth_thermal, permission_handler, image_picker, image, qr, qr_flutter, mobile_scanner, crypto, http, flutter_localizations. Dev : sqflite_common_ffi (tests).
