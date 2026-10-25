import 'package:flutter/material.dart';

import '../app_state.dart';
import '../db.dart';
import '../format.dart';
import '../models.dart';
import '../receipts.dart';
import '../ui.dart';
import 'clients_screen.dart';
import 'scan_screen.dart';

/// Écran de vente rapide : produits à gauche, panier à droite (tablette) ou en page séparée (téléphone).
class SaleScreen extends StatefulWidget {
  const SaleScreen({super.key});

  @override
  State<SaleScreen> createState() => _SaleScreenState();
}

class _SaleScreenState extends State<SaleScreen> {
  List<Product> _products = [];
  List<String> _cats = [];
  List<int> _top = [];
  String _q = '';
  String _cat = ''; // '' = tout, '*' = populaires, sinon un rayon
  final _search = TextEditingController();
  final Cart cart = AppState.i.cart;

  @override
  void initState() {
    super.initState();
    AppState.i.dataVersion.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    AppState.i.dataVersion.removeListener(_load);
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final db = await Db.instance;
    final l = await db.listProducts();
    final cats = await db.listCategories();
    final top = await db.topProductIds();
    if (!mounted) return;
    setState(() {
      _products = l;
      _cats = cats;
      _top = top;
      if (_cat.isNotEmpty && _cat != '*' && !cats.contains(_cat)) _cat = '';
    });
  }

  Future<void> _scanProduct() async {
    final code = await Navigator.of(context)
        .push<String>(MaterialPageRoute(builder: (_) => const ScanScreen(title: 'Scanner un produit')));
    if (code == null || !mounted) return;
    final db = await Db.instance;
    final p = await db.getProductByBarcode(code);
    if (!mounted) return;
    if (p == null) {
      toast(context, 'Aucun produit avec ce code-barres.');
    } else {
      cart.add(p);
      toast(context, '${p.name} ajouté');
    }
  }

  Future<void> _askQty(Product p) async {
    final q = await askQuantity(context, name: p.name, unit: p.unit, unitPrice: p.priceFor(cart.level));
    if (q != null && q > 0) cart.add(p, qty: q);
  }

  /// Produits vendus au poids / au volume : on demande la quantité (250 g, 500 g, 500 F…).
  bool _byWeight(Product p) => ['kg', 'litre', 'l', 'g'].contains(p.unit.trim().toLowerCase());

  Future<void> _freeLine() async {
    final name = TextEditingController();
    final price = TextEditingController();
    final qty = TextEditingController(text: '1');
    final unit = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Article libre'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, autofocus: true, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Désignation')),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(controller: qty, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Quantité'))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: unit, decoration: const InputDecoration(labelText: 'Unité', hintText: 'sac, kg…'))),
            ]),
            const SizedBox(height: 12),
            TextField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Prix unitaire (FCFA)', suffixText: 'F')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Ajouter')),
        ],
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      final pr = parseAmount(price.text) ?? 0;
      final q = parseQty(qty.text) ?? 1;
      if (pr > 0 && q > 0) cart.addFree(name.text.trim(), pr, q, unit.text.trim());
    }
    name.dispose();
    price.dispose();
    qty.dispose();
    unit.dispose();
  }

  void _openCart() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _CartPage()));
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= kWide;
    final q = fold(_q.trim());
    final words = q.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    var shown = _products.where((p) {
      if (words.isEmpty) return true;
      final hay = fold('${p.name} ${p.category}');
      return p.barcode == _q.trim() || words.every(hay.contains);
    }).toList();
    // Hors recherche : rayon choisi, ou « Populaires » dans l'ordre des plus vendus.
    if (q.isEmpty && _cat == '*') {
      shown = [for (final id in _top) ...shown.where((p) => p.id == id)];
    } else if (q.isEmpty && _cat.isNotEmpty) {
      shown = shown.where((p) => p.category == _cat).toList();
    }
    final stockOn = AppState.i.settings.stockEnabled;

    final catalog = Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Chercher un produit (${_products.length})',
                isDense: true,
                suffixIcon: _q.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _search.clear();
                          setState(() => _q = '');
                        },
                      ),
              ),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(tooltip: 'Scanner un code-barres', onPressed: _scanProduct, icon: const Icon(Icons.qr_code_scanner)),
          IconButton.filledTonal(tooltip: 'Article libre', onPressed: _freeLine, icon: const Icon(Icons.edit_note)),
        ]),
      ),
      ListenableBuilder(
        listenable: cart,
        builder: (context, _) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [for (final l in kLevels) ButtonSegment(value: l, label: Text(kLevelLabels[l]!))],
            selected: {cart.level},
            onSelectionChanged: (v) {
              cart.level = v.first;
              cart.changed();
            },
          ),
        ),
      ),
      if (_products.length > 8 && (_cats.isNotEmpty || _top.isNotEmpty))
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            children: [
              for (final c in [('', 'Tous'), if (_top.isNotEmpty) ('*', '⭐ Populaires'), for (final x in _cats) (x, x)])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(c.$2),
                    selected: _cat == c.$1,
                    onSelected: (_) => setState(() => _cat = c.$1),
                  ),
                ),
            ],
          ),
        ),
      Expanded(
        child: _products.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('Aucun produit. Ajoutez vos articles dans l\'onglet Produits,\nou utilisez « Article libre » (crayon) pour vendre tout de suite.', textAlign: TextAlign.center),
                ),
              )
            : shown.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.search_off, size: 40),
                        const SizedBox(height: 8),
                        Text(q.isEmpty ? 'Rien dans ce rayon.' : 'Aucun produit pour « ${_q.trim()} ».', textAlign: TextAlign.center),
                        if (q.isNotEmpty) TextButton.icon(onPressed: _freeLine, icon: const Icon(Icons.edit_note), label: const Text('Vendre comme article libre')),
                      ]),
                    ),
                  )
                : ListenableBuilder(
                listenable: cart,
                builder: (context, _) => GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 220, mainAxisExtent: 102, crossAxisSpacing: 10, mainAxisSpacing: 10),
                  itemCount: shown.length,
                  itemBuilder: (_, i) {
                    final p = shown[i];
                    final inCart = cart.lines.where((l) => l.productId == p.id).fold<double>(0, (s, l) => s + l.qty);
                    return Card(
                      clipBehavior: Clip.antiAlias,
                      color: inCart > 0 ? Theme.of(context).colorScheme.primaryContainer : null,
                      child: InkWell(
                        onTap: () => _byWeight(p) ? _askQty(p) : cart.add(p),
                        onLongPress: () => _askQty(p),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              if (p.icon.isNotEmpty) Padding(padding: const EdgeInsets.only(right: 6), child: Text(p.icon, style: const TextStyle(fontSize: 24))),
                              Expanded(child: Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, height: 1.15))),
                            ]),
                            const Spacer(),
                            Row(children: [
                              Expanded(
                                child: AmountText(fcfa(p.priceFor(cart.level)) + (p.unit.isEmpty ? '' : ' / ${p.unit}'),
                                    align: Alignment.centerLeft, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Theme.of(context).colorScheme.primary)),
                              ),
                              if (inCart > 0) CircleAvatar(radius: 11, child: Text(fmtQty(inCart), style: const TextStyle(fontSize: 11))),
                            ]),
                            if (stockOn && p.trackStock)
                              Text(p.stock <= 0 ? 'Rupture' : 'Stock : ${fmtQty(p.stock)}', style: TextStyle(fontSize: 11, fontWeight: p.low ? FontWeight.bold : null, color: p.low ? Colors.red.shade600 : null)),
                          ]),
                        ),
                      ),
                    );
                  },
                ),
              ),
      ),
    ]);

    if (wide) {
      return Scaffold(
        appBar: AppBar(title: const Text('Nouvelle vente')),
        body: Row(children: [
          Expanded(child: catalog),
          const VerticalDivider(width: 1),
          const SizedBox(width: 400, child: CartPanel()),
        ]),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Nouvelle vente')),
      body: catalog,
      bottomNavigationBar: ListenableBuilder(
        listenable: cart,
        builder: (context, _) => cart.isEmpty
            ? const SizedBox.shrink()
            : SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                    onPressed: _openCart,
                    icon: Badge(label: Text('${cart.lines.length}'), child: const Icon(Icons.shopping_cart)),
                    label: FittedBox(fit: BoxFit.scaleDown, child: Text('Panier · ${fcfa(cart.total)}', style: const TextStyle(fontSize: 17))),
                  ),
                ),
              ),
      ),
    );
  }
}

class _CartPage extends StatelessWidget {
  const _CartPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Panier')),
      body: CartPanel(onDone: () => Navigator.of(context).pop()),
    );
  }
}

/// Panier + encaissement.
class CartPanel extends StatefulWidget {
  const CartPanel({super.key, this.onDone});
  final VoidCallback? onDone;

  @override
  State<CartPanel> createState() => _CartPanelState();
}

class _CartPanelState extends State<CartPanel> {
  final Cart cart = AppState.i.cart;

  Future<void> _pickClient() async {
    final c = await pickClient(context, allowCounter: true);
    if (c == null) return;
    cart.setClient(c.id == 0 ? null : c);
  }

  Future<void> _editLine(int i) async {
    final l = cart.lines[i];
    final price = TextEditingController(text: l.unitPrice.toString());
    var qty = l.qty;
    final r = await showDialog<String>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setS) => AlertDialog(
          title: Text(l.name),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Quantité'),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: () async {
                final q = await askQuantity(context, name: l.name, unit: l.unit, unitPrice: int.tryParse(price.text) ?? l.unitPrice, initial: qty);
                if (q != null && q > 0) setS(() => qty = q);
              },
              icon: const Icon(Icons.edit_outlined),
              label: Text(fmtQtyUnit(qty, l.unit), style: const TextStyle(fontSize: 18)),
            ),
            const SizedBox(height: 12),
            TextField(controller: price, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Prix par ${l.unit.isEmpty ? 'unité' : l.unit} (FCFA)', suffixText: 'F')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, 'del'), child: const Text('Retirer')),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(context, 'ok'), child: const Text('OK')),
          ],
        ),
      ),
    );
    if (r == 'del') {
      cart.removeAt(i);
    } else if (r == 'ok') {
      final p = parseAmount(price.text);
      l.qty = qty;
      if (p != null && p > 0) l.unitPrice = p;
      cart.changed();
    }
    price.dispose();
  }

  Future<void> _discount() async {
    final c = TextEditingController(text: cart.discount > 0 ? cart.discount.toString() : '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remise'),
        content: TextField(controller: c, autofocus: true, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Montant de la remise (FCFA)', suffixText: 'F')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('OK')),
        ],
      ),
    );
    if (ok == true) cart.setDiscount(parseAmount(c.text) ?? 0);
    c.dispose();
  }

  Future<void> _checkout() async {
    final res = await showDialog<_CheckoutResult>(context: context, builder: (_) => _CheckoutDialog(cart: cart));
    if (res == null || !mounted) return;
    final db = await Db.instance;
    final settings = AppState.i.settings;
    try {
      final id = await db.createSale(
        clientId: cart.client?.id,
        clientName: cart.client?.fullName ?? '',
        lines: List.of(cart.lines),
        discount: cart.discount,
        paid: res.paid,
        method: res.method,
      );
      cart.clear();
      AppState.i.touch();
      final sale = await db.getSale(id);
      if (!mounted || sale == null) return;
      var printed = false;
      if (settings.autoPrint && settings.hasPrinter) {
        printed = await printTicket(context, saleReceipt(settings, sale));
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dc) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: Colors.green, size: 40),
          title: Text('Facture ${sale.number}'),
          content: Text(sale.due > 0 ? 'Enregistrée. Reste à payer : ${fcfa(sale.due)}' : 'Vente payée et enregistrée.', textAlign: TextAlign.center),
          actions: [
            TextButton(
              onPressed: () async {
                await printTicket(dc, saleReceipt(settings, sale, duplicate: printed));
              },
              child: Text(printed ? 'Réimprimer' : 'Imprimer'),
            ),
            FilledButton(onPressed: () => Navigator.pop(dc), child: const Text('OK')),
          ],
        ),
      );
      if (mounted) widget.onDone?.call();
    } catch (e) {
      if (mounted) toast(context, 'Erreur : $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: cart,
      builder: (context, _) => Column(children: [
        ListTile(
          leading: const Icon(Icons.person_outline),
          title: Text(cart.client?.fullName ?? 'Client comptoir'),
          subtitle: Text(cart.client == null ? 'Paiement comptant' : (cart.client!.balance > 0 ? 'Doit déjà ${fcfa(cart.client!.balance)}' : 'Crédit possible')),
          trailing: const Icon(Icons.swap_horiz),
          onTap: _pickClient,
        ),
        const Divider(height: 1),
        Expanded(
          child: cart.isEmpty
              ? const Center(child: Text('Panier vide.\nTouchez un produit pour l\'ajouter.', textAlign: TextAlign.center))
              : ListView.separated(
                  itemCount: cart.lines.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final l = cart.lines[i];
                    return ListTile(
                      title: Text(l.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text(qtyLine(l.qty, l.unit, l.unitPrice)),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () {
                            if (l.qty > 1) {
                              l.qty -= 1;
                              cart.changed();
                            } else {
                              cart.removeAt(i);
                            }
                          },
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () {
                            l.qty += 1;
                            cart.changed();
                          },
                        ),
                        ConstrainedBox(constraints: const BoxConstraints(maxWidth: 96), child: AmountText(fcfa(l.total), style: const TextStyle(fontWeight: FontWeight.bold))),
                      ]),
                      onTap: () => _editLine(i),
                    );
                  },
                ),
        ),
        Container(
          color: cs.surfaceContainer,
          padding: const EdgeInsets.all(16),
          child: SafeArea(
            top: false,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (!cart.isEmpty)
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  TextButton.icon(onPressed: _discount, icon: const Icon(Icons.sell_outlined), label: Text(cart.discount > 0 ? 'Remise ${fcfa(cart.discount)}' : 'Remise')),
                  TextButton(onPressed: () => cart.clear(), child: const Text('Vider')),
                ]),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('TOTAL', style: Theme.of(context).textTheme.titleMedium),
                Flexible(child: AmountText(fcfa(cart.total), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold))),
              ]),
              const SizedBox(height: 12),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                onPressed: cart.isEmpty ? null : _checkout,
                child: const Text('Encaisser', style: TextStyle(fontSize: 18)),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _CheckoutResult {
  _CheckoutResult(this.paid, this.method);
  final int paid;
  final String method;
}

class _CheckoutDialog extends StatefulWidget {
  const _CheckoutDialog({required this.cart});
  final Cart cart;

  @override
  State<_CheckoutDialog> createState() => _CheckoutDialogState();
}

class _CheckoutDialogState extends State<_CheckoutDialog> {
  late final _c = TextEditingController(text: widget.cart.total.toString());
  String _method = 'cash';

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.cart.total;
    final received = parseAmount(_c.text) ?? 0;
    final counter = widget.cart.client == null;
    final paid = received > total ? total : received;
    final rest = total - paid;
    final change = received - total;
    final canSave = counter ? received >= total : true;

    return AlertDialog(
      title: Text('Encaisser ${fcfa(total)}'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(counter ? 'Client comptoir : paiement complet obligatoire.' : widget.cart.client!.fullName),
          const SizedBox(height: 12),
          TextField(
            controller: _c,
            autofocus: true,
            keyboardType: TextInputType.number,
            style: Theme.of(context).textTheme.headlineSmall,
            decoration: const InputDecoration(labelText: 'Montant reçu (FCFA)', suffixText: 'F'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            ActionChip(label: const Text('Exact'), onPressed: () => setState(() => _c.text = total.toString())),
            if (!counter) ActionChip(label: const Text('Tout à crédit'), onPressed: () => setState(() => _c.text = '0')),
            for (final step in const [500, 1000, 5000, 10000])
              if (step >= total ~/ 4 || total < 500) ActionChip(label: Text(fcfa(step)), onPressed: () => setState(() => _c.text = (((total + step - 1) ~/ step) * step).toString())),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            for (final m in kMethods) ChoiceChip(label: Text(methodLabel(m)), selected: _method == m, onSelected: (_) => setState(() => _method = m)),
          ]),
          const SizedBox(height: 12),
          if (change > 0) Text('À rendre : ${fcfa(change)}', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade700, fontSize: 18)),
          if (rest > 0)
            Text(counter ? 'Il manque ${fcfa(rest)}' : 'Reste à crédit : ${fcfa(rest)}',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red.shade600, fontSize: 18)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(onPressed: canSave ? () => Navigator.pop(context, _CheckoutResult(paid, _method)) : null, child: const Text('Valider')),
      ],
    );
  }
}
