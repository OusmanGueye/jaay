import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';

/// Base SQLite embarquée : aucun service externe, aucune connexion requise.
class Db {
  Db._(this._db);

  final Database _db;
  static Db? _inst;

  static Future<Db> get instance async => _inst ??= await _open();

  static Future<Db> _open() async {
    final path = p.join(await getDatabasesPath(), 'ardoise.db');
    final db = await openDatabase(
      path,
      version: 4,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, v) => createSchema(db),
      onUpgrade: (db, from, to) async {
        if (from < 2) {
          // La v1 (carnet simple) est remplacée par le modèle ventes/paiements.
          await db.execute('DROP TABLE IF EXISTS transactions');
          await db.execute('DROP TABLE IF EXISTS clients');
          await _createV2Tables(db);
        }
        if (from < 3) {
          if (from >= 2) await db.execute("ALTER TABLE products ADD COLUMN icon TEXT NOT NULL DEFAULT ''");
          await _createSyncObjects(db, backfill: true);
        }
        if (from >= 3 && from < 4) {
          await db.execute("ALTER TABLE products ADD COLUMN category TEXT NOT NULL DEFAULT ''");
          await db.execute("INSERT INTO sync_log(tbl, row_id, op) SELECT 'products', id, 'u' FROM products");
        }
        if (from == 2) {
          await db.execute("ALTER TABLE products ADD COLUMN category TEXT NOT NULL DEFAULT ''");
        }
      },
    );
    return Db._(db);
  }

  /// Utilisé par les tests.
  static Db forDatabase(Database d) => Db._(d);

  static Future<void> createSchema(Database db) async {
    await db.execute('CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)');
    await _createV2Tables(db);
    await _createSyncObjects(db);
  }

  static const syncTables = ['clients', 'products', 'sales', 'sale_items', 'payments', 'stock_moves'];

  /// Journal des modifications : chaque ajout / changement / suppression est noté par
  /// des déclencheurs SQLite, puis envoyé en ligne quand il y a du réseau.
  static Future<void> _createSyncObjects(Database db, {bool backfill = false}) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_log(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tbl TEXT NOT NULL,
        row_id INTEGER NOT NULL,
        op TEXT NOT NULL
      )''');
    for (final t in syncTables) {
      await db.execute('''CREATE TRIGGER IF NOT EXISTS trg_${t}_i AFTER INSERT ON $t
        BEGIN INSERT INTO sync_log(tbl, row_id, op) VALUES('$t', NEW.id, 'u'); END''');
      await db.execute('''CREATE TRIGGER IF NOT EXISTS trg_${t}_u AFTER UPDATE ON $t
        BEGIN INSERT INTO sync_log(tbl, row_id, op) VALUES('$t', NEW.id, 'u'); END''');
      await db.execute('''CREATE TRIGGER IF NOT EXISTS trg_${t}_d AFTER DELETE ON $t
        BEGIN INSERT INTO sync_log(tbl, row_id, op) VALUES('$t', OLD.id, 'd'); END''');
      if (backfill) await db.execute("INSERT INTO sync_log(tbl, row_id, op) SELECT '$t', id, 'u' FROM $t");
    }
  }

  static Future<void> _createV2Tables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)''');
    await db.execute('''
      CREATE TABLE clients(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        first_name TEXT NOT NULL DEFAULT '',
        last_name TEXT NOT NULL DEFAULT '',
        phone TEXT NOT NULL DEFAULT '',
        note TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE products(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        unit TEXT NOT NULL DEFAULT 'pièce',
        price_retail INTEGER NOT NULL DEFAULT 0,
        price_semi INTEGER NOT NULL DEFAULT 0,
        price_wholesale INTEGER NOT NULL DEFAULT 0,
        barcode TEXT NOT NULL DEFAULT '',
        track_stock INTEGER NOT NULL DEFAULT 0,
        stock REAL NOT NULL DEFAULT 0,
        min_stock REAL NOT NULL DEFAULT 0,
        active INTEGER NOT NULL DEFAULT 1,
        icon TEXT NOT NULL DEFAULT '',
        category TEXT NOT NULL DEFAULT ''
      )''');
    await db.execute('''
      CREATE TABLE sales(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        client_id INTEGER REFERENCES clients(id) ON DELETE SET NULL,
        client_name TEXT NOT NULL DEFAULT '',
        subtotal INTEGER NOT NULL,
        discount INTEGER NOT NULL DEFAULT 0,
        total INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'active',
        note TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL
      )''');
    await db.execute('CREATE INDEX idx_sales_client ON sales(client_id)');
    await db.execute('CREATE INDEX idx_sales_date ON sales(created_at)');
    await db.execute('''
      CREATE TABLE sale_items(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id INTEGER NOT NULL REFERENCES sales(id) ON DELETE CASCADE,
        product_id INTEGER,
        name TEXT NOT NULL,
        unit TEXT NOT NULL DEFAULT '',
        qty REAL NOT NULL,
        unit_price INTEGER NOT NULL,
        total INTEGER NOT NULL
      )''');
    await db.execute('CREATE INDEX idx_items_sale ON sale_items(sale_id)');
    await db.execute('''
      CREATE TABLE payments(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id INTEGER NOT NULL REFERENCES sales(id) ON DELETE CASCADE,
        amount INTEGER NOT NULL,
        method TEXT NOT NULL DEFAULT 'cash',
        note TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL
      )''');
    await db.execute('CREATE INDEX idx_pay_sale ON payments(sale_id)');
    await db.execute('CREATE INDEX idx_pay_date ON payments(created_at)');
    await db.execute('''
      CREATE TABLE stock_moves(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
        delta REAL NOT NULL,
        reason TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL
      )''');
  }

  int _now() => DateTime.now().millisecondsSinceEpoch;

  // ---------------------------------------------------------------- réglages

  Future<String?> _get(String key) async {
    final r = await _db.query('settings', where: 'key = ?', whereArgs: [key]);
    return r.isEmpty ? null : r.first['value'] as String;
  }

  Future<AppSettings> loadSettings() async {
    final s = AppSettings();
    s.shopName = await _get('shop_name') ?? s.shopName;
    s.address = await _get('address') ?? '';
    s.phone1 = await _get('phone1') ?? await _get('shop_phone') ?? '';
    s.phone2 = await _get('phone2') ?? '';
    s.footer = await _get('footer') ?? s.footer;
    final logo = await _get('logo');
    s.logoB64 = (logo == null || logo.isEmpty) ? null : logo;
    s.colorValue = int.tryParse(await _get('color') ?? '') ?? s.colorValue;
    s.themeMode = await _get('theme_mode') ?? 'system';
    final mac = await _get('printer_mac');
    s.printerMac = (mac == null || mac.isEmpty) ? null : mac;
    s.printerName = await _get('printer_name') ?? '';
    s.cols = int.tryParse(await _get('cols') ?? '') ?? 48;
    s.stripAccents = (await _get('strip_accents')) == '1';
    s.printLogo = (await _get('print_logo')) != '0';
    s.autoPrint = (await _get('auto_print')) != '0';
    s.stockEnabled = (await _get('stock_enabled')) != '0';
    s.logoSize = int.tryParse(await _get('logo_size') ?? '') ?? 0;
    s.customerDisplay = (await _get('customer_display')) != '0';
    return s;
  }

  Future<void> saveSettings(AppSettings s) async {
    await _db.transaction((txn) async {
      Future<void> set(String k, String v) =>
          txn.insert('settings', {'key': k, 'value': v}, conflictAlgorithm: ConflictAlgorithm.replace);
      await set('shop_name', s.shopName);
      await set('address', s.address);
      await set('phone1', s.phone1);
      await set('phone2', s.phone2);
      await set('footer', s.footer);
      await set('logo', s.logoB64 ?? '');
      await set('color', s.colorValue.toString());
      await set('theme_mode', s.themeMode);
      await set('printer_mac', s.printerMac ?? '');
      await set('printer_name', s.printerName);
      await set('cols', s.cols.toString());
      await set('strip_accents', s.stripAccents ? '1' : '0');
      await set('print_logo', s.printLogo ? '1' : '0');
      await set('auto_print', s.autoPrint ? '1' : '0');
      await set('stock_enabled', s.stockEnabled ? '1' : '0');
      await set('logo_size', s.logoSize.toString());
      await set('customer_display', s.customerDisplay ? '1' : '0');
    });
  }

  Future<bool> isActivated() async => (await _get('activated')) == '1';

  Future<void> setActivated() => _db.insert('settings', {'key': 'activated', 'value': '1'},
      conflictAlgorithm: ConflictAlgorithm.replace);

  // ----------------------------------------------------------------- clients

  static const _paidSub = '(SELECT sale_id, SUM(amount) AS paid FROM payments GROUP BY sale_id)';

  static const _clientSql = '''
    SELECT c.id, c.first_name, c.last_name, c.phone, c.note,
      COALESCE(SUM(CASE WHEN s.status = 'active' THEN s.total - IFNULL(p.paid, 0) ELSE 0 END), 0) AS balance,
      MAX(s.created_at) AS last_at
    FROM clients c
    LEFT JOIN sales s ON s.client_id = c.id
    LEFT JOIN $_paidSub p ON p.sale_id = s.id
  ''';

  Client _client(Map<String, Object?> r) => Client(
        id: r['id'] as int,
        firstName: r['first_name'] as String,
        lastName: r['last_name'] as String,
        phone: r['phone'] as String,
        note: r['note'] as String,
        balance: (r['balance'] as num).toInt(),
        lastAt: r['last_at'] as int?,
      );

  /// Clients triés : ceux qui doivent le plus d'abord.
  Future<List<Client>> listClients() async {
    final rows = await _db.rawQuery('$_clientSql GROUP BY c.id');
    final list = rows.map(_client).toList();
    list.sort((a, b) {
      final c = b.balance.compareTo(a.balance);
      return c != 0 ? c : a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
    });
    return list;
  }

  Future<Client?> getClient(int id) async {
    final rows = await _db.rawQuery('$_clientSql WHERE c.id = ? GROUP BY c.id', [id]);
    return rows.isEmpty ? null : _client(rows.first);
  }

  Future<int> addClient({String firstName = '', String lastName = '', String phone = '', String note = ''}) =>
      _db.insert('clients', {
        'first_name': firstName.trim(),
        'last_name': lastName.trim(),
        'phone': phone.trim(),
        'note': note.trim(),
        'created_at': _now(),
      });

  Future<void> updateClient(int id, {String firstName = '', String lastName = '', String phone = '', String note = ''}) =>
      _db.update(
        'clients',
        {'first_name': firstName.trim(), 'last_name': lastName.trim(), 'phone': phone.trim(), 'note': note.trim()},
        where: 'id = ?',
        whereArgs: [id],
      );

  /// Supprime un client sans dette. Ses ventes passées restent (nom conservé).
  Future<bool> deleteClient(int id) async {
    final c = await getClient(id);
    if (c == null) return true;
    if (c.balance > 0) return false;
    await _db.delete('clients', where: 'id = ?', whereArgs: [id]);
    return true;
  }

  // ---------------------------------------------------------------- produits

  Product _product(Map<String, Object?> r) => Product(
        id: r['id'] as int,
        name: r['name'] as String,
        unit: r['unit'] as String,
        priceRetail: r['price_retail'] as int,
        priceSemi: r['price_semi'] as int,
        priceWholesale: r['price_wholesale'] as int,
        barcode: r['barcode'] as String,
        trackStock: (r['track_stock'] as int) == 1,
        stock: (r['stock'] as num).toDouble(),
        minStock: (r['min_stock'] as num).toDouble(),
        active: (r['active'] as int) == 1,
        icon: (r['icon'] as String?) ?? '',
        category: (r['category'] as String?) ?? '',
      );

  Future<List<Product>> listProducts({bool onlyActive = true}) async {
    final rows = await _db.query(
      'products',
      where: onlyActive ? 'active = 1' : null,
      orderBy: 'name COLLATE NOCASE',
    );
    return rows.map(_product).toList();
  }

  /// Rayons déjà utilisés.
  Future<List<String>> listCategories() async {
    final r = await _db.rawQuery("SELECT DISTINCT category FROM products WHERE active = 1 AND category <> '' ORDER BY category COLLATE NOCASE");
    return [for (final x in r) x['category'] as String];
  }

  /// Produits les plus vendus (par nombre de ventes), pour l'onglet « Populaires ».
  Future<List<int>> topProductIds({int limit = 12}) async {
    final r = await _db.rawQuery(
        'SELECT product_id, COUNT(*) AS n FROM sale_items WHERE product_id IS NOT NULL GROUP BY product_id ORDER BY n DESC, MAX(id) DESC LIMIT ?',
        [limit]);
    return [for (final x in r) x['product_id'] as int];
  }

  Future<Product?> getProduct(int id) async {
    final r = await _db.query('products', where: 'id = ?', whereArgs: [id]);
    return r.isEmpty ? null : _product(r.first);
  }

  Future<Product?> getProductByBarcode(String code) async {
    if (code.trim().isEmpty) return null;
    final r = await _db.query('products',
        where: 'barcode = ? AND active = 1', whereArgs: [code.trim()], limit: 1);
    return r.isEmpty ? null : _product(r.first);
  }

  Future<int> saveProduct(Product pr) async {
    final values = {
      'name': pr.name.trim(),
      'unit': pr.unit.trim().isEmpty ? 'pièce' : pr.unit.trim(),
      'price_retail': pr.priceRetail,
      'price_semi': pr.priceSemi,
      'price_wholesale': pr.priceWholesale,
      'barcode': pr.barcode.trim(),
      'track_stock': pr.trackStock ? 1 : 0,
      'min_stock': pr.minStock,
      'active': pr.active ? 1 : 0,
      'icon': pr.icon,
      'category': pr.category.trim(),
    };
    if (pr.id == 0) {
      final id = await _db.insert('products', {...values, 'stock': pr.stock});
      if (pr.trackStock && pr.stock != 0) {
        await _db.insert('stock_moves',
            {'product_id': id, 'delta': pr.stock, 'reason': 'Stock initial', 'created_at': _now()});
      }
      return id;
    }
    await _db.update('products', values, where: 'id = ?', whereArgs: [pr.id]);
    return pr.id;
  }

  /// Archive un produit (il reste dans les anciennes factures).
  Future<void> archiveProduct(int id) =>
      _db.update('products', {'active': 0}, where: 'id = ?', whereArgs: [id]);

  Future<void> adjustStock(int productId, double delta, String reason) async {
    await _db.transaction((txn) async {
      await txn.rawUpdate('UPDATE products SET stock = stock + ? WHERE id = ?', [delta, productId]);
      await txn.insert('stock_moves',
          {'product_id': productId, 'delta': delta, 'reason': reason, 'created_at': _now()});
    });
  }

  Future<int> lowStockCount() async {
    final r = await _db.rawQuery(
        'SELECT COUNT(*) AS n FROM products WHERE active = 1 AND track_stock = 1 AND stock <= min_stock');
    return (r.first['n'] as int);
  }

  // ------------------------------------------------------------------ ventes

  /// Enregistre une vente, décrémente le stock et note l'éventuel acompte.
  /// Un client comptoir (sans [clientId]) doit payer la totalité.
  Future<int> createSale({
    int? clientId,
    String clientName = '',
    required List<CartLine> lines,
    int discount = 0,
    int paid = 0,
    String method = 'cash',
    String note = '',
  }) async {
    if (lines.isEmpty) throw ArgumentError('Panier vide');
    final subtotal = lines.fold<int>(0, (s, l) => s + l.total);
    final disc = discount.clamp(0, subtotal);
    final total = subtotal - disc;
    final pay = paid.clamp(0, total);
    if (clientId == null && pay < total) {
      throw ArgumentError('Le client comptoir doit payer la totalité.');
    }
    final now = _now();
    return _db.transaction((txn) async {
      final id = await txn.insert('sales', {
        'client_id': clientId,
        'client_name': clientName,
        'subtotal': subtotal,
        'discount': disc,
        'total': total,
        'status': 'active',
        'note': note.trim(),
        'created_at': now,
      });
      for (final l in lines) {
        await txn.insert('sale_items', {
          'sale_id': id,
          'product_id': l.productId,
          'name': l.name,
          'unit': l.unit,
          'qty': l.qty,
          'unit_price': l.unitPrice,
          'total': l.total,
        });
        if (l.productId != null) {
          final rows = await txn.query('products',
              columns: ['track_stock'], where: 'id = ?', whereArgs: [l.productId]);
          if (rows.isNotEmpty && rows.first['track_stock'] == 1) {
            await txn.rawUpdate('UPDATE products SET stock = stock - ? WHERE id = ?', [l.qty, l.productId]);
            await txn.insert('stock_moves', {
              'product_id': l.productId,
              'delta': -l.qty,
              'reason': 'Vente ${saleNumber(id)}',
              'created_at': now,
            });
          }
        }
      }
      if (pay > 0) {
        await txn.insert('payments',
            {'sale_id': id, 'amount': pay, 'method': method, 'note': '', 'created_at': now});
      }
      return id;
    });
  }

  Sale _sale(Map<String, Object?> r, {List<SaleItem> items = const [], List<Payment> payments = const []}) => Sale(
        id: r['id'] as int,
        clientId: r['client_id'] as int?,
        clientName: r['client_name'] as String,
        subtotal: r['subtotal'] as int,
        discount: r['discount'] as int,
        total: r['total'] as int,
        status: r['status'] as String,
        note: r['note'] as String,
        createdAt: r['created_at'] as int,
        paid: ((r['paid'] as num?) ?? 0).toInt(),
        items: items,
        payments: payments,
      );

  static const _saleSql = 'SELECT s.*, IFNULL(p.paid, 0) AS paid FROM sales s LEFT JOIN $_paidSub p ON p.sale_id = s.id';

  Future<Sale?> getSale(int id) async {
    final rows = await _db.rawQuery('$_saleSql WHERE s.id = ?', [id]);
    if (rows.isEmpty) return null;
    final items = (await _db.query('sale_items', where: 'sale_id = ?', whereArgs: [id], orderBy: 'id'))
        .map((r) => SaleItem(
              productId: r['product_id'] as int?,
              name: r['name'] as String,
              unit: r['unit'] as String,
              qty: (r['qty'] as num).toDouble(),
              unitPrice: r['unit_price'] as int,
              total: r['total'] as int,
            ))
        .toList();
    final pays = (await _db.query('payments', where: 'sale_id = ?', whereArgs: [id], orderBy: 'created_at, id'))
        .map(_payment)
        .toList();
    return _sale(rows.first, items: items, payments: pays);
  }

  Payment _payment(Map<String, Object?> r) => Payment(
        id: r['id'] as int,
        saleId: r['sale_id'] as int,
        amount: r['amount'] as int,
        method: r['method'] as String,
        note: r['note'] as String,
        createdAt: r['created_at'] as int,
      );

  /// Liste des ventes, la plus récente d'abord.
  Future<List<Sale>> listSales({int? clientId, bool dueOnly = false, int? from, int? to, int limit = 300}) async {
    final where = <String>[];
    final args = <Object?>[];
    if (clientId != null) {
      where.add('s.client_id = ?');
      args.add(clientId);
    }
    if (from != null) {
      where.add('s.created_at >= ?');
      args.add(from);
    }
    if (to != null) {
      where.add('s.created_at < ?');
      args.add(to);
    }
    if (dueOnly) where.add("s.status = 'active' AND s.total - IFNULL(p.paid, 0) > 0");
    final sql =
        '$_saleSql ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'} ORDER BY s.created_at DESC, s.id DESC LIMIT $limit';
    final rows = await _db.rawQuery(sql, args);
    return rows.map((r) => _sale(r)).toList();
  }

  /// Paiement d'une tranche sur une vente précise.
  Future<int> addPayment(int saleId, int amount, String method, {String note = ''}) async {
    final sale = await getSale(saleId);
    if (sale == null || sale.refunded) throw ArgumentError('Vente introuvable ou remboursée');
    if (amount <= 0 || amount > sale.due) throw ArgumentError('Montant invalide');
    return _db.insert('payments',
        {'sale_id': saleId, 'amount': amount, 'method': method, 'note': note.trim(), 'created_at': _now()});
  }

  /// Paiement libre d'un client : réparti sur ses plus anciennes dettes d'abord.
  /// Retourne les paiements créés (vente, montant).
  Future<List<MapEntry<int, int>>> payClientDebt(int clientId, int amount, String method) async {
    final due = await listSales(clientId: clientId, dueOnly: true, limit: 5000);
    final total = due.fold<int>(0, (s, x) => s + x.due);
    if (amount <= 0 || amount > total) throw ArgumentError('Montant invalide');
    due.sort((a, b) => a.createdAt != b.createdAt ? a.createdAt.compareTo(b.createdAt) : a.id.compareTo(b.id));
    final now = _now();
    final out = <MapEntry<int, int>>[];
    await _db.transaction((txn) async {
      var left = amount;
      for (final s in due) {
        if (left <= 0) break;
        final part = left < s.due ? left : s.due;
        await txn.insert('payments',
            {'sale_id': s.id, 'amount': part, 'method': method, 'note': '', 'created_at': now});
        out.add(MapEntry(s.id, part));
        left -= part;
      }
    });
    return out;
  }

  /// Annule la vente : l'argent déjà encaissé est rendu, le stock est remis.
  /// Retourne le montant remboursé.
  Future<int> refundSale(int saleId, {bool restock = true}) async {
    final sale = await getSale(saleId);
    if (sale == null || sale.refunded) throw ArgumentError('Vente introuvable ou déjà remboursée');
    final now = _now();
    await _db.transaction((txn) async {
      if (sale.paid > 0) {
        await txn.insert('payments', {
          'sale_id': saleId,
          'amount': -sale.paid,
          'method': 'cash',
          'note': 'Remboursement',
          'created_at': now,
        });
      }
      await txn.update('sales', {'status': 'refunded'}, where: 'id = ?', whereArgs: [saleId]);
      if (restock) {
        for (final it in sale.items) {
          if (it.productId == null) continue;
          final rows = await txn.query('products',
              columns: ['track_stock'], where: 'id = ?', whereArgs: [it.productId]);
          if (rows.isNotEmpty && rows.first['track_stock'] == 1) {
            await txn.rawUpdate('UPDATE products SET stock = stock + ? WHERE id = ?', [it.qty, it.productId]);
            await txn.insert('stock_moves', {
              'product_id': it.productId,
              'delta': it.qty,
              'reason': 'Remboursement ${sale.number}',
              'created_at': now,
            });
          }
        }
      }
    });
    return sale.paid;
  }

  // ------------------------------------------------------------- tableau de bord

  /// Total des dettes clients et nombre de débiteurs.
  Future<({int total, int debtors})> debtOverview() async {
    final clients = await listClients();
    final d = clients.where((c) => c.balance > 0);
    return (total: d.fold<int>(0, (s, c) => s + c.balance), debtors: d.length);
  }

  /// Récapitulatif de la journée contenant [day].
  Future<DaySummary> daySummary(DateTime day) => rangeSummary(
        DateTime(day.year, day.month, day.day).millisecondsSinceEpoch,
        DateTime(day.year, day.month, day.day + 1).millisecondsSinceEpoch,
      );

  /// Récapitulatif d'une période [start, end[ (millisecondes).
  Future<DaySummary> rangeSummary(int start, int end) async {
    final sales = await _db.rawQuery(
        "SELECT COUNT(*) AS n, IFNULL(SUM(total), 0) AS t FROM sales WHERE status = 'active' AND created_at >= ? AND created_at < ?",
        [start, end]);

    final byMethod = await _db.rawQuery(
        'SELECT method, SUM(amount) AS t FROM payments WHERE amount > 0 AND created_at >= ? AND created_at < ? GROUP BY method',
        [start, end]);
    final collected = {for (final m in kMethods) m: 0};
    for (final r in byMethod) {
      final m = r['method'] as String;
      collected[m] = (collected[m] ?? 0) + (r['t'] as num).toInt();
    }

    final ref = await _db.rawQuery(
        'SELECT IFNULL(SUM(-amount), 0) AS t FROM payments WHERE amount < 0 AND created_at >= ? AND created_at < ?',
        [start, end]);

    // Part des ventes du jour encaissée le jour même.
    final paidToday = await _db.rawQuery('''
      SELECT IFNULL(SUM(p.amount), 0) AS t FROM payments p JOIN sales s ON s.id = p.sale_id
      WHERE p.amount > 0 AND s.status = 'active' AND s.created_at >= ? AND s.created_at < ?
        AND p.created_at >= ? AND p.created_at < ?''', [start, end, start, end]);

    final salesTotal = (sales.first['t'] as num).toInt();
    final collectedTotal = collected.values.fold<int>(0, (a, b) => a + b);
    final paidOnToday = (paidToday.first['t'] as num).toInt();

    return DaySummary(
      salesCount: sales.first['n'] as int,
      salesTotal: salesTotal,
      collected: collected,
      refunded: (ref.first['t'] as num).toInt(),
      creditGranted: (salesTotal - paidOnToday).clamp(0, salesTotal),
      debtsCollected: (collectedTotal - paidOnToday).clamp(0, collectedTotal),
    );
  }

  // ------------------------------------------------------------ synchronisation

  Future<String?> getSetting(String key) => _get(key);

  Future<void> setSetting(String key, String value) =>
      _db.insert('settings', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> deleteSetting(String key) => _db.delete('settings', where: 'key = ?', whereArgs: [key]);

  /// Nombre d'enregistrements en attente d'envoi.
  Future<int> pendingCount() async {
    final r = await _db.rawQuery('SELECT COUNT(*) AS n FROM (SELECT DISTINCT tbl, row_id FROM sync_log)');
    return (r.first['n'] as int);
  }

  /// Garde la dernière opération de chaque ligne : ajouté / modifié (u) ou supprimé (d).
  static Map<(String, int), String> collapseLog(List<Map<String, Object?>> log) {
    final out = <(String, int), String>{};
    for (final r in log) {
      out[(r['tbl'] as String, r['row_id'] as int)] = r['op'] as String;
    }
    return out;
  }

  /// Prochain lot à envoyer : enregistrements (tbl, id, data, deleted) et dernier n° de journal couvert.
  Future<({List<Map<String, Object?>> records, int maxLogId})> nextSyncBatch({int limit = 300}) async {
    final log = await _db.rawQuery('SELECT id, tbl, row_id, op FROM sync_log ORDER BY id LIMIT ?', [limit]);
    if (log.isEmpty) return (records: <Map<String, Object?>>[], maxLogId: 0);
    final records = <Map<String, Object?>>[];
    for (final e in collapseLog(log).entries) {
      final (tbl, id) = e.key;
      Map<String, Object?>? row;
      if (e.value != 'd' && syncTables.contains(tbl)) {
        final r = await _db.rawQuery('SELECT * FROM $tbl WHERE id = ?', [id]);
        if (r.isNotEmpty) row = Map<String, Object?>.of(r.first);
      }
      records.add({'tbl': tbl, 'id': id, 'data': row, 'deleted': row == null});
    }
    return (records: records, maxLogId: log.last['id'] as int);
  }

  Future<void> ackSync(int maxLogId) => _db.delete('sync_log', where: 'id <= ?', whereArgs: [maxLogId]);

  static const syncSettingKeys = [
    'shop_name', 'address', 'phone1', 'phone2', 'footer', 'logo', 'color', 'theme_mode',
    'print_logo', 'auto_print', 'stock_enabled', 'logo_size', 'customer_display', 'cols', 'strip_accents',
  ];

  Future<Map<String, String>> settingsSnapshot() async {
    final out = <String, String>{};
    for (final k in syncSettingKeys) {
      final v = await _get(k);
      if (v != null) out[k] = v;
    }
    return out;
  }

  /// Vrai si l'appareil n'a encore aucune donnée (on peut alors restaurer une sauvegarde).
  Future<bool> isLocalEmpty() async {
    for (final t in ['clients', 'products', 'sales']) {
      final r = await _db.rawQuery('SELECT COUNT(*) AS n FROM $t');
      if ((r.first['n'] as int) > 0) return false;
    }
    return true;
  }

  /// Recopie une sauvegarde en ligne dans la base locale.
  Future<void> restoreRecords(List<Map<String, Object?>> records, Map<String, String>? settings) async {
    await _db.transaction((txn) async {
      for (final t in syncTables) {
        for (final r in records.where((r) => r['tbl'] == t && r['deleted'] != true && r['data'] is Map)) {
          await txn.insert(t, Map<String, Object?>.from(r['data'] as Map), conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
      if (settings != null) {
        for (final e in settings.entries) {
          if (syncSettingKeys.contains(e.key)) {
            await txn.insert('settings', {'key': e.key, 'value': e.value}, conflictAlgorithm: ConflictAlgorithm.replace);
          }
        }
      }
      await txn.delete('sync_log');
    });
  }
}
