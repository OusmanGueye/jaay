import 'package:flutter/material.dart';

import '../app_state.dart';
import '../db.dart';
import '../format.dart';
import '../models.dart';
import '../ui.dart';
import 'client_screen.dart';

class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key});

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  List<Client> _clients = [];
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
    final l = await db.listClients();
    if (!mounted) return;
    setState(() {
      _clients = l;
      _loading = false;
    });
  }

  Future<void> _add() async {
    final id = await showClientForm(context);
    if (id == null || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ClientScreen(clientId: id)));
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final shown = q.isEmpty ? _clients : _clients.where((c) => c.fullName.toLowerCase().contains(q) || c.phone.contains(q)).toList();
    final debtors = _clients.where((c) => c.balance > 0).toList();
    final total = debtors.fold<int>(0, (s, c) => s + c.balance);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Clients · Ardoise')),
      floatingActionButton: FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.person_add_alt_1), label: const Text('Nouveau client')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Card(
                  color: cs.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('À recevoir', style: Theme.of(context).textTheme.labelLarge),
                          AmountText(fcfa(total), align: Alignment.centerLeft, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                        ]),
                      ),
                      Text('${debtors.length} client${debtors.length > 1 ? 's' : ''}\nqui doivent', textAlign: TextAlign.right),
                    ]),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Chercher un client', isDense: true),
                  onChanged: (v) => setState(() => _q = v),
                ),
              ),
              Expanded(
                child: _clients.isEmpty
                    ? const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('Aucun client.\nAjoutez ceux à qui vous faites crédit.', textAlign: TextAlign.center)))
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 96),
                        itemCount: shown.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, i) => _ClientTile(
                          client: shown[i],
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ClientScreen(clientId: shown[i].id))),
                        ),
                      ),
              ),
            ]),
    );
  }
}

class _ClientTile extends StatelessWidget {
  const _ClientTile({required this.client, required this.onTap});
  final Client client;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = client;
    final initial = c.fullName.isEmpty ? '?' : c.fullName.characters.first.toUpperCase();
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(child: Text(initial)),
      title: Text(c.fullName.isEmpty ? '(sans nom)' : c.fullName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(c.phone.isNotEmpty ? c.phone : (c.lastAt == null ? 'Aucune vente' : 'Dernière vente ${fmtDate(c.lastAt!)}')),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 130),
        child: AmountText(
          c.balance > 0 ? fcfa(c.balance) : 'Soldé',
          style: TextStyle(color: c.balance > 0 ? Colors.red.shade600 : Theme.of(context).hintColor, fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
    );
  }
}

/// Fiche client : prénom, nom, téléphone. Retourne l'id du client créé / modifié.
Future<int?> showClientForm(BuildContext context, {Client? edit}) async {
  final first = TextEditingController(text: edit?.firstName ?? '');
  final last = TextEditingController(text: edit?.lastName ?? '');
  final phone = TextEditingController(text: edit?.phone ?? '');
  String? err;
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (context, setS) => AlertDialog(
        title: Text(edit == null ? 'Nouveau client' : 'Modifier le client'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: first, autofocus: true, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: 'Prénom', errorText: err)),
            const SizedBox(height: 12),
            TextField(controller: last, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Nom')),
            const SizedBox(height: 12),
            TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Téléphone')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              if (first.text.trim().isEmpty && last.text.trim().isEmpty) {
                setS(() => err = 'Entrez un prénom ou un nom');
              } else {
                Navigator.pop(context, true);
              }
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    ),
  );
  final f = first.text, l = last.text, p = phone.text;
  first.dispose();
  last.dispose();
  phone.dispose();
  if (ok != true) return null;
  final db = await Db.instance;
  int id;
  if (edit == null) {
    id = await db.addClient(firstName: f, lastName: l, phone: p);
  } else {
    await db.updateClient(edit.id, firstName: f, lastName: l, phone: p, note: edit.note);
    id = edit.id;
  }
  AppState.i.touch();
  return id;
}

/// Choix d'un client dans une liste. Le client comptoir est retourné avec l'id 0.
Future<Client?> pickClient(BuildContext context, {bool allowCounter = false}) {
  return showModalBottomSheet<Client>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ClientPicker(allowCounter: allowCounter),
  );
}

class _ClientPicker extends StatefulWidget {
  const _ClientPicker({required this.allowCounter});
  final bool allowCounter;

  @override
  State<_ClientPicker> createState() => _ClientPickerState();
}

class _ClientPickerState extends State<_ClientPicker> {
  List<Client> _all = [];
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = await Db.instance;
    final l = await db.listClients();
    if (!mounted) return;
    setState(() => _all = l);
  }

  Future<void> _new() async {
    final id = await showClientForm(context);
    if (id == null || !mounted) return;
    final db = await Db.instance;
    final c = await db.getClient(id);
    if (mounted && c != null) Navigator.pop(context, c);
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final shown = q.isEmpty ? _all : _all.where((c) => c.fullName.toLowerCase().contains(q) || c.phone.contains(q)).toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.75,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Expanded(child: TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Chercher un client', isDense: true), onChanged: (v) => setState(() => _q = v))),
              const SizedBox(width: 8),
              FilledButton.icon(onPressed: _new, icon: const Icon(Icons.person_add_alt_1), label: const Text('Nouveau')),
            ]),
          ),
          if (widget.allowCounter)
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.storefront)),
              title: const Text('Client comptoir'),
              subtitle: const Text('Vente comptant, sans nom'),
              onTap: () => Navigator.pop(context, Client(id: 0, firstName: '', lastName: '', phone: '', note: '', balance: 0, lastAt: null)),
            ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: shown.length,
              itemBuilder: (_, i) {
                final c = shown[i];
                return ListTile(
                  leading: CircleAvatar(child: Text(c.fullName.isEmpty ? '?' : c.fullName.characters.first.toUpperCase())),
                  title: Text(c.fullName),
                  subtitle: c.phone.isEmpty ? null : Text(c.phone),
                  trailing: c.balance > 0 ? Text(fcfa(c.balance), style: TextStyle(color: Colors.red.shade600, fontWeight: FontWeight.bold)) : null,
                  onTap: () => Navigator.pop(context, c),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}
