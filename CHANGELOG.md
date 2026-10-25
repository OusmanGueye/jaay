# Historique des versions

## 2.4
- L'application est renommée **Jaay** (« vendre » en wolof) ; nouvelle icône (lettre J).

## 2.3.1
- Application renommée « Faye Facturation » (nom abandonné depuis la 2.4).
- Le code d'activation de production n'est plus dans le code public (compilation avec `--dart-define=ACTIVATION_HASH`) ; code de démonstration `DEMO-2026`.

## 2.3
- Écran de vente : rayons, « Populaires », recherche sans accents et multi-mots, boutons − / + dans le panier, « Rupture », vente d'un texte introuvable comme article libre.
- Produits : rayon / catégorie, filtre « Stock bas », recherche sans accents.
- Ticket : titre encadré, totaux en double hauteur, règlements datés, montant en lettres, mention « PAYE - MERCI », QR légendé. Même style pour reçus, remboursements, relevés et clôtures.
- Base de données v4 (colonne `category`).

## 2.2
- Vente au poids / volume (g, ml, par montant).
- Icônes produits (base d'emojis + suggestion automatique).
- Sauvegarde et synchronisation Supabase automatiques.
- Nouvelle icône d'application.

## 2.1
- Code d'activation au premier lancement, mention légale.
- Filtres par période, tableau de bord responsive (montants qui ne débordent pas).
- Scan caméra avec demande d'autorisation explicite.
- Sous-écran client, logo plus petit sur les tickets, thème modernisé.

## 2.0
- Refonte : ventes, paiements par tranches, QR, remboursement, produits / stock, thème.

## 1.0
- Carnet de crédit simple (remplacé par le modèle ventes / paiements).
