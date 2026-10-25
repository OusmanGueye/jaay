import 'package:flutter/material.dart';

import '../app_state.dart';
import '../db.dart';
import '../format.dart';
import '../models.dart';
import '../receipts.dart';
import '../ui.dart';
import 'clients_screen.dart';
import 'sale_detail_screen.dart';

class ClientScreen extends StatefulWidget {
  const ClientScreen({super.key, required this.clientId});
  final int clientId;

  @override
  State<ClientScreen> createState() => _ClientScreenState();
}

class _ClientScreenState extends State<ClientScreen> {
  Client? _client;
  List<Sale> _sales = [];

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
    final c = await db.getClient(widget.clientId);
    final s = await db.listSales(clientId: widget.clientId);
    if (!mounted) return;
    setState(() {
      _client = c;
      _sales = s;
    });
  }

  Future<void> _pay() async {
    final c = _client!;
    final r = await askPayment(context, title: 'Encaisser (ardoise de ${c.firstName.isEmpty ? c.lastName : c.firstName})', max: c.balance);
    if (r == null || !mounted) return;
    final db = await Db.instance;
    final parts = await db.payClientDebt(c.id, r.amount, r.method);
    AppState.i.touch();
    final after = await db.getClient(c.id);
    if (!mounted) return;
    final settings = AppState.i.settings;
    if (settings.autoPrint && settings.hasPrinter) {
      await printTicket(
        context,
        paymentReceipt(settings, clientName: c.fullName, parts: parts, method: r.method, remaining: after?.balance ?? 0, clientId: c.id),
      );
    } else {
      toast(context, 'Paiement de ${fcfa(r.amount)} enregistré.');
    }
  }

  void _sell() {
    AppState.i.cart.setClient(_client);
    AppState.i.tab.value = 1;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _statement() async {
    final c = _client!;
    await printTicket(context, statementReceipt(AppState.i.settings, c, _sales.where((s) => s.due > 0).toList()));
  }

  Future<void> _edit() async {
    await showClientForm(context, edit: _client);
  }

  Future<void> _delete() async {
    final c = _client!;
    if (c.balance > 0) {
      toast(context, 'Impossible : ce client doit encore ${fcfa(c.balance)}.');
      return;
    }
    final ok = await confirm(context, 'Supprimer ${c.fullName} ?', 'Ses anciennes factures restent dans l\'historique.', ok: 'Supprimer');
    if (!ok || !mounted) return;
    final db = await Db.instance;
    await db.deleteClient(c.id);
    AppState.i.touch();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = _client;
    if (c == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    final theme = Theme.of(context);
    final open = _sales.where((s) => s.due > 0).toList();
    final others = _sales.where((s) => s.due == 0).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(c.fullName),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) => v == 'edit' ? _edit() : _delete(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Modifier')),
              PopupMenuItem(value: 'del', child: Text('Supprimer')),
            ],
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Card(
              color: c.balance > 0 ? theme.colorScheme.errorContainer : theme.colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(children: [
                  Text(c.balance > 0 ? 'Il doit' : 'Compte soldé', style: theme.textTheme.titleMedium),
                  Text(fcfa(c.balance), style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold)),
                  if (c.phone.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(c.phone)),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: FilledButton.icon(style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)), onPressed: c.balance > 0 ? _pay : null, icon: const Icon(Icons.payments), label: const Text('Encaisser'))),
              const SizedBox(width: 12),
              Expanded(child: FilledButton.tonalIcon(style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)), onPressed: _sell, icon: const Icon(Icons.add_shopping_cart), label: const Text('Nouvelle vente'))),
            ]),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(onPressed: open.isEmpty ? null : _statement, icon: const Icon(Icons.print_outlined), label: const Text('Imprimer le relevé')),
            ),
            if (open.isNotEmpty) ...[
              Text('Factures à payer', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Card(child: Column(children: [for (final s in open) _saleTile(s)])),
              const SizedBox(height: 16),
            ],
            if (others.isNotEmpty) ...[
              Text('Historique', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Card(child: Column(children: [for (final s in others) _saleTile(s)])),
            ],
            if (_sales.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Aucune vente pour ce client.'))),
          ]),
        ),
      ),
    );
  }

  Widget _saleTile(Sale s) => ListTile(
        title: Text('${s.number} · ${fcfa(s.total)}'),
        subtitle: Text(fmtDateTime(s.createdAt)),
        trailing: SaleStatusChip(s),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SaleDetailScreen(saleId: s.id))),
      );
}
