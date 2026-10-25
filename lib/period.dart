import 'package:intl/intl.dart';

enum PeriodKind { today, yesterday, week, month, lastMonth, year, custom }

const kPeriodLabels = {
  PeriodKind.today: 'Aujourd\'hui',
  PeriodKind.yesterday: 'Hier',
  PeriodKind.week: '7 jours',
  PeriodKind.month: 'Ce mois',
  PeriodKind.lastMonth: 'Mois dernier',
  PeriodKind.year: 'Cette année',
  PeriodKind.custom: 'Dates…',
};

/// Période [start, end[ en millisecondes, pour filtrer ventes et encaissements.
class Period {
  Period(this.kind, this.start, this.end);

  final PeriodKind kind;
  final DateTime start;

  /// Exclus : minuit du jour suivant le dernier jour inclus.
  final DateTime end;

  int get startMs => start.millisecondsSinceEpoch;
  int get endMs => end.millisecondsSinceEpoch;

  static DateTime _d(DateTime t) => DateTime(t.year, t.month, t.day);

  static Period of(PeriodKind k, {DateTime? now, DateTime? from, DateTime? to}) {
    final t = _d(now ?? DateTime.now());
    switch (k) {
      case PeriodKind.today:
        return Period(k, t, DateTime(t.year, t.month, t.day + 1));
      case PeriodKind.yesterday:
        return Period(k, DateTime(t.year, t.month, t.day - 1), t);
      case PeriodKind.week:
        return Period(k, DateTime(t.year, t.month, t.day - 6), DateTime(t.year, t.month, t.day + 1));
      case PeriodKind.month:
        return Period(k, DateTime(t.year, t.month, 1), DateTime(t.year, t.month + 1, 1));
      case PeriodKind.lastMonth:
        return Period(k, DateTime(t.year, t.month - 1, 1), DateTime(t.year, t.month, 1));
      case PeriodKind.year:
        return Period(k, DateTime(t.year, 1, 1), DateTime(t.year + 1, 1, 1));
      case PeriodKind.custom:
        final a = _d(from ?? t);
        final b = _d(to ?? a);
        return Period(k, a, DateTime(b.year, b.month, b.day + 1));
    }
  }

  bool get isSingleDay => end.difference(start).inHours <= 25 && end.day != start.day;

  /// Libellé lisible : « Aujourd'hui », « Octobre 2026 », « 01/10 – 15/10/2026 »…
  String get label {
    switch (kind) {
      case PeriodKind.today:
        return 'Aujourd\'hui';
      case PeriodKind.yesterday:
        return 'Hier';
      case PeriodKind.month:
      case PeriodKind.lastMonth:
        final s = DateFormat('MMMM yyyy', 'fr').format(start);
        return s[0].toUpperCase() + s.substring(1);
      case PeriodKind.year:
        return 'Année ${start.year}';
      default:
        final last = DateTime(end.year, end.month, end.day - 1);
        final f = DateFormat('dd/MM/yyyy');
        return start == last ? f.format(start) : '${DateFormat('dd/MM').format(start)} – ${f.format(last)}';
    }
  }
}
