import 'package:flutter/material.dart';

import '../format.dart';
import '../sync.dart';
import '../ui.dart';

/// Section « Sauvegarde en ligne » des réglages.
class SyncCard extends StatefulWidget {
  const SyncCard({super.key});

  @override
  State<SyncCard> createState() => _SyncCardState();
}

class _SyncCardState extends State<SyncCard> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  bool _hide = true;
  String? _msg;
  bool _msgOk = false;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _run(Future<String?> Function() job) async {
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      final ok = await job();
      if (mounted) setState(() { _msg = ok; _msgOk = true; });
    } on SyncException catch (e) {
      if (mounted) setState(() { _msg = e.message; _msgOk = false; });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool get _valid => _email.text.contains('@') && _pass.text.length >= 6;

  @override
  Widget build(BuildContext context) {
    final svc = SyncService.i;
    final cs = Theme.of(context).colorScheme;
    return ValueListenableBuilder<SyncStatus>(
      valueListenable: svc.status,
      builder: (context, st, _) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(st.loggedIn ? Icons.cloud_done_outlined : Icons.cloud_off_outlined, color: st.loggedIn ? cs.primary : cs.outline),
                const SizedBox(width: 10),
                Expanded(child: Text(st.loggedIn ? 'Sauvegarde automatique activée' : 'Sauvegarde en ligne', style: const TextStyle(fontWeight: FontWeight.w700))),
              ]),
              const SizedBox(height: 8),
              if (!st.loggedIn) ...[
                const Text('Vos ventes, clients et produits sont copiés en ligne dès qu\'il y a internet. L\'application continue de marcher sans connexion.'),
                const SizedBox(height: 12),
                TextField(controller: _email, keyboardType: TextInputType.emailAddress, autocorrect: false, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'E-mail', prefixIcon: Icon(Icons.mail_outline))),
                const SizedBox(height: 12),
                TextField(
                  controller: _pass,
                  obscureText: _hide,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(labelText: 'Mot de passe (6 caractères minimum)', prefixIcon: const Icon(Icons.lock_outline), suffixIcon: IconButton(icon: Icon(_hide ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => _hide = !_hide))),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy || !_valid ? null : () => _run(() async {
                        await svc.signIn(_email.text, _pass.text);
                        return 'Connecté. Première sauvegarde en cours…';
                      }),
                      child: const Text('Se connecter'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy || !_valid ? null : () => _run(() async {
                        final direct = await svc.signUp(_email.text, _pass.text);
                        return direct ? 'Compte créé et connecté.' : 'Compte créé. Ouvrez le lien reçu par e-mail pour le confirmer, puis touchez « Se connecter ».';
                      }),
                      child: const Text('Créer un compte'),
                    ),
                  ),
                ]),
              ] else ...[
                Text(st.email ?? ''),
                const SizedBox(height: 4),
                Text(
                  st.running
                      ? 'Synchronisation en cours…'
                      : (st.pending > 0 ? '${st.pending} élément${st.pending > 1 ? 's' : ''} en attente d\'envoi' : (st.lastSync == null ? 'Rien envoyé pour le moment' : 'Tout est sauvegardé · ${fmtDateTime(st.lastSync!)}')),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton.tonalIcon(
                    onPressed: _busy || st.running ? null : () => _run(() async {
                      final n = await svc.syncNow();
                      return n == 0 ? 'Déjà à jour.' : '$n élément${n > 1 ? 's' : ''} sauvegardé${n > 1 ? 's' : ''}.';
                    }),
                    icon: const Icon(Icons.sync),
                    label: const Text('Synchroniser'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () async {
                      final ok = await confirm(context, 'Restaurer la sauvegarde ?', 'À utiliser sur un appareil neuf : les données en ligne sont recopiées ici. Impossible si cet appareil contient déjà des ventes, clients ou produits.', ok: 'Restaurer');
                      if (!ok) return;
                      await _run(() async {
                        final n = await svc.restore();
                        return '$n élément${n > 1 ? 's' : ''} restauré${n > 1 ? 's' : ''}.';
                      });
                    },
                    icon: const Icon(Icons.cloud_download_outlined),
                    label: const Text('Restaurer'),
                  ),
                  TextButton(onPressed: _busy ? null : () => svc.signOut(), child: const Text('Se déconnecter')),
                ]),
              ],
              if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
              if (_msg != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_msg!, style: TextStyle(color: _msgOk ? cs.primary : cs.error, fontWeight: FontWeight.w600))),
              if (st.error != null && _msg == null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(st.error!, style: TextStyle(color: cs.error))),
            ]),
          ),
        );
      },
    );
  }
}
