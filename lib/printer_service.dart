import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import 'models.dart';

class PrinterService {
  /// Imprimantes Bluetooth déjà appairées dans les réglages Android.
  static Future<List<BluetoothInfo>> pairedPrinters() async {
    await _askPermissions();
    return PrintBluetoothThermal.pairedBluetooths;
  }

  static Future<void> _askPermissions() async {
    await [Permission.bluetoothConnect, Permission.bluetoothScan].request();
  }

  /// Envoie [bytes] à l'imprimante choisie dans les réglages.
  /// Retourne null si tout va bien, sinon un message d'erreur lisible.
  static Future<String?> printBytes(AppSettings s, List<int> bytes) async {
    if (!s.hasPrinter) {
      return 'Aucune imprimante choisie. Ouvrez Réglages (icône imprimante).';
    }
    try {
      await _askPermissions();
      if (!await PrintBluetoothThermal.bluetoothEnabled) {
        return 'Le Bluetooth est désactivé.';
      }
      if (!await PrintBluetoothThermal.connectionStatus) {
        final ok = await PrintBluetoothThermal.connect(macPrinterAddress: s.printerMac!);
        if (!ok) {
          return 'Connexion à l\'imprimante impossible. Vérifiez qu\'elle est bien appairée.';
        }
      }
      final sent = await PrintBluetoothThermal.writeBytes(bytes);
      return sent ? null : 'L\'impression a échoué (papier, couvercle ?).';
    } catch (e) {
      return 'Erreur d\'impression : $e';
    }
  }
}
