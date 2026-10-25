import 'escpos.dart';
import 'format.dart';
import 'models.dart';
import 'raster.dart';

EscPos _start(AppSettings s) => EscPos(cols: s.cols, stripAccents: s.stripAccents);

/// En-tête commun : logo, nom, adresse, téléphones.
void _header(EscPos e, AppSettings s) {
  if (s.printLogo && s.logoB64 != null) {
    // Petit par défaut : le logo ne doit pas manger le papier.
    const sizes = [(140, 70), (220, 110), (320, 160)];
    final (w, h) = sizes[s.logoSize.clamp(0, 2)];
    final k = e.paperDots >= 576 ? 1.0 : 0.7;
    final r = Raster.logo(s.logoB64!, maxDots: (w * k).round(), maxHeight: (h * k).round());
    if (r != null) e.raster(r);
  }
  e.text(s.shopName.toUpperCase(), align: Align.center, bold: true, big: true);
  if (s.address.trim().isNotEmpty) e.text(s.address.trim(), align: Align.center);
  final phones = s.phones;
  if (phones.isNotEmpty) e.text('Tel : ${phones.join(' / ')}', align: Align.center);
}

void _qr(EscPos e, String data, String caption) {
  e.feed();
  e.raster(Raster.qr(data));
  e.text(caption, align: Align.center);
}

void _end(EscPos e, AppSettings s) {
  if (s.footer.trim().isNotEmpty) {
    e.feed();
    e.text(s.footer.trim(), align: Align.center);
  }
  e.feed(4);
}

String _m(int v) => fcfa(v, forPrint: true);

/// Facture / ticket de vente. Avec un reste à payer : reconnaissance de dette à signer.
List<int> saleReceipt(AppSettings s, Sale sale, {bool duplicate = false}) {
  final e = _start(s);
  _header(e, s);
  e.feed();
  e.banner('FACTURE ${sale.number}${duplicate ? '  (DUPLICATA)' : ''}', sub: fmtDateTime(sale.createdAt));
  e.text('Client : ${sale.displayClient}', bold: true);
  e.line();
  e.row('ARTICLES', 'MONTANT', bold: true);
  e.line();
  for (final it in sale.items) {
    e.text(it.name, bold: true);
    e.row('  ${qtyLine(it.qty, it.unit, it.unitPrice, forPrint: true)}', _m(it.total));
  }
  e.line();
  final count = sale.items.length;
  e.row('Nombre d\'articles', '$count');
  if (sale.discount > 0) {
    e.row('Sous-total', _m(sale.subtotal));
    e.row('Remise', '-${_m(sale.discount)}');
  }
  e.line('=');
  e.rowTall('TOTAL', _m(sale.total));
  e.line('=');
  final pays = sale.payments.where((p) => !p.isRefund).toList();
  if (pays.isNotEmpty) {
    e.text('Reglements', bold: true);
    for (final p in pays) {
      e.row('  ${fmtShort(p.createdAt)}  ${methodLabel(p.method)}', _m(p.amount));
    }
  }
  final refunded = sale.payments.where((p) => p.isRefund).fold<int>(0, (a, p) => a - p.amount);
  if (sale.refunded) {
    e.feed();
    e.banner('VENTE ANNULEE', sub: 'Rembourse : ${_m(refunded)}');
  } else if (sale.due > 0) {
    e.line();
    e.rowTall('RESTE A PAYER', _m(sale.due));
    e.feed();
    e.text('Je reconnais devoir la somme de ${_m(sale.due)} (${amountInWords(sale.due)}) a ${s.shopName}.');
    e.feed(2);
    e.text('Signature du client :');
    e.feed(3);
  } else {
    e.feed();
    e.text('*** PAYE - MERCI ***', align: Align.center, bold: true);
    e.feed();
    e.text('Arretee a la somme de ${amountInWords(sale.total)}.', align: Align.center);
  }
  _qr(e, sale.qrData, sale.number);
  e.text('Scannez pour retrouver cette facture', align: Align.center);
  _end(e, s);
  return e.bytes;
}

/// Reçu d'un paiement par tranche. [parts] = (numéro de facture, montant imputé).
List<int> paymentReceipt(
  AppSettings s, {
  required String clientName,
  required List<MapEntry<int, int>> parts,
  required String method,
  required int remaining,
  int? clientId,
  int? remainingOnSale,
}) {
  final e = _start(s);
  _header(e, s);
  e.feed();
  e.banner('RECU DE PAIEMENT', sub: fmtDateTime(DateTime.now().millisecondsSinceEpoch));
  e.text('Client : $clientName');
  e.line();
  var total = 0;
  for (final p in parts) {
    e.row('Facture ${saleNumber(p.key)}', _m(p.value));
    total += p.value;
  }
  e.line();
  e.rowTall('MONTANT RECU', _m(total));
  e.row('Mode', methodLabel(method));
  if (remainingOnSale != null) e.row('Reste sur la facture', _m(remainingOnSale));
  e.row(parts.length > 1 || remainingOnSale == null ? 'RESTE A PAYER (total)' : 'Reste a payer (total)',
      _m(remaining),
      bold: true);
  if (parts.length == 1) {
    _qr(e, saleQr(parts.first.key), saleNumber(parts.first.key));
  } else if (clientId != null) {
    _qr(e, clientQr(clientId), clientName);
  }
  _end(e, s);
  return e.bytes;
}

List<int> refundReceipt(AppSettings s, Sale sale, int amount) {
  final e = _start(s);
  _header(e, s);
  e.feed();
  e.banner('REMBOURSEMENT', sub: fmtDateTime(DateTime.now().millisecondsSinceEpoch));
  e.text('Facture ${sale.number} du ${fmtDate(sale.createdAt)}');
  e.text('Client : ${sale.displayClient}');
  e.line();
  e.row('MONTANT REMBOURSE', _m(amount), bold: true);
  e.feed(2);
  e.text('Signature du client :');
  e.feed(3);
  _end(e, s);
  return e.bytes;
}

/// Relevé des factures non soldées d'un client.
List<int> statementReceipt(AppSettings s, Client c, List<Sale> dueSales) {
  final e = _start(s);
  _header(e, s);
  e.feed();
  e.banner('RELEVE DE COMPTE', sub: fmtDateTime(DateTime.now().millisecondsSinceEpoch));
  e.text('Client : ${c.fullName}');
  if (c.phone.isNotEmpty) e.text('Tel : ${c.phone}');
  e.line();
  for (final x in dueSales) {
    e.row('${x.number}  ${fmtDate(x.createdAt)}', _m(x.total));
    if (x.paid > 0) e.row('  deja paye', '-${_m(x.paid)}');
    e.row('  reste', _m(x.due), bold: true);
  }
  e.line();
  e.line('=');
  e.rowTall('TOTAL A PAYER', _m(c.balance));
  _qr(e, clientQr(c.id), c.fullName);
  _end(e, s);
  return e.bytes;
}

/// Clôture de caisse de la journée.
List<int> closingReceipt(AppSettings s, String periodLabel, DaySummary d, int totalDebts) {
  final e = _start(s);
  _header(e, s);
  e.feed();
  e.banner('CLOTURE DE CAISSE', sub: periodLabel);
  e.row('Ventes (${d.salesCount})', _m(d.salesTotal), bold: true);
  e.row('  dont a credit', _m(d.creditGranted));
  e.line();
  e.text('ENCAISSEMENTS', bold: true);
  for (final m in kMethods) {
    e.row('  ${methodLabel(m)}', _m(d.collected[m] ?? 0));
  }
  e.row('  dont dettes payees', _m(d.debtsCollected));
  e.row('Rembourse', '-${_m(d.refunded)}');
  e.line('=');
  e.rowTall('NET ENCAISSE', _m(d.net));
  e.line();
  e.row('Dettes clients (total)', _m(totalDebts));
  _end(e, s);
  return e.bytes;
}

List<int> testReceipt(AppSettings s) {
  final e = _start(s);
  _header(e, s);
  e.line();
  e.text('TEST IMPRIMANTE', align: Align.center, bold: true);
  e.text('Accents : é è à ç ô ê î — œ', align: Align.center);
  e.row('Gauche', 'Droite');
  e.row('Total', _m(1250000), bold: true);
  e.line('=');
  e.text('Largeur : ${s.cols} caractères');
  _qr(e, saleQr(1), 'QR de test');
  _end(e, s);
  return e.bytes;
}
