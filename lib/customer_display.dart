import 'package:flutter/services.dart';

import 'app_state.dart';
import 'format.dart';
import 'models.dart';

/// Petit écran client du terminal : montre uniquement la vente en cours.
/// Sans effet si le terminal n'a pas de second écran accessible.
class CustomerDisplay {
  static const _ch = MethodChannel('gueye/customer_display');
  static bool _attached = false;

  static void attach() {
    if (_attached) return;
    _attached = true;
    AppState.i.cart.addListener(update);
    AppState.i.addListener(update);
    update();
  }

  static Future<bool> available() async {
    try {
      return (await _ch.invokeMethod<bool>('available')) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> update() async {
    try {
      final s = AppState.i.settings;
      if (!s.customerDisplay) {
        await _ch.invokeMethod('hide');
        return;
      }
      final c = AppState.i.cart;
      final last = c.lines.length > 4 ? c.lines.sublist(c.lines.length - 4) : c.lines;
      await _ch.invokeMethod('show', {
        'shop': s.shopName,
        'footer': s.footer,
        'total': fcfa(c.total),
        'lines': [
          for (final l in last)
            {'name': l.name, 'detail': qtyLine(l.qty, l.unit, l.unitPrice), 'total': fcfa(l.total)},
        ],
      });
    } catch (_) {}
  }
}
