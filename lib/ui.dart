import 'package:flutter/material.dart';

import 'app_state.dart';
import 'format.dart';
import 'period.dart';
import 'models.dart';
import 'printer_service.dart';
import 'screens/client_screen.dart';
import 'screens/scan_screen.dart';
import 'screens/sale_detail_screen.dart';
import 'db.dart';

/// Largeur à partir de laquelle on passe en mise en page tablette / terminal large.
const double kWide = 720;

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

/// Imprime [bytes] sur l'imprimante configurée et affiche le résultat.
Future<bool> printTicket(BuildContext context, List<int> bytes) async {
  final messenger = ScaffoldMessenger.of(context);
  final err = await PrinterService.printBytes(AppState.i.settings, bytes);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(err ?? 'Ticket imprimé.')));
  return err == null;
}

/// Ouvre la facture ou le client désigné par un texte scanné / saisi.
Future<void> openScanned(BuildContext context, String raw) async {
  final t = ScanTarget.parse(raw);
  final db = await Db.instance;
  if (!context.mounted) return;
  if (t == null) {
    toast(context, 'Code non reconnu : $raw');
    return;
  }
  if (t.kind == 'F') {
    if (await db.getSale(t.id) == null) {
      if (context.mounted) toast(context, 'Facture introuvable.');
      return;
    }
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => SaleDetailScreen(saleId: t.id)));
  } else {
    if (await db.getClient(t.id) == null) {
      if (context.mounted) toast(context, 'Client introuvable.');
      return;
    }
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ClientScreen(clientId: t.id)));
  }
}

/// Ouvre la caméra pour lire un code puis ouvre ce qu'il désigne.
Future<void> scanAndOpen(BuildContext context) async {
  final raw = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const ScanScreen()));
  if (raw == null || !context.mounted) return;
  await openScanned(context, raw);
}

/// Couleur d'un solde : rouge si dû, vert si soldé.
Color dueColor(BuildContext context, int due) =>
    due > 0 ? Colors.red.shade600 : Colors.green.shade600;

class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.label, required this.value, this.icon, this.color, this.sub});
  final String label;
  final String value;
  final String? sub;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: color ?? cs.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 6)],
              Expanded(child: Text(label, style: Theme.of(context).textTheme.labelLarge)),
            ]),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            ),
            if (sub != null) Text(sub!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// Pastille d'état d'une facture.
class SaleStatusChip extends StatelessWidget {
  const SaleStatusChip(this.sale, {super.key});
  final Sale sale;

  @override
  Widget build(BuildContext context) {
    final (String label, Color c) = sale.refunded
        ? ('Remboursée', Colors.grey)
        : sale.due > 0
            ? ('Reste ${fcfa(sale.due)}', Colors.red.shade600)
            : ('Payée', Colors.green.shade600);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: c, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }
}

/// Boîte de saisie d'un montant en FCFA avec choix du mode de paiement.
class PayResult {
  PayResult(this.amount, this.method);
  final int amount;
  final String method;
}

Future<PayResult?> askPayment(BuildContext context, {required String title, required int max, int? initial}) {
  return showDialog<PayResult>(
    context: context,
    builder: (_) => _PayDialog(title: title, max: max, initial: initial),
  );
}

class _PayDialog extends StatefulWidget {
  const _PayDialog({required this.title, required this.max, this.initial});
  final String title;
  final int max;
  final int? initial;

  @override
  State<_PayDialog> createState() => _PayDialogState();
}

class _PayDialogState extends State<_PayDialog> {
  late final _c = TextEditingController(text: widget.initial?.toString() ?? '');
  String _method = 'cash';
  String? _err;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _ok() {
    final a = parseAmount(_c.text);
    if (a == null || a <= 0) {
      setState(() => _err = 'Entrez un montant.');
    } else if (a > widget.max) {
      setState(() => _err = 'Maximum ${fcfa(widget.max)}.');
    } else {
      Navigator.pop(context, PayResult(a, _method));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            controller: _c,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: 'Montant reçu (FCFA)', suffixText: 'F', errorText: _err),
            onSubmitted: (_) => _ok(),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: ActionChip(
              avatar: const Icon(Icons.done_all, size: 18),
              label: Text('Tout payer (${fcfa(widget.max)})'),
              onPressed: () => setState(() => _c.text = widget.max.toString()),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            for (final m in kMethods)
              ChoiceChip(label: Text(methodLabel(m)), selected: _method == m, onSelected: (_) => setState(() => _method = m)),
          ]),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(onPressed: _ok, child: const Text('Encaisser')),
      ],
    );
  }
}

Future<bool> confirm(BuildContext context, String title, String body, {String ok = 'Confirmer'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(ok)),
      ],
    ),
  );
  return r ?? false;
}

/// Montant qui rétrécit au lieu de déborder quand il est très grand.
class AmountText extends StatelessWidget {
  const AmountText(this.value, {super.key, this.style, this.align = Alignment.centerRight});
  final String value;
  final TextStyle? style;
  final AlignmentGeometry align;

  @override
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: align,
        child: Text(value, maxLines: 1, style: style),
      );
}

/// Titre de section.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Row(children: [
          Expanded(child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
          ?trailing,
        ]),
      );
}

/// Choix de période : aujourd'hui, hier, 7 jours, mois, année ou dates précises.
class PeriodBar extends StatelessWidget {
  const PeriodBar({super.key, required this.period, required this.onChanged, this.kinds});
  final Period period;
  final ValueChanged<Period> onChanged;
  final List<PeriodKind>? kinds;

  Future<void> _custom(BuildContext context) async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1),
      initialDateRange: DateTimeRange(start: period.start, end: period.end.subtract(const Duration(days: 1))),
      locale: const Locale('fr'),
      helpText: 'Choisir la période',
      saveText: 'Valider',
    );
    if (r != null) onChanged(Period.of(PeriodKind.custom, from: r.start, to: r.end));
  }

  @override
  Widget build(BuildContext context) {
    final list = kinds ?? PeriodKind.values;
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final k in list)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                showCheckmark: false,
                avatar: k == PeriodKind.custom ? const Icon(Icons.date_range, size: 18) : null,
                label: Text(k == PeriodKind.custom && period.kind == PeriodKind.custom ? period.label : kPeriodLabels[k]!),
                selected: period.kind == k,
                onSelected: (_) => k == PeriodKind.custom ? _custom(context) : onChanged(Period.of(k)),
              ),
            ),
        ],
      ),
    );
  }
}

/// Saisie d'une quantité : directement dans l'unité, en grammes / millilitres (si kg / litre),
/// ou « par montant » (ex : 500 F de sucre). Retourne la quantité en unité de vente.
Future<double?> askQuantity(
  BuildContext context, {
  required String name,
  required String unit,
  required int unitPrice,
  double initial = 1,
}) {
  return showDialog<double>(
    context: context,
    builder: (_) => _QtyDialog(name: name, unit: unit, unitPrice: unitPrice, initial: initial),
  );
}

class _QtyDialog extends StatefulWidget {
  const _QtyDialog({required this.name, required this.unit, required this.unitPrice, required this.initial});
  final String name;
  final String unit;
  final int unitPrice;
  final double initial;

  @override
  State<_QtyDialog> createState() => _QtyDialogState();
}

class _QtyDialogState extends State<_QtyDialog> {
  String _mode = 'qty'; // qty | small | amt
  late final _c = TextEditingController(text: fmtQty(widget.initial));

  String get _u => widget.unit.trim().toLowerCase();
  bool get _hasSmall => _u == 'kg' || _u == 'litre' || _u == 'l';
  String get _smallLabel => _u == 'kg' ? 'g' : 'ml';

  double? get _value {
    switch (_mode) {
      case 'small':
        final v = parseQty(_c.text);
        return v == null ? null : v / 1000;
      case 'amt':
        final a = parseAmount(_c.text);
        return (a == null || widget.unitPrice <= 0) ? null : a / widget.unitPrice;
      default:
        return parseQty(_c.text);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _setQty(double v) => setState(() {
        _mode = 'qty';
        _c.text = fmtQty(v);
      });

  @override
  Widget build(BuildContext context) {
    final v = _value;
    final ok = v != null && v > 0;
    final total = ok ? (v * widget.unitPrice).round() : 0;
    final quick = _hasSmall ? const [0.25, 0.5, 0.75, 1.0, 2.0, 5.0] : const [0.5, 1.0, 2.0, 5.0, 10.0, 20.0];
    return AlertDialog(
      title: Text(widget.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${fcfa(widget.unitPrice)} par ${widget.unit.isEmpty ? 'unité' : widget.unit}', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: 'qty', label: Text(widget.unit.isEmpty ? 'Qté' : widget.unit)),
              if (_hasSmall) ButtonSegment(value: 'small', label: Text(_smallLabel)),
              const ButtonSegment(value: 'amt', label: Text('Montant')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() {
              _mode = s.first;
              _c.clear();
            }),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _c,
            autofocus: true,
            keyboardType: _mode == 'amt' ? TextInputType.number : const TextInputType.numberWithOptions(decimal: true),
            style: Theme.of(context).textTheme.headlineSmall,
            decoration: InputDecoration(
              labelText: _mode == 'amt' ? 'Montant demandé (FCFA)' : (_mode == 'small' ? 'Quantité en $_smallLabel' : 'Quantité (${widget.unit})'),
              suffixText: _mode == 'amt' ? 'F' : (_mode == 'small' ? _smallLabel : widget.unit),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) {
              if (ok) Navigator.pop(context, v);
            },
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final q in quick) ActionChip(label: Text(fmtQtyUnit(q, widget.unit.isEmpty ? '' : widget.unit)), onPressed: () => _setQty(q)),
          ]),
          const SizedBox(height: 12),
          if (ok)
            Text('= ${fmtQtyUnit(v, widget.unit)} · ${fcfa(total)}', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(onPressed: ok ? () => Navigator.pop(context, v) : null, child: const Text('Valider')),
      ],
    );
  }
}
