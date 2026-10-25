import 'package:flutter/material.dart';

import '../app_state.dart';
import '../db.dart';
import '../format.dart';
import '../models.dart';
import '../product_icons.dart';
import '../ui.dart';
import 'scan_screen.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  List<Product> _all = [];
  String _q = '';
  String _cat = ''; // '' = tout, '!' = stock bas
  List<String> _cats = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    AppState.i.dataVersion.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    AppState.i.dataVersion.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final db = await Db.instance;
    final l = await db.listProducts();
    final cats = await db.listCategories();
    if (!mounted) return;
    setState(() {
      _all = l;
      _cats = cats;
      if (_cat.isNotEmpty && _cat != '!' && !cats.contains(_cat)) _cat = '';
      _loading = false;
    });
  }

  Future<void> _open([Product? p]) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProductForm(product: p)));
  }

  Future<void> _adjust(Product p) async {
    final c = TextEditingController();
    var sign = 1;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setS) => AlertDialog(
          title: Text('Stock : ${p.name}'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('En stock : ${fmtQty(p.stock)} ${p.unit}'),
            const SizedBox(height: 12),
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [ButtonSegment(value: 1, label: Text('Entrée (+)')), ButtonSegment(value: -1, label: Text('Perte / sortie (−)'))],
              selected: {sign},
              onSelectionChanged: (v) => setS(() => sign = v.first),
            ),
            const SizedBox(height: 12),
            TextField(controller: c, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: 'Quantité (${p.unit})')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Valider')),
          ],
        ),
      ),
    );
    final q = parseQty(c.text);
    c.dispose();
    if (ok == true && q != null && q > 0) {
      final db = await Db.instance;
      await db.adjustStock(p.id, sign * q, sign > 0 ? 'Entrée de stock' : 'Sortie / perte');
      AppState.i.touch();
    }
  }

  @override
  Widget build(BuildContext context) {
    final stockOn = AppState.i.settings.stockEnabled;
    final words = fold(_q.trim()).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final shown = _all.where((p) {
      if (_cat == '!' && !(stockOn && p.low)) return false;
      if (_cat.isNotEmpty && _cat != '!' && p.category != _cat) return false;
      if (words.isEmpty) return true;
      final hay = fold('${p.name} ${p.category}');
      return p.barcode == _q.trim() || words.every(hay.contains);
    }).toList();
    final lowCount = stockOn ? _all.where((p) => p.low).length : 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Produits et stock')),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _open(), icon: const Icon(Icons.add), label: const Text('Nouveau produit')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: TextField(decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: 'Chercher parmi ${_all.length} produits', isDense: true), onChanged: (v) => setState(() => _q = v)),
              ),
              if (_cats.isNotEmpty || lowCount > 0)
                SizedBox(
                  height: 46,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    children: [
                      for (final c in [('', 'Tous'), if (lowCount > 0) ('!', 'Stock bas ($lowCount)'), for (final x in _cats) (x, x)])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(label: Text(c.$2), selected: _cat == c.$1, onSelected: (_) => setState(() => _cat = c.$1)),
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: _all.isEmpty
                    ? const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('Aucun produit.\nAjoutez riz, sucre, huile, petit pois… avec leurs prix détail, demi-gros et gros.', textAlign: TextAlign.center)))
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 96),
                        itemCount: shown.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final p = shown[i];
                          return ListTile(
                            onTap: () => _open(p),
                            leading: ProductIcon(icon: p.icon, name: p.name),
                            title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text('${p.category.isEmpty ? '' : '${p.category} · '}${p.unit} · Détail ${fcfa(p.priceRetail)}'
                                '${p.priceSemi > 0 ? ' · Demi ${fcfa(p.priceSemi)}' : ''}'
                                '${p.priceWholesale > 0 ? ' · Gros ${fcfa(p.priceWholesale)}' : ''}'),
                            trailing: stockOn && p.trackStock
                                ? InkWell(
                                    onTap: () => _adjust(p),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: (p.low ? Colors.red : Colors.green).withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                                        Text('${fmtQty(p.stock)} ${p.unit}', style: TextStyle(fontWeight: FontWeight.bold, color: p.low ? Colors.red.shade700 : Colors.green.shade800)),
                                        const SizedBox(width: 4),
                                        const Icon(Icons.edit, size: 14),
                                      ]),
                                    ),
                                  )
                                : null,
                          );
                        },
                      ),
              ),
            ]),
    );
  }
}

class ProductForm extends StatefulWidget {
  const ProductForm({super.key, this.product});
  final Product? product;

  @override
  State<ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends State<ProductForm> {
  late final _name = TextEditingController(text: widget.product?.name ?? '');
  late final _unit = TextEditingController(text: widget.product?.unit ?? 'sac');
  late final _retail = TextEditingController(text: _n(widget.product?.priceRetail));
  late final _semi = TextEditingController(text: _n(widget.product?.priceSemi));
  late final _gros = TextEditingController(text: _n(widget.product?.priceWholesale));
  late final _barcode = TextEditingController(text: widget.product?.barcode ?? '');
  late final _stock = TextEditingController(text: widget.product == null ? '' : fmtQty(widget.product!.stock));
  late final _min = TextEditingController(text: widget.product == null ? '' : fmtQty(widget.product!.minStock));
  late final _cat = TextEditingController(text: widget.product?.category ?? '');
  List<String> _knownCats = [];
  late bool _track = widget.product?.trackStock ?? false;
  late String _icon = widget.product?.icon ?? '';
  bool _iconTouched = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    Db.instance.then((db) => db.listCategories()).then((l) {
      if (mounted) setState(() => _knownCats = l);
    });
  }

  static String _n(int? v) => (v == null || v == 0) ? '' : v.toString();

  @override
  void dispose() {
    for (final c in [_name, _unit, _cat, _retail, _semi, _gros, _barcode, _stock, _min]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _scan() async {
    final code = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const ScanScreen(title: 'Scanner le code-barres')));
    if (code != null) setState(() => _barcode.text = code);
  }

  Future<void> _save() async {
    final retail = parseAmount(_retail.text) ?? 0;
    final semi = parseAmount(_semi.text) ?? 0;
    final gros = parseAmount(_gros.text) ?? 0;
    if (_name.text.trim().isEmpty) {
      setState(() => _err = 'Donnez un nom au produit.');
      return;
    }
    if (retail <= 0 && semi <= 0 && gros <= 0) {
      setState(() => _err = 'Renseignez au moins un prix.');
      return;
    }
    final p = widget.product;
    final base = retail > 0 ? retail : (semi > 0 ? semi : gros);
    final db = await Db.instance;
    await db.saveProduct(Product(
      id: p?.id ?? 0,
      name: _name.text,
      unit: _unit.text,
      priceRetail: base,
      priceSemi: semi,
      priceWholesale: gros,
      barcode: _barcode.text,
      trackStock: _track,
      stock: p?.stock ?? (parseQty(_stock.text) ?? 0),
      minStock: parseQty(_min.text) ?? 0,
      icon: _icon.isEmpty && !_iconTouched ? suggestIcon(_name.text) : _icon,
      category: _cat.text.trim(),
    ));
    AppState.i.touch();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _archive() async {
    final ok = await confirm(context, 'Retirer ce produit ?', 'Il disparaîtra de la vente. Les anciennes factures ne changent pas.', ok: 'Retirer');
    if (!ok || !mounted) return;
    final db = await Db.instance;
    await db.archiveProduct(widget.product!.id);
    AppState.i.touch();
    if (mounted) Navigator.of(context).pop();
  }

  Widget _price(TextEditingController c, String label, String hint) => TextField(
        controller: c,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label, helperText: hint, suffixText: 'F'),
      );

  @override
  Widget build(BuildContext context) {
    final editing = widget.product != null;
    final stockOn = AppState.i.settings.stockEnabled;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Modifier le produit' : 'Nouveau produit'),
        actions: [if (editing) IconButton(tooltip: 'Retirer', icon: const Icon(Icons.delete_outline), onPressed: _archive)],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Row(children: [
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () async {
                  final r = await pickProductIcon(context, current: _icon);
                  if (r != null) {
                    setState(() {
                      _icon = r;
                      _iconTouched = true;
                    });
                  }
                },
                child: Stack(clipBehavior: Clip.none, children: [
                  ProductIcon(icon: _icon.isEmpty && !_iconTouched ? suggestIcon(_name.text) : _icon, name: _name.text, size: 64),
                  Positioned(right: -4, bottom: -4, child: CircleAvatar(radius: 11, backgroundColor: Theme.of(context).colorScheme.primary, child: Icon(Icons.edit, size: 13, color: Theme.of(context).colorScheme.onPrimary))),
                ]),
              ),
              const SizedBox(width: 14),
              Expanded(child: TextField(controller: _name, autofocus: !editing, onChanged: (_) => setState(() {}), textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Nom du produit', hintText: 'ex : Riz brisé 50 kg'))),
            ]),
            const SizedBox(height: 12),
            TextField(controller: _unit, decoration: const InputDecoration(labelText: 'Unité (indicatif)', hintText: 'sac, carton, kg, pièce…', helperText: 'Au poids : kg ou litre. On pourra vendre 250 g, 500 g ou « 500 F ».')),
            Wrap(spacing: 8, children: [
              for (final u in const ['sac', 'carton', 'kg', 'pièce', 'litre', 'bidon'])
                ActionChip(label: Text(u), onPressed: () => setState(() => _unit.text = u)),
            ]),
            const SizedBox(height: 12),
            TextField(controller: _cat, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Rayon / catégorie (facultatif)', hintText: 'Céréales, Boissons, Épicerie…', helperText: 'Pour retrouver vite un produit quand il y en a beaucoup')),
            if (_knownCats.isNotEmpty)
              Wrap(spacing: 8, children: [for (final c in _knownCats) ActionChip(label: Text(c), onPressed: () => setState(() => _cat.text = c))]),
            const SizedBox(height: 20),
            Text('Prix par unité', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            _price(_retail, 'Prix détail', 'Vente à l\'unité / au client ordinaire'),
            const SizedBox(height: 12),
            _price(_semi, 'Prix demi-gros', 'Facultatif'),
            const SizedBox(height: 12),
            _price(_gros, 'Prix gros', 'Facultatif'),
            const SizedBox(height: 20),
            TextField(
              controller: _barcode,
              decoration: InputDecoration(labelText: 'Code-barres (facultatif)', suffixIcon: IconButton(icon: const Icon(Icons.qr_code_scanner), onPressed: _scan)),
            ),
            if (stockOn) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Suivre le stock'),
                subtitle: const Text('Facultatif : le stock baisse à chaque vente'),
                value: _track,
                onChanged: (v) => setState(() => _track = v),
              ),
              if (_track) ...[
                if (!editing) TextField(controller: _stock, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Stock de départ')),
                if (!editing) const SizedBox(height: 12),
                TextField(controller: _min, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Alerte stock bas (à partir de)')),
                if (editing) const Padding(padding: EdgeInsets.only(top: 8), child: Text('Pour changer la quantité en stock, touchez la pastille de stock dans la liste.')),
              ],
            ],
            if (_err != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_err!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
            const SizedBox(height: 20),
            FilledButton(style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)), onPressed: _save, child: const Text('Enregistrer')),
          ]),
        ),
      ),
    );
  }
}
