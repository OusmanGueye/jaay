import 'package:flutter/material.dart';

import '../activation.dart';
import '../app_state.dart';
import '../db.dart';
import '../format.dart';
import '../models.dart';
import '../period.dart';
import '../receipts.dart';
import '../ui.dart';
import 'sale_detail_screen.dart';
import 'shell.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Period _period = Period.of(PeriodKind.today);
  DaySummary? _sum;
  int _debts = 0;
  int _debtors = 0;
  int _low = 0;
  List<Sale> _recent = [];

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
    final sum = await db.rangeSummary(_period.startMs, _period.endMs);
    final debt = await db.debtOverview();
    final low = await db.lowStockCount();
    final recent = await db.listSales(limit: 6);
    if (!mounted) return;
    setState(() {
      _sum = sum;
      _debts = debt.total;
      _debtors = debt.debtors;
      _low = low;
      _recent = recent;
    });
  }

  void _setPeriod(Period p) {
    setState(() => _period = p);
    _load();
  }

  Future<void> _closing() async {
    final d = _sum;
    if (d == null) return;
    await printTicket(context, closingReceipt(AppState.i.settings, _period.label, d, _debts));
  }

  static const _methodIcons = {'cash': Icons.payments_outlined, 'wave': Icons.waves, 'om': Icons.phone_android};

  @override
  Widget build(BuildContext context) {
    final s = AppState.i.settings;
    final d = _sum;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s.shopName, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(kAppName, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w500)),
        ]),
        actions: [
          IconButton(tooltip: 'Scanner un QR code', icon: const Icon(Icons.qr_code_scanner), onPressed: () => scanAndOpen(context)),
          IconButton(tooltip: 'Réglages', icon: const Icon(Icons.settings_outlined), onPressed: () => openSettings(context)),
        ],
      ),
      body: Column(children: [
        const SizedBox(height: 4),
        PeriodBar(period: _period, onChanged: _setPeriod),
        const SizedBox(height: 8),
        Expanded(
          child: d == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: LayoutBuilder(builder: (context, box) {
                    final wide = box.maxWidth >= 860;
                    final hero = _hero(context, d);
                    final stats = _stats(context, d);
                    final collect = _collect(context, d);
                    final actions = _actions(context);
                    final recent = _recentList(context);
                    final stock = _stockAlert(context);
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                      children: [
                        if (wide)
                          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Expanded(
                              flex: 6,
                              child: Column(children: [hero, const SizedBox(height: 12), stats, if (stock != null) ...[const SizedBox(height: 12), stock], const SizedBox(height: 12), actions]),
                            ),
                            const SizedBox(width: 16),
                            Expanded(flex: 5, child: Column(children: [collect, recent])),
                          ])
                        else ...[
                          hero,
                          const SizedBox(height: 12),
                          stats,
                          if (stock != null) ...[const SizedBox(height: 12), stock],
                          const SizedBox(height: 12),
                          actions,
                          const SizedBox(height: 12),
                          collect,
                          recent,
                        ],
                      ],
                    );
                  }),
                ),
        ),
      ]),
    );
  }

  Widget _hero(BuildContext context, DaySummary d) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [cs.primary, Color.lerp(cs.primary, Colors.black, 0.4)!]),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.trending_up, color: cs.onPrimary.withValues(alpha: 0.85), size: 18),
          const SizedBox(width: 6),
          Expanded(child: Text('Ventes · ${_period.label}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onPrimary.withValues(alpha: 0.9), fontWeight: FontWeight.w600))),
        ]),
        const SizedBox(height: 8),
        AmountText(fcfa(d.salesTotal), align: Alignment.centerLeft, style: TextStyle(fontSize: 38, fontWeight: FontWeight.w800, color: cs.onPrimary)),
        const SizedBox(height: 4),
        Text('${d.salesCount} facture${d.salesCount > 1 ? 's' : ''}', style: TextStyle(color: cs.onPrimary.withValues(alpha: 0.85))),
      ]),
    );
  }

  Widget _stats(BuildContext context, DaySummary d) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, box) {
      final w = (box.maxWidth - 12) / 2;
      return Wrap(spacing: 12, runSpacing: 12, children: [
        SizedBox(width: w, child: StatCard(label: 'Encaissé (net)', value: fcfa(d.net), sub: d.refunded > 0 ? 'après ${fcfa(d.refunded)} remboursés' : 'argent reçu', icon: Icons.account_balance_wallet_outlined, color: cs.primaryContainer)),
        SizedBox(width: w, child: StatCard(label: 'Vendu à crédit', value: fcfa(d.creditGranted), sub: 'sur la période', icon: Icons.menu_book_outlined)),
        SizedBox(width: w, child: StatCard(label: 'Dettes clients', value: fcfa(_debts), sub: '$_debtors client${_debtors > 1 ? 's' : ''} (total)', icon: Icons.groups_outlined, color: _debts > 0 ? cs.errorContainer : null)),
        SizedBox(width: w, child: StatCard(label: 'Dettes payées', value: fcfa(d.debtsCollected), sub: 'reçues sur la période', icon: Icons.task_alt)),
      ]);
    });
  }

  Widget _collect(BuildContext context, DaySummary d) {
    final total = d.collectedTotal;
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Encaissements · ${_period.label}', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          for (final m in kMethods) ...[
            Row(children: [
              Icon(_methodIcons[m], size: 20, color: cs.primary),
              const SizedBox(width: 10),
              Expanded(child: Text(methodLabel(m))),
              Flexible(child: AmountText(fcfa(d.collected[m] ?? 0), style: const TextStyle(fontWeight: FontWeight.w700))),
            ]),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(minHeight: 6, value: total == 0 ? 0 : (d.collected[m] ?? 0) / total, backgroundColor: cs.surfaceContainerHighest),
            ),
            const SizedBox(height: 12),
          ],
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(onPressed: _closing, icon: const Icon(Icons.print_outlined), label: const Text('Imprimer la clôture de caisse')),
          ),
        ]),
      ),
    );
  }

  Widget? _stockAlert(BuildContext context) {
    if (_low == 0 || !AppState.i.settings.stockEnabled) return null;
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.tertiaryContainer,
      child: ListTile(
        leading: Icon(Icons.warning_amber_rounded, color: cs.onTertiaryContainer),
        title: Text('$_low produit${_low > 1 ? 's' : ''} en stock bas', style: TextStyle(color: cs.onTertiaryContainer, fontWeight: FontWeight.w600)),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => AppState.i.tab.value = 4,
      ),
    );
  }

  Widget _actions(BuildContext context) => Row(children: [
        Expanded(flex: 3, child: FilledButton.icon(style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)), onPressed: () => AppState.i.tab.value = 1, icon: const Icon(Icons.add_shopping_cart), label: const Text('Nouvelle vente'))),
        const SizedBox(width: 12),
        Expanded(flex: 2, child: OutlinedButton.icon(style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)), onPressed: () => scanAndOpen(context), icon: const Icon(Icons.qr_code_scanner), label: const Text('Scanner'))),
      ]);

  Widget _recentList(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle('Dernières factures', trailing: TextButton(onPressed: () => AppState.i.tab.value = 2, child: const Text('Tout voir'))),
        if (_recent.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Aucune vente pour le moment.')),
        for (final x in _recent)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              child: ListTile(
                title: Text('${x.number} · ${x.displayClient}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(fmtDateTime(x.createdAt)),
                trailing: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 130),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                    AmountText(fcfa(x.total), style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    SaleStatusChip(x),
                  ]),
                ),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SaleDetailScreen(saleId: x.id))),
              ),
            ),
          ),
      ]);
}
