import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:qr/qr.dart';

/// Image noir/blanc prête pour la commande ESC/POS « GS v 0 » (impression en points).
class Raster {
  Raster(this.widthBytes, this.height, this.data);

  /// Largeur en octets (8 points par octet).
  final int widthBytes;
  final int height;

  /// Lignes empaquetées, bit 1 = point noir.
  final Uint8List data;

  int get width => widthBytes * 8;

  /// Centre l'image dans une largeur de papier de [paperDots] points.
  Raster padded(int paperDots) {
    final pw = paperDots ~/ 8;
    if (pw <= widthBytes) return this;
    final left = (pw - widthBytes) ~/ 2;
    final out = Uint8List(pw * height);
    for (var y = 0; y < height; y++) {
      out.setRange(y * pw + left, y * pw + left + widthBytes, data, y * widthBytes);
    }
    return Raster(pw, height, out);
  }

  /// Construit une image à partir d'une grille de pixels noirs (true).
  static Raster fromBits(int w, int h, bool Function(int x, int y) black) {
    final wb = (w + 7) ~/ 8;
    final out = Uint8List(wb * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (black(x, y)) out[y * wb + (x >> 3)] |= 0x80 >> (x & 7);
      }
    }
    return Raster(wb, h, out);
  }

  /// QR code (zone blanche de 4 modules autour) d'environ [targetDots] points de large.
  static Raster qr(String data, {int targetDots = 216}) {
    final code = QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.M);
    final image = QrImage(code);
    final n = image.moduleCount;
    final scale = (targetDots ~/ (n + 8)).clamp(3, 10);
    final size = (n + 8) * scale;
    return fromBits(size, size, (x, y) {
      final mx = x ~/ scale - 4;
      final my = y ~/ scale - 4;
      if (mx < 0 || my < 0 || mx >= n || my >= n) return false;
      return image.isDark(my, mx);
    });
  }

  /// Logo (PNG/JPEG en base64) : marges blanches rognées, réduit pour tenir dans
  /// [maxDots] × [maxHeight] points (proportions conservées), puis tramé noir et blanc.
  static Raster? logo(String b64, {int maxDots = 140, int maxHeight = 70}) {
    try {
      var src = img.decodeImage(base64Decode(b64));
      if (src == null) return null;
      src = _cropMargins(src);
      final k = [maxDots / src.width, maxHeight / src.height, 1.0].reduce((a, b) => a < b ? a : b);
      final w = (src.width * k).round().clamp(8, maxDots);
      final resized = k < 1 ? img.copyResize(src, width: w, interpolation: img.Interpolation.average) : src;
      return _dither(resized);
    } catch (_) {
      return null;
    }
  }

  /// Enlève les bords blancs / transparents autour du dessin pour ne pas gaspiller de papier.
  static img.Image _cropMargins(img.Image im) {
    var minX = im.width, minY = im.height, maxX = -1, maxY = -1;
    for (var y = 0; y < im.height; y++) {
      for (var x = 0; x < im.width; x++) {
        final px = im.getPixel(x, y);
        final a = px.a / px.maxChannelValue;
        final l = (0.299 * px.r + 0.587 * px.g + 0.114 * px.b) / px.maxChannelValue * 255;
        if (a > 0.1 && l < 235) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }
    if (maxX < 0) return im;
    return img.copyCrop(im, x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1);
  }

  /// Floyd–Steinberg : rend bien les logos en niveaux de gris sur imprimante thermique.
  static Raster _dither(img.Image im) {
    final w = im.width, h = im.height;
    final lum = List<double>.filled(w * h, 255);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final px = im.getPixel(x, y);
        final a = px.a / px.maxChannelValue;
        final l = (0.299 * px.r + 0.587 * px.g + 0.114 * px.b) / px.maxChannelValue * 255;
        lum[y * w + x] = l * a + 255 * (1 - a);
      }
    }
    final black = List<bool>.filled(w * h, false);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        final old = lum[i];
        final nw = old < 128 ? 0.0 : 255.0;
        black[i] = nw == 0;
        final err = old - nw;
        if (x + 1 < w) lum[i + 1] += err * 7 / 16;
        if (y + 1 < h) {
          if (x > 0) lum[i + w - 1] += err * 3 / 16;
          lum[i + w] += err * 5 / 16;
          if (x + 1 < w) lum[i + w + 1] += err * 1 / 16;
        }
      }
    }
    return fromBits(w, h, (x, y) => black[y * w + x]);
  }
}

/// Réduit et convertit une image choisie par l'utilisateur en PNG léger (niveaux de gris),
/// stocké en base64 dans la base de données.
String? prepareLogo(Uint8List bytes, {int maxWidth = 384}) {
  final src = img.decodeImage(bytes);
  if (src == null) return null;
  var im = src.width > maxWidth ? img.copyResize(src, width: maxWidth) : src;
  im = img.grayscale(im);
  return base64Encode(img.encodePng(im));
}
