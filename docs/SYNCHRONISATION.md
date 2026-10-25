# Synchronisation Supabase

## Principe
L'application est **hors ligne d'abord**. Chaque modification locale est notée par des triggers SQLite, puis envoyée à Supabase quand le réseau est disponible. Aucun service tiers autre que votre projet Supabase.

## Quand la synchronisation part-elle ?
Automatiquement, si un compte est connecté :
- toutes les **90 secondes** ;
- **4 secondes** après un changement (vente, paiement, produit…) ;
- à chaque **reprise** de l'application.
Sans connexion, rien n'est perdu : les opérations restent en attente.

## Compte
E-mail + mot de passe via Supabase Auth (GoTrue), appelé en REST avec le paquet `http` (pas de `supabase_flutter`). La session est conservée dans les réglages locaux (`sb_session`) et renouvelée avec le refresh token. L'inscription demande la confirmation de l'e-mail.

## Modèle de données serveur
Une table générique stocke toutes les lignes en JSON :

| Table | Colonnes |
|---|---|
| `gf_records` | `user_id`, `device_id`, `tbl`, `id`, `data jsonb`, `deleted`, `updated_at` — clé primaire `(user_id, device_id, tbl, id)` |
| `gf_devices` | `user_id`, `device_id`, `name`, `app_version`, `last_sync` |

Le schéma complet et la sécurité sont dans [`supabase/schema.sql`](../supabase/schema.sql).

## Envoi
`POST /rest/v1/gf_records?on_conflict=user_id,device_id,tbl,id` avec `Prefer: resolution=merge-duplicates`. Toutes les lignes d'un lot ont les **mêmes clés JSON** (exigence de PostgREST). Les suppressions sont envoyées avec `deleted = true`.

## Restauration
Sur une base locale **vide**, l'application propose de restaurer : elle adopte le `device_id` sauvegardé et recharge toutes les tables. La restauration est refusée si des données locales existent.

## Sécurité
- **Row Level Security** sur les deux tables : un utilisateur ne voit et n'écrit que ses lignes (`auth.uid() = user_id`).
- Seule la clé **publishable** est dans l'application (conçue pour être publique). Ne mettez jamais la clé `service_role` dans l'application.
- Testé : un second compte ne voit rien ; l'écriture sur les lignes d'un autre compte renvoie 403 ; la lecture anonyme renvoie une liste vide.

## Limites
Sauvegarde à sens unique + restauration. Pas de fusion en temps réel entre plusieurs appareils.
