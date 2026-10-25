import 'dart:convert';
import 'dart:io';

import 'package:ardoise/db.dart';
import 'package:ardoise/escpos.dart';
import 'package:ardoise/format.dart';
import 'package:ardoise/activation.dart';
import 'package:ardoise/models.dart';
import 'package:ardoise/period.dart';
import 'package:ardoise/product_icons.dart';
import 'package:ardoise/raster.dart';
import 'package:ardoise/receipts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

String asText(List<int> b) => String.fromCharCodes(b.where((x) => x >= 0x20 || x == 0x0A));

void main() {
  group('format et modèles', () {
    test('fcfa', () {
      expect(fcfa(1250000, forPrint: true), '1 250 000 F');
      expect(fcfa(-500, forPrint: true), '-500 F');
      expect(parseAmount('150 000'), 150000);
      expect(parseAmount('abc'), isNull);
    });

    test('chiffres en lettres et recherche sans accents', () {
      expect(amountInWords(1), 'un franc CFA');
      expect(amountInWords(21), 'vingt et un francs CFA');
      expect(amountInWords(80), 'quatre-vingts francs CFA');
      expect(amountInWords(85000), 'quatre-vingt-cinq mille francs CFA');
      expect(amountInWords(100000), 'cent mille francs CFA');
      expect(amountInWords(1250000), 'un million deux cent cinquante mille francs CFA');
      expect(amountInWords(371), 'trois cent soixante et onze francs CFA');
      expect(fold('Riz BRISÉ'), 'riz brise');
    });

    test('quantités', () {
      expect(fmtQty(2), '2');
      expect(fmtQty(2.5), '2,5');
      expect(parseQty('2,5'), 2.5);
      expect(parseQty(''), isNull);
    });

    test('prix par niveau avec repli sur le détail', () {
      final p = Product(name: 'Riz', priceRetail: 1000, priceWholesale: 800);
      expect(p.priceFor('detail'), 1000);
      expect(p.priceFor('semi'), 1000);
      expect(p.priceFor('gros'), 800);
    });

    test('lecture des QR', () {
      expect(ScanTarget.parse('ARD:F:12')!.id, 12);
      expect(ScanTarget.parse('ARD:C:3')!.kind, 'C');
      expect(ScanTarget.parse('F-000123')!.id, 123);
      expect(ScanTarget.parse('45')!.kind, 'F');
      expect(ScanTarget.parse('bonjour'), isNull);
      expect(saleQr(7), 'ARD:F:7');
      expect(saleNumber(7), 'F-000007');
    });
  });

  group('quantités au poids et icônes', () {
    test('grammes et millilitres', () {
      expect(fmtQtyUnit(0.5, 'kg'), '500 g');
      expect(fmtQtyUnit(0.25, 'kg'), '250 g');
      expect(fmtQtyUnit(1.5, 'kg'), '1,5 kg');
      expect(fmtQtyUnit(0.75, 'litre'), '750 ml');
      expect(fmtQtyUnit(2, 'sac'), '2 sac');
      expect(qtyLine(0.5, 'kg', 2500, forPrint: true), '500 g x 2 500 F/kg');
      expect(qtyLine(10, 'sac', 15000, forPrint: true), '10 sac x 15 000 F');
      // 500 F de sucre à 800 F le kg -> 0,625 kg
      expect((500 / 800 * 800).round(), 500);
    });

    test('icône suggérée d\'après le nom', () {
      expect(suggestIcon('Riz brisé 50 kg'), '🍚');
      expect(suggestIcon('Pain de singe'), '🌳');
      expect(suggestIcon('Petit pois'), '🫘');
      expect(suggestIcon('Truc inconnu'), '');
    });
  });

  group('période et activation', () {
    test('périodes', () {
      final now = DateTime(2026, 10, 20, 15);
      final today = Period.of(PeriodKind.today, now: now);
      expect(today.start, DateTime(2026, 10, 20));
      expect(today.end, DateTime(2026, 10, 21));
      expect(Period.of(PeriodKind.yesterday, now: now).start, DateTime(2026, 10, 19));
      final m = Period.of(PeriodKind.month, now: now);
      expect(m.start, DateTime(2026, 10, 1));
      expect(m.end, DateTime(2026, 11, 1));
      expect(Period.of(PeriodKind.lastMonth, now: now).start, DateTime(2026, 9, 1));
      expect(Period.of(PeriodKind.year, now: DateTime(2026, 12, 31)).end, DateTime(2027, 1, 1));
      expect(Period.of(PeriodKind.week, now: now).start, DateTime(2026, 10, 14));
      final c = Period.of(PeriodKind.custom, from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 15));
      expect(c.end, DateTime(2026, 10, 16));
      expect(c.label, '01/10 – 15/10/2026');
    });

    test('code d\'activation', () {
      expect(checkActivationCode('DEMO-2026'), isTrue);
      expect(checkActivationCode(' DEMO-2026 '), isTrue);
      expect(checkActivationCode('demo-2026'), isFalse);
      expect(checkActivationCode(''), isFalse);
    });
  });

  group('escpos et raster', () {
    test('accents et colonnes', () {
      final e = EscPos(cols: 48);
      expect(e.encode('é è à ç ô'), [0xE9, 0x20, 0xE8, 0x20, 0xE0, 0x20, 0xE7, 0x20, 0xF4]);
      expect(String.fromCharCodes(EscPos(stripAccents: true).encode('Éléphant œuf')), 'Elephant oeuf');
    });

    test('QR : image carrée, centrée sur la largeur du papier', () {
      final r = Raster.qr('ARD:F:123');
      expect(r.width - r.height, inInclusiveRange(0, 7)); // largeur arrondie à l'octet
      expect(r.data.any((b) => b != 0), isTrue);
      final e = EscPos(cols: 48)..raster(r);
      expect(e.paperDots, 576);
      final b = e.bytes;
      var i = -1;
      for (var k = 0; k < b.length - 3; k++) {
        if (b[k] == 0x1D && b[k + 1] == 0x76 && b[k + 2] == 0x30 && b[k + 3] == 0x00) {
          i = k;
          break;
        }
      }
      expect(i, greaterThan(0));
      expect(b[i + 4], 576 ~/ 8); // xL : largeur du papier en octets
      expect(b[i + 5], 0);
    });

    test('logo : rogné et limité à la taille demandée', () {
      final im = img.Image(width: 600, height: 400);
      img.fill(im, color: img.ColorRgb8(255, 255, 255));
      img.fillRect(im, x1: 200, y1: 100, x2: 399, y2: 299, color: img.ColorRgb8(0, 0, 0));
      final b64 = prepareLogo(img.encodePng(im) as dynamic)!;
      final r = Raster.logo(b64, maxDots: 140, maxHeight: 70)!;
      expect(r.height, lessThanOrEqualTo(70));
      expect(r.width, lessThanOrEqualTo(144));
    });

    test('logo : PNG -> trame', () {
      final im = img.Image(width: 100, height: 40);
      img.fill(im, color: img.ColorRgb8(0, 0, 0));
      final b64 = prepareLogo(img.encodePng(im) as dynamic)!;
      final r = Raster.logo(b64)!;
      expect(r.height, 40);
      expect(r.data.every((b) => b == 0xFF || b == 0xF0 || b == 0xE0 || b == 0xC0 || b == 0x80 || b == 0xFC || b == 0xF8 || b == 0xFE || b == 0), isTrue);
      expect(Raster.logo(base64Encode([1, 2, 3])), isNull);
    });
  });

  group('base de données', () {
    late Db db;
    late Database raw;

    setUpAll(() => sqfliteFfiInit());

    setUp(() async {
      raw = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 3,
          onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
          onCreate: (d, v) => Db.createSchema(d),
        ),
      );
      db = Db.forDatabase(raw);
    });

    tearDown(() => raw.close());

    CartLine line(Product p, double q, [String level = 'detail']) => CartLine(
        productId: p.id, name: p.name, unit: p.unit, qty: q, unitPrice: p.priceFor(level), level: level);

    test('vente comptoir : décrémente le stock, exige le paiement complet', () async {
      final id = await db.saveProduct(Product(name: 'Riz', unit: 'sac', priceRetail: 1000, priceWholesale: 800, trackStock: true, stock: 100, minStock: 10));
      final p = (await db.getProduct(id))!;
      expect(
        () => db.createSale(lines: [line(p, 2)], paid: 1000),
        throwsArgumentError,
      );
      final sid = await db.createSale(lines: [line(p, 2.5, 'gros')], paid: 5000);
      final s = (await db.getSale(sid))!;
      expect(s.total, 2000);
      expect(s.due, 0);
      expect(s.settled, isTrue);
      expect(s.displayClient, 'Client comptoir');
      expect((await db.getProduct(id))!.stock, 97.5);
    });

    test('paiement par tranches et solde client', () async {
      final c = await db.addClient(firstName: 'Awa', lastName: 'Ndiaye', phone: '77 111 22 33');
      final sid = await db.createSale(
        clientId: c,
        clientName: 'Awa Ndiaye',
        lines: [CartLine(name: 'Riz', unit: 'sac', qty: 10, unitPrice: 15000, level: 'gros')],
        paid: 50000,
      );
      expect((await db.getClient(c))!.balance, 100000);
      await db.addPayment(sid, 40000, 'wave');
      expect((await db.getClient(c))!.balance, 60000);
      expect(() => db.addPayment(sid, 70000, 'cash'), throwsArgumentError);
      await db.addPayment(sid, 60000, 'cash');
      final s = (await db.getSale(sid))!;
      expect(s.settled, isTrue);
      expect(s.payments.length, 3);
      expect((await db.getClient(c))!.balance, 0);
    });

    test('paiement libre réparti sur les plus anciennes dettes', () async {
      final c = await db.addClient(firstName: 'Moussa');
      final l = [CartLine(name: 'X', unit: 'kg', qty: 1, unitPrice: 10000, level: 'detail')];
      final a = await db.createSale(clientId: c, lines: l);
      final b = await db.createSale(clientId: c, lines: l);
      final parts = await db.payClientDebt(c, 15000, 'cash');
      expect(parts.map((e) => (e.key, e.value)), [(a, 10000), (b, 5000)]);
      expect((await db.getSale(a))!.due, 0);
      expect((await db.getSale(b))!.due, 5000);
      expect(() => db.payClientDebt(c, 6000, 'cash'), throwsArgumentError);
    });

    test('remboursement : annule, rend l\'argent, remet le stock', () async {
      final id = await db.saveProduct(Product(name: 'Sucre', unit: 'carton', priceRetail: 5000, trackStock: true, stock: 10));
      final p = (await db.getProduct(id))!;
      final c = await db.addClient(firstName: 'Fatou');
      final sid = await db.createSale(clientId: c, lines: [line(p, 4)], paid: 8000);
      expect((await db.getProduct(id))!.stock, 6);
      expect((await db.getClient(c))!.balance, 12000);
      final back = await db.refundSale(sid);
      expect(back, 8000);
      final s = (await db.getSale(sid))!;
      expect(s.refunded, isTrue);
      expect(s.paid, 0);
      expect(s.due, 0);
      expect((await db.getProduct(id))!.stock, 10);
      expect((await db.getClient(c))!.balance, 0);
      expect(() => db.refundSale(sid), throwsArgumentError);
    });

    test('suppression client : refusée avec dette, ventes conservées sinon', () async {
      final c = await db.addClient(firstName: 'Ibra');
      final sid = await db.createSale(clientId: c, clientName: 'Ibra', lines: [CartLine(name: 'X', unit: '', qty: 1, unitPrice: 1000, level: 'detail')]);
      expect(await db.deleteClient(c), isFalse);
      await db.addPayment(sid, 1000, 'cash');
      expect(await db.deleteClient(c), isTrue);
      final s = (await db.getSale(sid))!;
      expect(s.clientId, isNull);
      expect(s.clientName, 'Ibra');
    });

    test('récapitulatif de la journée', () async {
      final c = await db.addClient(firstName: 'Awa');
      final l = [CartLine(name: 'X', unit: 'kg', qty: 1, unitPrice: 10000, level: 'detail')];
      await db.createSale(lines: l, paid: 10000, method: 'wave');
      await db.createSale(clientId: c, lines: l, paid: 4000);
      final d = await db.daySummary(DateTime.now());
      expect(d.salesCount, 2);
      expect(d.salesTotal, 20000);
      expect(d.collected['wave'], 10000);
      expect(d.collected['cash'], 4000);
      expect(d.creditGranted, 6000);
      expect(d.net, 14000);
      final debt = await db.debtOverview();
      expect(debt.total, 6000);
      expect(debt.debtors, 1);
    });

    test('journal de synchronisation et restauration', () async {
      expect(await db.pendingCount(), 0);
      final pid = await db.saveProduct(Product(name: 'Riz', unit: 'kg', priceRetail: 800, icon: '🍚', trackStock: true, stock: 50));
      final cid = await db.addClient(firstName: 'Awa');
      final sid = await db.createSale(
        clientId: cid,
        clientName: 'Awa',
        lines: [CartLine(productId: pid, name: 'Riz', unit: 'kg', qty: 0.5, unitPrice: 800, level: 'detail')],
        paid: 100,
      );
      expect(await db.pendingCount(), greaterThan(4));
      var batch = await db.nextSyncBatch();
      expect(batch.records.map((r) => r['tbl']).toSet(), containsAll(['products', 'clients', 'sales', 'sale_items', 'payments', 'stock_moves']));
      final prod = batch.records.firstWhere((r) => r['tbl'] == 'products');
      expect((prod['data'] as Map)['icon'], '🍚');
      expect((prod['data'] as Map)['stock'], 49.5); // dernier état de la ligne
      final snapshot = batch.records.where((r) => r['deleted'] != true).toList();
      await db.ackSync(batch.maxLogId);
      expect(await db.pendingCount(), 0);

      // une modification ne renvoie que la ligne touchée
      await db.addPayment(sid, 300, 'wave');
      batch = await db.nextSyncBatch();
      expect(batch.records.map((r) => r['tbl']).toSet(), {'payments'});
      await db.ackSync(batch.maxLogId);

      // restauration sur une base neuve
      expect(await db.isLocalEmpty(), isFalse);
      final file = '${Directory.systemTemp.path}/gf_restore_${DateTime.now().microsecondsSinceEpoch}.db';
      final raw2 = await databaseFactoryFfi.openDatabase(
        file,
        options: OpenDatabaseOptions(version: 3, onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'), onCreate: (d, v) => Db.createSchema(d)),
      );
      final db2 = Db.forDatabase(raw2);
      expect(await db2.isLocalEmpty(), isTrue);
      await db2.restoreRecords(snapshot, {'shop_name': 'Chez Fall'});
      expect(await db2.pendingCount(), 0);
      expect((await db2.getProduct(pid))!.icon, '🍚');
      expect((await db2.getSale(sid))!.items.single.qty, 0.5);
      expect((await db2.getClient(cid))!.firstName, 'Awa');
      expect((await db2.loadSettings()).shopName, 'Chez Fall');
      await raw2.close();
      await File(file).delete();
    });

    test('collapseLog garde la dernière opération', () {
      final m = Db.collapseLog([
        {'id': 1, 'tbl': 'clients', 'row_id': 1, 'op': 'u'},
        {'id': 2, 'tbl': 'clients', 'row_id': 1, 'op': 'd'},
        {'id': 3, 'tbl': 'sales', 'row_id': 5, 'op': 'u'},
      ]);
      expect(m[('clients', 1)], 'd');
      expect(m[('sales', 5)], 'u');
    });

    test('stock bas, code-barres, réglages', () async {
      await db.saveProduct(Product(name: 'Huile', unit: 'bidon', priceRetail: 3000, barcode: '6001', trackStock: true, stock: 3, minStock: 5));
      expect(await db.lowStockCount(), 1);
      expect((await db.getProductByBarcode('6001'))!.name, 'Huile');
      expect(await db.getProductByBarcode('zzz'), isNull);

      final s = await db.loadSettings();
      expect(s.shopName, 'MA BOUTIQUE');
      s
        ..shopName = 'Chez Fall'
        ..address = 'Marché Sandaga'
        ..phone1 = '77 000 00 00'
        ..phone2 = '78 000 00 00'
        ..colorValue = 0xFF1565C0
        ..themeMode = 'dark'
        ..logoB64 = 'abc'
        ..stockEnabled = false;
      await db.saveSettings(s);
      final r = await db.loadSettings();
      expect(r.shopName, 'Chez Fall');
      expect(r.address, 'Marché Sandaga');
      expect(r.phones, ['77 000 00 00', '78 000 00 00']);
      expect(r.colorValue, 0xFF1565C0);
      expect(r.themeMode, 'dark');
      expect(r.logoB64, 'abc');
      expect(r.stockEnabled, isFalse);
    });

    test('tickets : infos boutique, QR, reste à payer', () async {
      final settings = AppSettings()
        ..shopName = 'Chez Fall'
        ..address = 'Marché Sandaga'
        ..phone1 = '77 000 00 00';
      final c = await db.addClient(firstName: 'Awa', lastName: 'Ndiaye');
      final sid = await db.createSale(
        clientId: c,
        clientName: 'Awa Ndiaye',
        lines: [CartLine(name: 'Riz brisé', unit: 'sac', qty: 10, unitPrice: 15000, level: 'gros')],
        paid: 50000,
      );
      final sale = (await db.getSale(sid))!;
      final t = asText(saleReceipt(settings, sale));
      expect(t, contains('CHEZ FALL'));
      expect(t, contains('Marché Sandaga'.replaceAll('é', 'é')));
      expect(t, contains('Tel : 77 000 00 00'));
      expect(t, contains('FACTURE F-000001'));
      expect(t, contains('10 sac x 15 000 F'));
      expect(t, contains('RESTE A PAYER'));
      expect(t, contains('100 000 F'));
      expect(t, contains('Signature du client'));
      expect(t, contains('mille francs CFA'));
      expect(saleReceipt(settings, sale).length, greaterThan(300)); // contient le QR en points

      final p = asText(paymentReceipt(settings, clientName: 'Awa Ndiaye', parts: [MapEntry(sid, 30000)], method: 'wave', remaining: 70000, remainingOnSale: 70000, clientId: c));
      expect(p, contains('RECU DE PAIEMENT'));
      expect(p, contains('Wave'));
      expect(p, contains('70 000 F'));

      final day = await db.daySummary(DateTime.now());
      expect(asText(closingReceipt(settings, 'Aujourd\'hui', day, 100000)), contains('CLOTURE DE CAISSE'));
      expect(asText(statementReceipt(settings, (await db.getClient(c))!, [sale])), contains('TOTAL A PAYER'));
      expect(asText(testReceipt(settings)), contains('TEST IMPRIMANTE'));
    });
  });
}
