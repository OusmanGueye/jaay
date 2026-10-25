import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

/// Lit un QR code / code-barres avec la caméra. Retourne le texte lu.
/// En secours, on peut aussi taper le numéro à la main.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key, this.title = 'Scanner un code'});
  final String title;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> with WidgetsBindingObserver {
  MobileScannerController? _controller;
  final _manual = TextEditingController();
  PermissionStatus? _perm;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _askPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _manual.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Retour depuis les réglages Android : on revérifie l'autorisation.
    if (state == AppLifecycleState.resumed && _perm != PermissionStatus.granted) _askPermission();
  }

  Future<void> _askPermission() async {
    var st = await Permission.camera.status;
    if (!st.isGranted) st = await Permission.camera.request();
    if (!mounted) return;
    setState(() {
      _perm = st;
      if (st.isGranted && _controller == null) {
        _controller = MobileScannerController(
          facing: CameraFacing.back,
          formats: const [
            BarcodeFormat.qrCode,
            BarcodeFormat.ean13,
            BarcodeFormat.ean8,
            BarcodeFormat.code128,
            BarcodeFormat.code39,
            BarcodeFormat.upcA,
          ],
        );
      }
    });
  }

  void _finish(String v) {
    if (_done || v.trim().isEmpty) return;
    _done = true;
    Navigator.of(context).pop(v.trim());
  }

  Widget _problem(String title, String detail, {Widget? action}) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.no_photography_outlined, size: 48),
            const SizedBox(height: 12),
            Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(detail, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 16), action],
          ]),
        ),
      );

  Widget _camera() {
    final p = _perm;
    if (p == null) return const Center(child: CircularProgressIndicator());
    if (!p.isGranted) {
      final forever = p.isPermanentlyDenied || p.isRestricted;
      return _problem(
        'Caméra non autorisée',
        forever
            ? 'Ouvrez les réglages de l\'application, choisissez Autorisations, puis Caméra, et autorisez-la.'
            : 'L\'application a besoin de la caméra pour lire les QR codes.',
        action: FilledButton.icon(
          onPressed: forever ? openAppSettings : _askPermission,
          icon: Icon(forever ? Icons.settings : Icons.camera_alt),
          label: Text(forever ? 'Ouvrir les réglages' : 'Autoriser la caméra'),
        ),
      );
    }
    final c = _controller;
    if (c == null) return const Center(child: CircularProgressIndicator());
    return MobileScanner(
      controller: c,
      onDetect: (capture) {
        for (final b in capture.barcodes) {
          final v = b.rawValue;
          if (v != null) {
            _finish(v);
            break;
          }
        }
      },
      errorBuilder: (context, error) => _problem(
        'Caméra indisponible',
        '${error.errorCode.name}${error.errorDetails?.message != null ? '\n${error.errorDetails!.message}' : ''}\n\nTapez le numéro de la facture ci-dessous.',
        action: OutlinedButton.icon(
          onPressed: () {
            setState(() {
              _controller?.dispose();
              _controller = null;
            });
            _askPermission();
          },
          icon: const Icon(Icons.refresh),
          label: const Text('Réessayer'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title), actions: [
        if (_controller != null)
          IconButton(tooltip: 'Lampe', icon: const Icon(Icons.flashlight_on_outlined), onPressed: () => _controller?.toggleTorch()),
      ]),
      body: Column(children: [
        Expanded(child: _camera()),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _manual,
                  decoration: const InputDecoration(labelText: 'Ou saisir le numéro (ex : F-000123)', isDense: true),
                  onSubmitted: _finish,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: () => _finish(_manual.text), child: const Text('OK')),
            ]),
          ),
        ),
      ]),
    );
  }
}
