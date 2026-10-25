import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app_state.dart';
import '../db.dart';
import '../format.dart';
import '../models.dart';
import '../receipts.dart';
import '../ui.dart';

class SaleDetailScreen extends StatefulWidget {
  const SaleDetailScreen({super.key, required this.saleId});
  final int saleId;

  @override
  State<SaleDetailScreen> createState() => _SaleDetailScreenState();
}

class _SaleDetailScreenState extends State<SaleDetailScreen> {
  Sale? _sale;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = await Db.instance;
    final s = await db.getSale(widget.saleId);
    if (!mounted) return;
    setState(() => _sale = s);
  }

  Future<void> _pay() async {
    final s = _sale!;
    final r = await askPayment(context, title: 'Encaisser une tranche', max: s.due, initial: null);
    if (r == null || !mounted) return;
    final db = await Db.instance;
    await db.addPayment(s.id, r.amount, r.method);
    AppState.i.touch();
    await _load();
    if (!mounted) return;
    final settings = AppState.i.settings;
    final fresh = _sale!;
    final clientAfter = fresh.clientId == null ? null : await db.getClient(fresh.clientId!);
    if (!mounted) return;
    if (settings.autoPrint && settings.hasPrinter) {
      await printTicket(
        context,
        paymentReceipt(
          settings,
          clientName: fresh.displayClient,
          parts: [MapEntry(fresh.id, r.amount)],
          method: r.method,
          remaining: clientAfter?.balance ?? fresh.due,
          remainingOnSale: fresh.due,
          clientId: fresh.clientId,
        ),
      );
    } else {
      toast(context, 'Paiement enregistré.');
    }
  }

  Future<void> _refund() async {
    final s = _sale!;
    final ok = await confirm(
      context,
      'Rembourser cette vente ?',
      s.paid > 0
          ? 'La facture ${s.number} sera annulée, le stock remis, et ${fcfa(s.paid)} rendus au client.'
          : 'La facture ${s.number} sera annulée et le stock remis (rien à rendre : elle n\'était pas payée).',
      ok: 'Rembourser',
    );
    if (!ok || !mounted) return;
    final db = await Db.instance;
    final amount = await db.refundSale(s.id);
    AppState.i.touch();
    await _load();
    if (!mounted) return;
    final settings = AppState.i.settings;
    if (settings.autoPrint && settings.hasPrinter && amount > 0) {
      await printTicket(context, refundReceipt(settings, _sale!, amount));
    } else {
      toast(context, 'Vente remboursée.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _sale;
    if (s == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    final settings = AppState.i.settings;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.number),
        actions: [
          IconButton(
            tooltip: 'Imprimer un duplicata',
            icon: const Icon(Icons.print_outlined),
            onPressed: () => printTicket(context, saleReceipt(settings, s, duplicate: true)),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.displayClient, style: theme.textTheme.titleLarge),
                  Text(fmtDateTime(s.createdAt)),
                  const SizedBox(height: 6),
                  SaleStatusChip(s),
                ]),
              ),
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(6),
                child: QrImageView(data: s.qrData, size: 92, padding: EdgeInsets.zero),
              ),
            ]),
            const SizedBox(height: 16),
            Card(
              child: Column(children: [
                for (final it in s.items)
                  ListTile(
                    dense: true,
                    title: Text(it.name),
                    subtitle: Text(qtyLine(it.qty, it.unit, it.unitPrice)),
                    trailing: Text(fcfa(it.total), style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                const Divider(height: 1),
                if (s.discount > 0) _row('Sous-total', fcfa(s.subtotal)),
                if (s.discount > 0) _row('Remise', '-${fcfa(s.discount)}'),
                _row('Total', fcfa(s.total), bold: true),
                _row('Déjà payé', fcfa(s.paid)),
                if (!s.refunded) _row('Reste à payer', fcfa(s.due), bold: true, color: dueColor(context, s.due)),
                const SizedBox(height: 8),
              ]),
            ),
            if (s.payments.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Paiements', style: theme.textTheme.titleSmall),
              Card(
                child: Column(children: [
                  for (final p in s.payments)
                    ListTile(
                      dense: true,
                      leading: Icon(p.isRefund ? Icons.undo : Icons.payments_outlined, color: p.isRefund ? Colors.red.shade600 : null),
                      title: Text(p.isRefund ? 'Remboursement' : methodLabel(p.method)),
                      subtitle: Text(fmtDateTime(p.createdAt)),
                      trailing: Text(p.isRefund ? '-${fcfa(-p.amount)}' : fcfa(p.amount), style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                ]),
              ),
            ],
            const SizedBox(height: 20),
            if (!s.refunded && s.due > 0)
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                onPressed: _pay,
                icon: const Icon(Icons.payments),
                label: const Text('Encaisser une tranche'),
              ),
            if (!s.refunded) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50), foregroundColor: Colors.red.shade600),
                onPressed: _refund,
                icon: const Icon(Icons.undo),
                label: const Text('Rembourser / annuler la vente'),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _row(String a, String b, {bool bold = false, Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(a, style: TextStyle(fontWeight: bold ? FontWeight.bold : null)),
          Text(b, style: TextStyle(fontWeight: bold ? FontWeight.bold : null, color: color)),
        ]),
      );
}
