import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'activation.dart';
import 'app_state.dart';
import 'customer_display.dart';
import 'db.dart';
import 'screens/activation_screen.dart';
import 'screens/shell.dart';
import 'sync.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr');
  await AppState.i.load();
  final activated = await (await Db.instance).isActivated();
  CustomerDisplay.attach();
  SyncService.i.start();
  runApp(GueyeApp(activated: activated));
}

ThemeData _theme(Color seed, Brightness b) {
  final cs = ColorScheme.fromSeed(seedColor: seed, brightness: b);
  final r14 = BorderRadius.circular(14);
  OutlineInputBorder ob([Color? c, double w = 0]) => OutlineInputBorder(
        borderRadius: r14,
        borderSide: c == null ? BorderSide.none : BorderSide(color: c, width: w),
      );
  return ThemeData(
    colorScheme: cs,
    useMaterial3: true,
    scaffoldBackgroundColor: cs.surface,
    visualDensity: VisualDensity.standard,
    cardTheme: CardThemeData(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: cs.surface,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: cs.onSurface),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.55),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: ob(),
      enabledBorder: ob(),
      focusedBorder: ob(cs.primary, 2),
      errorBorder: ob(cs.error, 1.5),
      focusedErrorBorder: ob(cs.error, 2),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 50),
        shape: RoundedRectangleBorder(borderRadius: r14),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 50),
        shape: RoundedRectangleBorder(borderRadius: r14),
        side: BorderSide(color: cs.outlineVariant),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: r14)),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      side: BorderSide(color: cs.outlineVariant),
    ),
    dialogTheme: DialogThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      backgroundColor: cs.surfaceContainer,
      indicatorColor: cs.primaryContainer,
      labelTextStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: cs.surfaceContainer,
      indicatorColor: cs.primaryContainer,
    ),
    listTileTheme: ListTileThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
    dividerTheme: DividerThemeData(color: cs.outlineVariant.withValues(alpha: 0.5), space: 1),
  );
}

class GueyeApp extends StatefulWidget {
  const GueyeApp({super.key, required this.activated});
  final bool activated;

  @override
  State<GueyeApp> createState() => _GueyeAppState();
}

class _GueyeAppState extends State<GueyeApp> with WidgetsBindingObserver {
  late bool _activated = widget.activated;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Retour dans l'application : on envoie ce qui est en attente.
    if (state == AppLifecycleState.resumed) SyncService.i.kick();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.i,
      builder: (context, _) {
        final s = AppState.i.settings;
        final seed = Color(s.colorValue);
        return MaterialApp(
          title: kAppName,
          debugShowCheckedModeBanner: false,
          locale: const Locale('fr'),
          supportedLocales: const [Locale('fr')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: _theme(seed, Brightness.light),
          darkTheme: _theme(seed, Brightness.dark),
          themeMode: switch (s.themeMode) {
            'light' => ThemeMode.light,
            'dark' => ThemeMode.dark,
            _ => ThemeMode.system,
          },
          // Évite que de gros réglages de police Android cassent les écrans.
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: MediaQuery.textScalerOf(context).clamp(minScaleFactor: 0.9, maxScaleFactor: 1.15),
            ),
            child: child!,
          ),
          home: _activated ? const Shell() : ActivationScreen(onActivated: () => setState(() => _activated = true)),
        );
      },
    );
  }
}
