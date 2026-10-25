# Impression et ticket

## Matériel
ZCS Z108 : imprimante thermique 80 mm intégrée, vue comme périphérique Bluetooth **« BluetoothPrint »**. Aucun SDK propriétaire : l'application envoie des commandes **ESC/POS** brutes via `print_bluetooth_thermal`.

## Réglages
| Réglage | Effet |
|---|---|
| Largeur | 48 colonnes (80 mm), 42 ou 32 (58 mm) |
| Supprimer les accents | Imprime sans accents si la page de codes pose problème |
| Imprimer le logo / taille | Petit (par défaut), moyen, grand |
| Impression automatique | Imprime dès la validation d'une vente |

## Techniques
- Page de codes **Windows-1252** (`ESC t 16`) : accents français ; repli ASCII.
- Images (logo, QR) : commande `GS v 0` envoyée par **bandes de 64 lignes**, centrées par remplissage à 576 points (80 mm) ou 384 (58 mm).
- Logo : marges blanches rognées, réduit, tramé Floyd–Steinberg.
- QR : bibliothèque `qr`, niveau de correction M, rendu en points.
- Double hauteur (`GS ! 0x01`) pour TOTAL, RESTE A PAYER, MONTANT RECU.

## Modèle de ticket de vente
```
        [LOGO]
     NOM DE LA BOUTIQUE
        Adresse
     Tel : 77 000 00 00
================================================
        FACTURE F-000123
        25/10/2026 15:10
================================================
Client : Awa Ndiaye
------------------------------------------------
ARTICLES                                 MONTANT
------------------------------------------------
Riz brisé
  10 sac x 15 000 F                    150 000 F
------------------------------------------------
Nombre d'articles                              1
================================================
TOTAL (double hauteur)                 150 000 F
================================================
Reglements
  25/10  Espèces                        50 000 F
------------------------------------------------
RESTE A PAYER (double hauteur)         100 000 F

Je reconnais devoir la somme de 100 000 F
(cent mille francs CFA) a Nom de la boutique.

Signature du client :

              [QR]
              F-000123
Scannez pour retrouver cette facture
      Merci de votre confiance !
```
Facture soldée : « *** PAYE - MERCI *** » et « Arretee a la somme de … ».
Facture annulée : bandeau « VENTE ANNULEE » et montant remboursé.

## Autres documents
Reçu de paiement, remboursement, relevé de compte, clôture de caisse et ticket de test partagent le même en-tête et le même style (`lib/receipts.dart`).

## Ajouter ou modifier un ticket
Chaque ticket est une fonction `List<int> xxxReceipt(AppSettings, …)` qui compose des appels `EscPos` (`text`, `row`, `rowTall`, `banner`, `line`, `raster`). Les tests (`test/ardoise_test.dart`) décodent les octets en texte pour vérifier le contenu.
