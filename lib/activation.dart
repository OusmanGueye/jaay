import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Nom de l'application et mention légale.
const kAppName = 'Jaay';
const kOwner = 'Ousmane Gueye';
const kLegal =
    '$kAppName est un logiciel propriétaire développé par $kOwner. '
    '© 2026 $kOwner. Tous droits réservés.\n\n'
    'Toute copie, diffusion, revente, décompilation ou mise à disposition de tiers sans '
    'l\'autorisation écrite de $kOwner est interdite.\n\n'
    'Les données saisies (clients, ventes, produits) restent la propriété de l\'exploitant de la boutique '
    'et sont enregistrées sur l\'appareil.';

// Seule l'empreinte du code d'activation est dans l'application, jamais le code lui-même.
// L'empreinte de production est fournie à la compilation (--dart-define=ACTIVATION_HASH=...) et
// n'est pas dans le dépôt public ; par défaut (code source public) le code d'activation est DEMO-2026.
const _salt = 'gueye-facturation-v1';
const _hash = String.fromEnvironment('ACTIVATION_HASH', defaultValue: '65f33b14060bc0d16b3d336c1c5ed816d4ea25ecf2cc7f6e857b2d44e3c9d3dc');

String activationHash(String code) => sha256.convert(utf8.encode('$_salt:${code.trim()}')).toString();

bool checkActivationCode(String code) => activationHash(code) == _hash;
