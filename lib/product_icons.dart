import 'package:flutter/material.dart';

/// Base d'icônes (emojis) pour les produits, rangées par rayon.
const kIconGroups = <String, List<String>>{
  'Céréales': ['🌾', '🍚', '🌽', '🫘', '🥜', '🌰', '🍞', '🥖', '🥐', '🍝', '🫓'],
  'Épicerie': ['🧂', '🍬', '🍯', '🫙', '🥫', '🧈', '🥚', '🧀', '🥛', '🍫', '🍪', '🥣', '🧁', '🍿'],
  'Boissons': ['💧', '🥤', '🧃', '☕', '🍵', '🍺', '🍷', '🧋', '🍶'],
  'Fruits & légumes': ['🧅', '🧄', '🥔', '🍅', '🥕', '🌶️', '🥬', '🥒', '🍆', '🍋', '🍊', '🍌', '🥭', '🍍', '🥥', '🍉', '🍎', '🍇', '🌳'],
  'Viande & poisson': ['🐟', '🍤', '🍖', '🍗', '🥩', '🐓', '🐑', '🐄'],
  'Maison': ['🧼', '🧴', '🧽', '🧹', '🪣', '🕯️', '🔋', '💡', '🪑', '🔥', '🛢️'],
  'Hygiène': ['🪥', '🧻', '👶', '🩹', '💊', '🧸'],
  'Agriculture': ['🌱', '🌿', '🚜', '🧪', '🌻', '🪴', '🐝'],
  'Divers': ['📦', '🛍️', '🛒', '🔧', '👕', '👟', '📱', '🎒', '⚽', '✏️', '🔑', '⭐'],
};

/// Mots-clés -> icône proposée automatiquement d'après le nom du produit.
const _kKeywords = <String, String>{
  'riz': '🍚', 'sucre': '🍬', 'sel': '🧂', 'huile': '🫙', 'farine': '🌾', 'mil': '🌾', 'maïs': '🌽', 'mais': '🌽',
  'petit pois': '🫘', 'pois': '🫘', 'haricot': '🫘', 'niébé': '🫘', 'niebe': '🫘', 'arachide': '🥜', 'cacahu': '🥜',
  'oignon': '🧅', 'ail': '🧄', 'pomme de terre': '🥔', 'patate': '🥔', 'tomate': '🍅', 'carotte': '🥕', 'piment': '🌶️',
  'lait': '🥛', 'oeuf': '🥚', 'œuf': '🥚', 'pain de singe': '🌳', 'bouye': '🌳', 'baobab': '🌳', 'pain': '🍞',
  'café': '☕', 'cafe': '☕', 'thé': '🍵', 'the ': '🍵', 'eau': '💧', 'jus': '🧃', 'savon': '🧼', 'lessive': '🧴',
  'javel': '🧴', 'poisson': '🐟', 'sardine': '🥫', 'conserve': '🥫', 'concentré': '🥫', 'concentre': '🥫',
  'poulet': '🍗', 'viande': '🥩', 'beurre': '🧈', 'fromage': '🧀', 'miel': '🍯', 'semence': '🌱', 'graine': '🌱',
  'semis': '🌱', 'engrais': '🌿', 'pile': '🔋', 'bougie': '🕯️', 'couche': '👶', 'papier': '🧻', 'banane': '🍌',
  'mangue': '🥭', 'citron': '🍋', 'orange': '🍊', 'coco': '🥥', 'pâte': '🍝', 'pate': '🍝', 'spaghetti': '🍝',
  'macaroni': '🍝', 'biscuit': '🍪', 'chocolat': '🍫', 'bonbon': '🍬', 'thon': '🥫', 'mayonnaise': '🫙',
  'vinaigre': '🫙', 'cube': '🧂', 'maggi': '🧂', 'sac': '📦', 'carton': '📦',
};

/// Icône proposée d'après le nom (vide si rien ne correspond).
String suggestIcon(String name) {
  final n = name.toLowerCase();
  var best = '';
  var bestLen = 0;
  for (final e in _kKeywords.entries) {
    if (n.contains(e.key) && e.key.length > bestLen) {
      best = e.value;
      bestLen = e.key.length;
    }
  }
  return best;
}

/// Vignette d'un produit : son emoji, ou son initiale si aucune icône n'est choisie.
class ProductIcon extends StatelessWidget {
  const ProductIcon({super.key, required this.icon, required this.name, this.size = 44});
  final String icon;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: cs.primaryContainer.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(size * 0.3)),
      child: icon.isNotEmpty
          ? Text(icon, style: TextStyle(fontSize: size * 0.55))
          : Text(name.isEmpty ? '?' : name.characters.first.toUpperCase(), style: TextStyle(fontSize: size * 0.42, fontWeight: FontWeight.w700, color: cs.onPrimaryContainer)),
    );
  }
}

/// Fenêtre de choix d'icône. Retourne l'emoji choisi, '' pour « aucune », null si annulé.
Future<String?> pickProductIcon(BuildContext context, {String current = ''}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Row(children: [
            Expanded(child: Text('Choisir une icône', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
            TextButton(onPressed: () => Navigator.pop(context, ''), child: const Text('Aucune')),
          ]),
          for (final g in kIconGroups.entries) ...[
            Padding(padding: const EdgeInsets.only(top: 12, bottom: 6), child: Text(g.key, style: Theme.of(context).textTheme.labelLarge)),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in g.value)
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => Navigator.pop(context, e),
                  child: Container(
                    width: 52,
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: e == current ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surfaceContainerHigh,
                      border: e == current ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2) : null,
                    ),
                    child: Text(e, style: const TextStyle(fontSize: 28)),
                  ),
                ),
            ]),
          ],
        ],
      ),
    ),
  );
}
