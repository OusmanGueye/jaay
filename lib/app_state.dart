import 'package:flutter/foundation.dart';

import 'db.dart';
import 'models.dart';

/// Panier de la vente en cours (conservé quand on change d'onglet).
class Cart extends ChangeNotifier {
  final List<CartLine> lines = [];
  Client? client; // null = client comptoir
  String level = 'detail';
  int discount = 0;

  int get subtotal => lines.fold(0, (s, l) => s + l.total);
  int get total => (subtotal - discount).clamp(0, subtotal);
  bool get isEmpty => lines.isEmpty;

  void add(Product p, {double qty = 1}) {
    final i = lines.indexWhere((l) => l.productId == p.id && l.level == level);
    if (i >= 0) {
      lines[i].qty += qty;
    } else {
      lines.add(CartLine(
        productId: p.id,
        name: p.name,
        unit: p.unit,
        qty: qty,
        unitPrice: p.priceFor(level),
        level: level,
      ));
    }
    notifyListeners();
  }

  void addFree(String name, int price, double qty, String unit) {
    lines.add(CartLine(name: name, unit: unit, qty: qty, unitPrice: price, level: level));
    notifyListeners();
  }

  void removeAt(int i) {
    lines.removeAt(i);
    if (lines.isEmpty) discount = 0;
    notifyListeners();
  }

  void changed() => notifyListeners();

  void setClient(Client? c) {
    client = c;
    notifyListeners();
  }

  void setDiscount(int d) {
    discount = d.clamp(0, subtotal);
    notifyListeners();
  }

  void clear() {
    lines.clear();
    discount = 0;
    client = null;
    notifyListeners();
  }
}

/// État global : réglages (thème, boutique), panier, onglet courant.
class AppState extends ChangeNotifier {
  AppState._();
  static final AppState i = AppState._();

  AppSettings settings = AppSettings();
  final Cart cart = Cart();

  /// Incrémenté après chaque écriture en base : les écrans se rechargent.
  final ValueNotifier<int> dataVersion = ValueNotifier(0);

  /// Onglet affiché par le menu principal.
  final ValueNotifier<int> tab = ValueNotifier(0);

  Future<void> load() async {
    final db = await Db.instance;
    settings = await db.loadSettings();
    notifyListeners();
  }

  Future<void> saveSettings(AppSettings s) async {
    final db = await Db.instance;
    await db.saveSettings(s);
    settings = s;
    notifyListeners();
  }

  void touch() => dataVersion.value++;
}
