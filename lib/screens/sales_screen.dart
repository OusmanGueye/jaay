import 'package:flutter/material.dart';

import '../app_state.dart';
import '../db.dart';
import '../format.dart';
import '../models.dart';
import '../period.dart';
import '../ui.dart';
import 'sale_detail_screen.dart';

/// Historique des factures, filtre « à payer », recherche par numéro et scan de QR code.
class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  List<Sale> _sales = [];
  String _filter = 'all'; // all | due
  Period _period = Period.of(PeriodKind.month);
  String _q = '';
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
    final l = await db.listSales(dueOnly: _filter == 'due', from: _period.startMs, to: _period.endMs, limit: 2000);
    if (!mounted) return;
    setState(() {
      _sales = l;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final shown = q.isEmpty
        ? _sales
        : _sales.where((s) => s.number.toLowerCase().contains(q) || s.displayClient.toLowerCase().contains(q)).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Factures'),
        actions: [
          IconButton.filledTonal(tooltip: 'Scanner un QR code', icon: const Icon(Icons.qr_code_scanner), onPressed: () => scanAndOpen(context)),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'N° de facture ou nom du client', isDense: true),
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
        const SizedBox(height: 4),
        PeriodBar(period: _period, onChanged: (p) {
          setState(() => _period = p);
          _load();
        }),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(children: [
            for (final f in const [('all', 'Toutes'), ('due', 'À payer')])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  showCheckmark: false,
                  label: Text(f.$2),
                  selected: _filter == f.$1,
                  onSelected: (_) {
                    setState(() => _filter = f.$1);
                    _load();
                  },
                ),
              ),
            const Spacer(),
            Text('${shown.length} · ${fcfa(shown.where((s) => !s.refunded).fold<int>(0, (a, s) => a + s.total))}', style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : shown.isEmpty
                  ? const Center(child: Text('Aucune facture.'))
                  : ListView.separated(
                      itemCount: shown.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final x = shown[i];
                        return ListTile(
                          title: Text('${x.number} · ${x.displayClient}', maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(fmtDateTime(x.createdAt)),
                          trailing: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 130),
                            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                              AmountText(fcfa(x.total), style: TextStyle(fontWeight: FontWeight.bold, decoration: x.refunded ? TextDecoration.lineThrough : null)),
                              const SizedBox(height: 2),
                              SaleStatusChip(x),
                            ]),
                          ),
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SaleDetailScreen(saleId: x.id))),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}
