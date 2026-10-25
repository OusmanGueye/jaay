import 'package:flutter/material.dart';

import '../activation.dart';
import '../db.dart';

/// Demandé une seule fois, au premier lancement de l'application.
class ActivationScreen extends StatefulWidget {
  const ActivationScreen({super.key, required this.onActivated});
  final VoidCallback onActivated;

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  final _c = TextEditingController();
  bool _hide = true;
  String? _err;
  int _tries = 0;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (checkActivationCode(_c.text)) {
      final db = await Db.instance;
      await db.setActivated();
      widget.onActivated();
    } else {
      setState(() {
        _tries++;
        _err = _tries >= 3 ? 'Code incorrect. Contactez $kOwner pour obtenir le code.' : 'Code incorrect.';
        _c.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [cs.primary, Color.lerp(cs.primary, Colors.black, 0.45)!],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      CircleAvatar(
                        radius: 34,
                        backgroundColor: cs.primaryContainer,
                        child: Icon(Icons.receipt_long, size: 34, color: cs.onPrimaryContainer),
                      ),
                      const SizedBox(height: 16),
                      Text(kAppName, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      const Text('Entrez le code d\'activation pour commencer.\nIl n\'est demandé qu\'une seule fois.', textAlign: TextAlign.center),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _c,
                        autofocus: true,
                        obscureText: _hide,
                        autocorrect: false,
                        enableSuggestions: false,
                        onSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: 'Code d\'activation',
                          errorText: _err,
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(icon: Icon(_hide ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => _hide = !_hide)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)), onPressed: _submit, child: const Text('Activer')),
                      const SizedBox(height: 16),
                      Text('© 2026 $kOwner · Tous droits réservés', style: Theme.of(context).textTheme.bodySmall),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
