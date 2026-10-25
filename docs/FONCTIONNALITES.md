# Fonctionnalités

## 1. Boutique et personnalisation
- Nom, adresse, deux numéros de téléphone, message de fin de ticket.
- Logo (rogné automatiquement, taille petit / moyen / grand, tramé noir et blanc pour l'imprimante thermique).
- Couleur principale (palette) et mode clair / sombre / automatique.
- Mention légale « Ousmane Gueye » (écran À propos).
- Code d'activation demandé **une seule fois** au premier lancement.

## 2. Vente
- Grille de produits avec icône, prix du niveau choisi, stock restant, pastille de quantité déjà au panier.
- **Niveau de prix** : Détail / Demi-gros / Gros (si un prix n'est pas renseigné, le prix détail est utilisé).
- **Recherche** sans accents ni majuscules, plusieurs mots dans n'importe quel ordre, sur le nom, le rayon et le code-barres.
- **Rayons** (catégories) et pastille **Populaires** (les plus vendus), affichés à partir de 8 produits.
- **Scan code-barres** d'un produit.
- **Article libre** : désignation, quantité, unité, prix.
- **Panier** : boutons − / +, modification d'une ligne (quantité, prix), remise globale, changement de client.
- **Vente au poids / volume** : pour un produit en kg ou litre, la quantité se saisit en kg, en grammes (250 g, 500 g) ou « par montant » (500 F). L'unité (sac, carton, kg…) est **indicative**.
- **Encaissement** : montant reçu, boutons rapides (Exact, arrondis), mode (espèces, Wave, Orange Money), monnaie à rendre, reste à crédit.
- **Client comptoir** : paiement complet obligatoire, pas de fiche client.

## 3. Clients et ardoise
- Fiche client : prénom, nom, téléphone, note. Aucune autre information obligatoire.
- Solde = somme des restes à payer de ses factures.
- **Paiement par tranches** sur une facture, ou **paiement libre** réparti automatiquement sur les plus anciennes dettes (FIFO).
- Reçu de paiement et **relevé de compte** imprimables.
- Suppression d'un client refusée tant qu'il a une dette.

## 4. Factures
- Numérotation `F-000123`.
- Liste filtrable par période et par état (toutes / impayées).
- Détail : articles, règlements, reste à payer, QR, duplicata, nouvelle tranche.
- **Remboursement** : la facture est annulée, l'argent déjà encaissé est rendu, le stock est remis.
- **QR codes** : `ARD:F:<id>` (facture) et `ARD:C:<id>` (client) ; saisie manuelle du numéro possible.

## 5. Tableau de bord
- Filtres : aujourd'hui, hier, semaine, mois, mois dernier, année, période libre.
- Ventes, nombre de factures, net encaissé, crédits accordés, dettes payées, remboursements.
- Encaissements par mode avec barres de progression.
- Alerte de stock bas, accès rapide aux actions, dernières factures.
- **Clôture de caisse** imprimable.

## 6. Produits et stock
- Nom, icône (≈ 90 emojis classés + suggestion automatique selon le nom), rayon, unité, trois prix, code-barres.
- Stock **facultatif** (activable / désactivable globalement et par produit) : décrémenté à chaque vente, remis au remboursement, entrées / sorties manuelles, seuil d'alerte.
- Filtres par rayon et « Stock bas ».
- Archivage d'un produit (les anciennes factures ne changent pas).

## 7. Impression
- Imprimante Bluetooth ESC/POS (ZCS Z108 : « BluetoothPrint »), 80 mm (48 colonnes) ou 58 mm.
- Accents Windows-1252 avec option « Supprimer les accents ».
- Logo et QR envoyés en points. Voir [IMPRESSION.md](IMPRESSION.md).

## 8. Sous-écran client
Sur les terminaux à double écran, la vente en cours (dernières lignes et total) s'affiche côté client. Réglages indique si un second écran est détecté.

## 9. Sauvegarde en ligne
Compte e-mail + mot de passe, envoi automatique, restauration sur un appareil neuf. Voir [SYNCHRONISATION.md](SYNCHRONISATION.md).

## Limites connues
- Le stock des produits « sac » et « kg » n'est pas relié (pas de conversion de conditionnement).
- Remboursement total uniquement (pas partiel).
- Synchronisation à sens unique (sauvegarde) + restauration ; pas de fusion multi-appareils en temps réel.
- Le sous-écran client n'a pas pu être testé sur tous les modèles.
