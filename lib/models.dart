// Modèles de données de l'application.
import 'format.dart';

const kLevels = ['detail', 'semi', 'gros'];
const kLevelLabels = {'detail': 'Détail', 'semi': 'Demi-gros', 'gros': 'Gros'};

const kMethods = ['cash', 'wave', 'om'];
const kMethodLabels = {'cash': 'Espèces', 'wave': 'Wave', 'om': 'Orange Money'};

String methodLabel(String m) => kMethodLabels[m] ?? m;

/// Quantité sans zéros inutiles : 2.0 -> "2", 2.5 -> "2,5".
String fmtQty(double q) {
  if (q == q.roundToDouble()) return q.round().toString();
  var s = q.toStringAsFixed(3);
  s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return s.replaceAll('.', ',');
}

/// Quantité avec son unité, en grammes / millilitres quand c'est moins d'une unité :
/// 0,5 kg -> "500 g", 0,25 litre -> "250 ml", 2 sac -> "2 sac".
String fmtQtyUnit(double q, String unit) {
  final u = unit.trim().toLowerCase();
  if (q > 0 && q < 1) {
    if (u == 'kg') return '${(q * 1000).round()} g';
    if (u == 'litre' || u == 'l') return '${(q * 1000).round()} ml';
  }
  return unit.isEmpty ? fmtQty(q) : '${fmtQty(q)} $unit';
}

/// Détail d'une ligne : "2 sac x 15 000 F" ou "500 g x 2 500 F/kg".
String qtyLine(double q, String unit, int unitPrice, {bool forPrint = false}) {
  final converted = q > 0 && q < 1 && ['kg', 'litre', 'l'].contains(unit.trim().toLowerCase());
  return '${fmtQtyUnit(q, unit)} x ${fcfa(unitPrice, forPrint: forPrint)}${converted ? '/$unit' : ''}';
}

/// Lit un nombre saisi avec virgule ou point ("2,5" -> 2.5). Null si invalide.
double? parseQty(String s) {
  final t = s.trim().replaceAll(',', '.').replaceAll(' ', '');
  if (t.isEmpty) return null;
  return double.tryParse(t);
}

class Client {
  Client({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.note,
    required this.balance,
    required this.lastAt,
  });

  final int id;
  final String firstName;
  final String lastName;
  final String phone;
  final String note;

  /// Ce que le client doit encore (somme des restes à payer).
  final int balance;
  final int? lastAt;

  String get fullName => '$firstName $lastName'.trim();
}

class Product {
  Product({
    this.id = 0,
    required this.name,
    this.unit = 'pièce',
    this.priceRetail = 0,
    this.priceSemi = 0,
    this.priceWholesale = 0,
    this.barcode = '',
    this.trackStock = false,
    this.stock = 0,
    this.minStock = 0,
    this.active = true,
    this.icon = '',
    this.category = '',
  });

  final int id;
  final String name;

  /// Emoji choisi dans la base d'icônes (facultatif).
  final String icon;

  /// Rayon (Céréales, Épicerie, Boissons…) pour filtrer quand il y a beaucoup de produits.
  final String category;
  final String unit;
  final int priceRetail;
  final int priceSemi;
  final int priceWholesale;
  final String barcode;
  final bool trackStock;
  final double stock;
  final double minStock;
  final bool active;

  /// Prix selon le niveau de vente ; si le prix n'est pas renseigné, on prend le prix détail.
  int priceFor(String level) {
    final p = switch (level) {
      'semi' => priceSemi,
      'gros' => priceWholesale,
      _ => priceRetail,
    };
    return p > 0 ? p : priceRetail;
  }

  bool get low => trackStock && stock <= minStock;
}

/// Ligne du panier (avant enregistrement de la vente).
class CartLine {
  CartLine({
    this.productId,
    required this.name,
    required this.unit,
    required this.qty,
    required this.unitPrice,
    required this.level,
  });

  final int? productId;
  final String name;
  final String unit;
  double qty;
  int unitPrice;
  String level;

  int get total => (qty * unitPrice).round();
}

class SaleItem {
  SaleItem({
    required this.name,
    required this.unit,
    required this.qty,
    required this.unitPrice,
    required this.total,
    this.productId,
  });

  final int? productId;
  final String name;
  final String unit;
  final double qty;
  final int unitPrice;
  final int total;
}

class Payment {
  Payment({
    required this.id,
    required this.saleId,
    required this.amount,
    required this.method,
    required this.note,
    required this.createdAt,
  });

  final int id;
  final int saleId;

  /// Négatif = remboursement.
  final int amount;
  final String method;
  final String note;
  final int createdAt;

  bool get isRefund => amount < 0;
}

class Sale {
  Sale({
    required this.id,
    required this.clientId,
    required this.clientName,
    required this.subtotal,
    required this.discount,
    required this.total,
    required this.status,
    required this.note,
    required this.createdAt,
    required this.paid,
    this.items = const [],
    this.payments = const [],
  });

  final int id;
  final int? clientId;
  final String clientName;
  final int subtotal;
  final int discount;
  final int total;

  /// 'active' ou 'refunded'.
  final String status;
  final String note;
  final int createdAt;

  /// Somme nette des paiements (remboursements déduits).
  final int paid;
  final List<SaleItem> items;
  final List<Payment> payments;

  bool get refunded => status == 'refunded';
  int get due => refunded ? 0 : (total - paid).clamp(0, total);
  bool get settled => !refunded && due == 0;

  String get number => saleNumber(id);
  String get displayClient => clientName.isEmpty ? 'Client comptoir' : clientName;
  String get qrData => saleQr(id);
}

String saleNumber(int id) => 'F-${id.toString().padLeft(6, '0')}';
String saleQr(int id) => 'ARD:F:$id';
String clientQr(int id) => 'ARD:C:$id';

/// Contenu d'un QR Ardoise lu à la caméra.
class ScanTarget {
  ScanTarget(this.kind, this.id);
  final String kind; // 'F' facture, 'C' client
  final int id;

  static ScanTarget? parse(String raw) {
    final m = RegExp(r'^ARD:([FC]):(\d+)$').firstMatch(raw.trim());
    if (m != null) return ScanTarget(m.group(1)!, int.parse(m.group(2)!));
    // Saisie manuelle d'un numéro de facture : "F-000123" ou "123"
    final n = RegExp(r'^F?-?0*(\d+)$', caseSensitive: false).firstMatch(raw.trim());
    if (n != null) return ScanTarget('F', int.parse(n.group(1)!));
    return null;
  }
}

class DaySummary {
  DaySummary({
    required this.salesCount,
    required this.salesTotal,
    required this.collected,
    required this.refunded,
    required this.creditGranted,
    required this.debtsCollected,
  });

  final int salesCount;
  final int salesTotal;

  /// Encaissements du jour par mode (espèces, wave, om).
  final Map<String, int> collected;
  final int refunded;

  /// Part des ventes du jour restée à crédit.
  final int creditGranted;

  /// Encaissements du jour sur des ventes d'un jour précédent (dettes payées).
  final int debtsCollected;

  int get collectedTotal => collected.values.fold(0, (a, b) => a + b);
  int get net => collectedTotal - refunded;
}

class AppSettings {
  AppSettings();

  String shopName = 'MA BOUTIQUE';
  String address = '';
  String phone1 = '';
  String phone2 = '';
  String footer = 'Merci de votre confiance !';

  /// Logo traité (PNG en niveaux de gris) encodé en base64.
  String? logoB64;
  int colorValue = 0xFF1B7F4B;

  /// 'system' | 'light' | 'dark'
  String themeMode = 'system';

  String? printerMac;
  String printerName = '';
  int cols = 48;
  bool stripAccents = false;
  bool printLogo = true;
  bool autoPrint = true;
  bool stockEnabled = true;

  /// Taille du logo imprimé : 0 petit, 1 moyen, 2 grand.
  int logoSize = 0;

  /// Affiche la vente en cours sur le petit écran client du terminal (si disponible).
  bool customerDisplay = true;

  bool get hasPrinter => printerMac != null && printerMac!.isNotEmpty;

  AppSettings clone() => AppSettings()
    ..shopName = shopName
    ..address = address
    ..phone1 = phone1
    ..phone2 = phone2
    ..footer = footer
    ..logoB64 = logoB64
    ..colorValue = colorValue
    ..themeMode = themeMode
    ..printerMac = printerMac
    ..printerName = printerName
    ..cols = cols
    ..stripAccents = stripAccents
    ..printLogo = printLogo
    ..autoPrint = autoPrint
    ..stockEnabled = stockEnabled
    ..logoSize = logoSize
    ..customerDisplay = customerDisplay;

  List<String> get phones => [phone1, phone2].where((p) => p.trim().isNotEmpty).toList();
}
