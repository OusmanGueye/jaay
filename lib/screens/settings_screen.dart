import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../activation.dart';
import '../app_state.dart';
import '../customer_display.dart';
import '../models.dart';
import '../printer_service.dart';
import '../raster.dart';
import '../receipts.dart';
import '../ui.dart';
import 'about_screen.dart';
import 'sync_card.dart';

const _palette = <(String, int)>[
  ('Vert', 0xFF1B7F4B),
  ('Bleu', 0xFF1565C0),
  ('Orange', 0xFFE65100),
  ('Rouge', 0xFFC62828),
  ('Violet', 0xFF6A1B9A),
  ('Turquoise', 0xFF00838F),
  ('Marron', 0xFF5D4037),
  ('Noir', 0xFF263238),
];

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late AppSettings _s = AppState.i.settings.clone();
  late final _name = TextEditingController(text: _s.shopName);
  late final _addr = TextEditingController(text: _s.address);
  late final _p1 = TextEditingController(text: _s.phone1);
  late final _p2 = TextEditingController(text: _s.phone2);
  late final _footer = TextEditingController(text: _s.footer);
  List<BluetoothInfo> _devices = [];
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  @override
  void dispose() {
    for (final c in [_name, _addr, _p1, _p2, _footer]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _scan() async {
    setState(() => _scanning = true);
    List<BluetoothInfo> list = [];
    try {
      list = await PrinterService.pairedPrinters();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _devices = list;
      _scanning = false;
    });
  }

  void _collect() {
    _s.shopName = _name.text.trim().isEmpty ? 'MA BOUTIQUE' : _name.text.trim();
    _s.address = _addr.text.trim();
    _s.phone1 = _p1.text.trim();
    _s.phone2 = _p2.text.trim();
    _s.footer = _footer.text.trim();
  }

  Future<void> _pickLogo() async {
    try {
      final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 900, imageQuality: 90);
      if (f == null) return;
      final b64 = prepareLogo(await f.readAsBytes());
      if (!mounted) return;
      if (b64 == null) {
        toast(context, 'Image illisible.');
      } else {
        setState(() => _s.logoB64 = b64);
      }
    } catch (e) {
      if (mounted) toast(context, 'Impossible d\'ouvrir la galerie : $e');
    }
  }

  Future<void> _save({bool close = true}) async {
    _collect();
    await AppState.i.saveSettings(_s);
    if (!mounted) return;
    if (close) {
      Navigator.of(context).pop();
    } else {
      // Les réglages enregistrés deviennent la nouvelle base de travail.
      _s = AppState.i.settings.clone();
    }
  }

  Future<void> _test() async {
    _collect();
    await AppState.i.saveSettings(_s);
    _s = AppState.i.settings.clone();
    if (!mounted) return;
    await printTicket(context, testReceipt(AppState.i.settings));
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 8),
        child: Text(t, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
      );

  @override
  Widget build(BuildContext context) {
    final logo = _s.logoB64;
    return Scaffold(
      appBar: AppBar(title: const Text('Réglages')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
            _section('Boutique (imprimé sur les tickets)'),
            TextField(controller: _name, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Nom de la boutique')),
            const SizedBox(height: 12),
            TextField(controller: _addr, maxLines: 2, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Adresse')),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(controller: _p1, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Téléphone 1'))),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: _p2, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Téléphone 2'))),
            ]),
            const SizedBox(height: 12),
            TextField(controller: _footer, maxLines: 2, decoration: const InputDecoration(labelText: 'Message en bas du ticket')),
            const SizedBox(height: 16),
            Row(children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Theme.of(context).dividerColor), borderRadius: BorderRadius.circular(8)),
                child: logo == null ? const Icon(Icons.image_outlined, size: 36, color: Colors.grey) : Padding(padding: const EdgeInsets.all(4), child: Image.memory(base64Decode(logo))),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  FilledButton.tonalIcon(onPressed: _pickLogo, icon: const Icon(Icons.add_photo_alternate_outlined), label: Text(logo == null ? 'Ajouter le logo' : 'Changer le logo')),
                  if (logo != null) TextButton(onPressed: () => setState(() => _s.logoB64 = null), child: const Text('Retirer le logo')),
                ]),
              ),
            ]),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Imprimer le logo'), subtitle: const Text('Désactivez pour imprimer plus vite'), value: _s.printLogo, onChanged: (v) => setState(() => _s.printLogo = v)),
            if (_s.printLogo && logo != null) ...[
              const Text('Taille du logo sur le ticket'),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 0, label: Text('Petit')),
                  ButtonSegment(value: 1, label: Text('Moyen')),
                  ButtonSegment(value: 2, label: Text('Grand')),
                ],
                selected: {_s.logoSize},
                onSelectionChanged: (v) => setState(() => _s.logoSize = v.first),
              ),
            ],
            _section('Apparence'),
            const Text('Couleur principale'),
            const SizedBox(height: 8),
            Wrap(spacing: 12, runSpacing: 12, children: [
              for (final c in _palette)
                Tooltip(
                  message: c.$1,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => setState(() => _s.colorValue = c.$2),
                    child: CircleAvatar(
                      radius: 22,
                      backgroundColor: Color(c.$2),
                      child: _s.colorValue == c.$2 ? const Icon(Icons.check, color: Colors.white) : null,
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'system', label: Text('Auto'), icon: Icon(Icons.brightness_auto)),
                ButtonSegment(value: 'light', label: Text('Clair'), icon: Icon(Icons.light_mode_outlined)),
                ButtonSegment(value: 'dark', label: Text('Sombre'), icon: Icon(Icons.dark_mode_outlined)),
              ],
              selected: {_s.themeMode},
              onSelectionChanged: (v) => setState(() => _s.themeMode = v.first),
            ),
            _section('Imprimante'),
            Row(children: [
              const Expanded(child: Text('Imprimante Bluetooth')),
              TextButton.icon(onPressed: _scanning ? null : _scan, icon: const Icon(Icons.refresh), label: const Text('Actualiser')),
            ]),
            if (_devices.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Aucune imprimante trouvée. Sur le terminal ZCS, elle s\'appelle « BluetoothPrint » (Paramètres Android > Bluetooth > Appareils enregistrés). Autorisez le Bluetooth puis touchez Actualiser.'),
              ),
            for (final d in _devices)
              Card(
                color: d.macAdress == _s.printerMac ? Theme.of(context).colorScheme.primaryContainer : null,
                child: ListTile(
                  leading: Icon(d.macAdress == _s.printerMac ? Icons.check_circle : Icons.print_outlined),
                  title: Text(d.name),
                  subtitle: Text(d.macAdress),
                  onTap: () => setState(() {
                    _s.printerMac = d.macAdress;
                    _s.printerName = d.name;
                  }),
                ),
              ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _s.cols,
              decoration: const InputDecoration(labelText: 'Largeur du ticket'),
              items: const [
                DropdownMenuItem(value: 48, child: Text('80 mm (48 caractères)')),
                DropdownMenuItem(value: 42, child: Text('80 mm, police plus large (42)')),
                DropdownMenuItem(value: 32, child: Text('58 mm (32 caractères)')),
              ],
              onChanged: (v) => setState(() => _s.cols = v ?? 48),
            ),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Supprimer les accents'), subtitle: const Text('À activer si des caractères bizarres apparaissent'), value: _s.stripAccents, onChanged: (v) => setState(() => _s.stripAccents = v)),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Imprimer automatiquement'), subtitle: const Text('Ticket imprimé dès qu\'une vente ou un paiement est enregistré'), value: _s.autoPrint, onChanged: (v) => setState(() => _s.autoPrint = v)),
            const SizedBox(height: 8),
            OutlinedButton.icon(style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)), onPressed: _test, icon: const Icon(Icons.print), label: const Text('Imprimer un ticket de test')),
            _section('Écran client (petit écran du terminal)'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Afficher la vente en cours'),
              subtitle: const Text('Le petit écran montre seulement les articles et le total. Sans effet si le terminal ne le permet pas.'),
              value: _s.customerDisplay,
              onChanged: (v) => setState(() => _s.customerDisplay = v),
            ),
            FutureBuilder<bool>(
              future: CustomerDisplay.available(),
              builder: (_, snap) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  snap.data == true ? 'Second écran détecté sur ce terminal.' : (snap.connectionState == ConnectionState.done ? 'Aucun second écran détecté (normal sur un téléphone).' : ''),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
            _section('Sauvegarde en ligne'),
            const SyncCard(),
            _section('Fonctions'),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Gestion de stock'), subtitle: const Text('Facultatif. Désactivée, le stock n\'apparaît nulle part.'), value: _s.stockEnabled, onChanged: (v) => setState(() => _s.stockEnabled = v)),
            const SizedBox(height: 24),
            FilledButton(style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)), onPressed: _save, child: const Text('Enregistrer')),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('À propos et mentions légales'),
              subtitle: const Text('$kAppName · © 2026 $kOwner'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AboutScreen())),
            ),
          ]),
        ),
      ),
    );
  }
}
