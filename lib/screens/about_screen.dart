import 'package:flutter/material.dart';

import '../activation.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('À propos et mentions légales')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(padding: const EdgeInsets.all(20), children: [
            Center(child: CircleAvatar(radius: 36, backgroundColor: t.colorScheme.primaryContainer, child: Icon(Icons.receipt_long, size: 36, color: t.colorScheme.onPrimaryContainer))),
            const SizedBox(height: 12),
            Center(child: Text(kAppName, style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold))),
            const Center(child: Text('Version 2.4')),
            const SizedBox(height: 20),
            Text('Éditeur', style: t.textTheme.titleSmall),
            const Text(kOwner),
            const SizedBox(height: 16),
            Text('Mentions légales', style: t.textTheme.titleSmall),
            const SizedBox(height: 4),
            const Text(kLegal),
          ]),
        ),
      ),
    );
  }
}
