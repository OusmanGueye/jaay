import 'raster.dart';

/// Petit constructeur ESC/POS (texte uniquement), suffisant pour des reçus.
/// Testé avec l'imprimante intégrée des terminaux ZCS vue comme "BluetoothPrint".
enum Align { left, center, right }

class EscPos {
  EscPos({this.cols = 48, this.stripAccents = false}) {
    // ESC @ (reset) puis ESC t 16 (page de code Windows-1252 : accents français)
    _b.addAll([0x1B, 0x40, 0x1B, 0x74, 16]);
  }

  final int cols;
  final bool stripAccents;
  final List<int> _b = [];

  List<int> get bytes => List.unmodifiable(_b);

  static const _ascii = {
    'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ã': 'a', 'À': 'A', 'Â': 'A', 'Ä': 'A',
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'É': 'E', 'È': 'E', 'Ê': 'E', 'Ë': 'E',
    'î': 'i', 'ï': 'i', 'í': 'i', 'Î': 'I', 'Ï': 'I',
    'ô': 'o', 'ö': 'o', 'ó': 'o', 'Ô': 'O', 'Ö': 'O',
    'ù': 'u', 'û': 'u', 'ü': 'u', 'ú': 'u', 'Ù': 'U', 'Û': 'U', 'Ü': 'U',
    'ç': 'c', 'Ç': 'C', 'œ': 'oe', 'Œ': 'OE', 'ñ': 'n',
  };

  /// Remplacements pour les caractères absents de Windows-1252.
  static const _fallback = {
    '’': "'", '‘': "'", '“': '"', '”': '"', '–': '-', '—': '-', '…': '...',
    ' ': ' ', ' ': ' ', '•': '*', '→': '>', '←': '<',
  };

  /// Encode du texte en octets Windows-1252 (ou ASCII si stripAccents).
  List<int> encode(String s) {
    final out = <int>[];
    for (final rune in s.runes) {
      var ch = String.fromCharCode(rune);
      ch = _fallback[ch] ?? ch;
      if (stripAccents) {
        for (final c in (_ascii[ch] ?? ch).runes) {
          out.add(c < 128 ? c : 0x3F);
        }
        continue;
      }
      final c = ch.runes.first;
      if (ch.length > 1 || c > 255) {
        if (ch == 'œ') {
          out.add(0x9C);
        } else if (ch == 'Œ') {
          out.add(0x8C);
        } else if (ch == '€') {
          out.add(0x80);
        } else {
          out.add(0x3F);
        }
      } else if (c >= 0x80 && c <= 0x9F) {
        out.add(0x3F);
      } else {
        out.add(c);
      }
    }
    return out;
  }

  static List<String> wrap(String text, int width) {
    final lines = <String>[];
    for (final para in text.split('\n')) {
      var cur = '';
      for (var word in para.split(RegExp(r'\s+'))) {
        if (word.isEmpty) continue;
        while (word.length > width) {
          if (cur.isNotEmpty) {
            lines.add(cur);
            cur = '';
          }
          lines.add(word.substring(0, width));
          word = word.substring(width);
        }
        if (cur.isEmpty) {
          cur = word;
        } else if (cur.length + 1 + word.length <= width) {
          cur = '$cur $word';
        } else {
          lines.add(cur);
          cur = word;
        }
      }
      if (cur.isNotEmpty) lines.add(cur);
    }
    return lines;
  }

  void _align(Align a) => _b.addAll([0x1B, 0x61, a.index]);
  void _bold(bool on) => _b.addAll([0x1B, 0x45, on ? 1 : 0]);
  void _size(bool big) => _b.addAll([0x1D, 0x21, big ? 0x11 : 0x00]);

  /// Texte (retour à la ligne automatique). [big] = double largeur et hauteur.
  EscPos text(String s, {Align align = Align.left, bool bold = false, bool big = false}) {
    final width = big ? cols ~/ 2 : cols;
    _align(align);
    _bold(bold);
    _size(big);
    for (final l in wrap(s, width)) {
      _b.addAll(encode(l));
      _b.add(0x0A);
    }
    _size(false);
    _bold(false);
    _align(Align.left);
    return this;
  }

  /// Une ligne avec un texte à gauche et un texte à droite.
  EscPos row(String left, String right, {bool bold = false}) {
    final maxLeft = cols - right.length - 1;
    var l = left;
    if (l.length > maxLeft) l = l.substring(0, maxLeft < 0 ? 0 : maxLeft);
    final gap = cols - l.length - right.length;
    _align(Align.left);
    _bold(bold);
    _b.addAll(encode('$l${' ' * (gap < 1 ? 1 : gap)}$right'));
    _b.add(0x0A);
    _bold(false);
    return this;
  }

  /// Ligne en double hauteur (totaux importants), gauche / droite.
  EscPos rowTall(String left, String right) {
    _align(Align.left);
    _bold(true);
    _b.addAll([0x1D, 0x21, 0x01]);
    final gap = cols - left.length - right.length;
    _b.addAll(encode('$left${' ' * (gap < 1 ? 1 : gap)}$right'));
    _b.add(0x0A);
    _size(false);
    _bold(false);
    return this;
  }

  /// Texte centré dans un cadre : ligne de '=' au-dessus et en dessous.
  EscPos banner(String s, {String? sub}) {
    line('=');
    text(s, align: Align.center, bold: true);
    if (sub != null) text(sub, align: Align.center);
    line('=');
    return this;
  }

  EscPos line([String ch = '-']) {
    _align(Align.left);
    _b.addAll(encode(ch * cols));
    _b.add(0x0A);
    return this;
  }

  EscPos feed([int n = 1]) {
    _b.addAll(List.filled(n, 0x0A));
    return this;
  }

  /// Largeur du papier en points (203 dpi) : 576 pour 80 mm, 384 pour 58 mm.
  int get paperDots => cols <= 32 ? 384 : 576;

  /// Image en points (logo, QR), centrée sur la largeur du papier, envoyée par bandes.
  EscPos raster(Raster r) {
    final p = r.padded(paperDots);
    _align(Align.left);
    const band = 64;
    for (var y = 0; y < p.height; y += band) {
      final h = (y + band > p.height) ? p.height - y : band;
      _b.addAll([0x1D, 0x76, 0x30, 0x00, p.widthBytes & 0xFF, p.widthBytes >> 8, h & 0xFF, h >> 8]);
      _b.addAll(p.data.sublist(y * p.widthBytes, (y + h) * p.widthBytes));
    }
    return this;
  }
}
