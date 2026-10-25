import 'package:intl/intl.dart';

/// Formate un montant en FCFA, sans décimales : 1250000 -> "1 250 000 F".
/// En impression on utilise un espace simple ; à l'écran un espace insécable.
String fcfa(int v, {bool forPrint = false}) {
  final neg = v < 0;
  final s = v.abs().toString();
  final sep = forPrint ? ' ' : ' ';
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(sep);
    b.write(s[i]);
  }
  return '${neg ? '-' : ''}$b${forPrint ? ' F' : ' F'}';
}

/// Extrait un entier d'un texte saisi ("150 000" -> 150000). Null si vide.
int? parseAmount(String s) {
  final digits = s.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return null;
  return int.tryParse(digits);
}

final DateFormat _dt = DateFormat('dd/MM/yyyy HH:mm');
final DateFormat _d = DateFormat('dd/MM/yyyy');
final DateFormat _short = DateFormat('dd/MM');

String fmtDateTime(int ms) => _dt.format(DateTime.fromMillisecondsSinceEpoch(ms));
String fmtDate(int ms) => _d.format(DateTime.fromMillisecondsSinceEpoch(ms));
String fmtShort(int ms) => _short.format(DateTime.fromMillisecondsSinceEpoch(ms));

/// Minuscules sans accents, pour chercher « riz brisé » en tapant « riz brise ».
String fold(String s) {
  const from = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿœ';
  const to = 'aaaaaaceeeeiiiinooooouuuuyyo';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b.toString();
}

const _units = [
  'zéro', 'un', 'deux', 'trois', 'quatre', 'cinq', 'six', 'sept', 'huit', 'neuf', 'dix', 'onze', 'douze',
  'treize', 'quatorze', 'quinze', 'seize',
];
const _tens = ['', '', 'vingt', 'trente', 'quarante', 'cinquante', 'soixante'];

String _below100(int n, bool allowS) {
  if (n < 17) return _units[n];
  if (n < 20) return 'dix-${_units[n - 10]}';
  if (n < 70) {
    final t = _tens[n ~/ 10], u = n % 10;
    return u == 0 ? t : (u == 1 ? '$t et un' : '$t-${_units[u]}');
  }
  if (n < 80) return n == 71 ? 'soixante et onze' : 'soixante-${_below100(n - 60, false)}';
  if (n == 80) return allowS ? 'quatre-vingts' : 'quatre-vingt';
  return 'quatre-vingt-${_below100(n - 80, false)}';
}

String _below1000(int n, bool allowS) {
  final h = n ~/ 100, r = n % 100;
  final parts = <String>[];
  if (h > 0) parts.add(h == 1 ? 'cent' : '${_units[h]} cent${r == 0 && allowS ? 's' : ''}');
  if (r > 0) parts.add(_below100(r, allowS));
  return parts.join(' ');
}

/// Nombre en toutes lettres : 1250000 -> "un million deux cent cinquante mille".
String numberToFrench(int n) {
  if (n == 0) return 'zéro';
  if (n < 0) return 'moins ${numberToFrench(-n)}';
  final parts = <String>[];
  final milliards = n ~/ 1000000000, millions = (n ~/ 1000000) % 1000, milliers = (n ~/ 1000) % 1000, reste = n % 1000;
  if (milliards > 0) parts.add('${_below1000(milliards, true)} milliard${milliards > 1 ? 's' : ''}');
  if (millions > 0) parts.add('${_below1000(millions, true)} million${millions > 1 ? 's' : ''}');
  if (milliers > 0) parts.add(milliers == 1 ? 'mille' : '${_below1000(milliers, false)} mille');
  if (reste > 0) parts.add(_below1000(reste, true));
  return parts.join(' ');
}

/// "cent mille francs CFA" (pour « Arrêtée à la somme de… » sur les factures).
String amountInWords(int amount) {
  final w = numberToFrench(amount);
  return '$w franc${amount > 1 ? 's' : ''} CFA';
}
