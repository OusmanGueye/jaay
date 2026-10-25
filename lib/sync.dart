import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'app_state.dart';
import 'db.dart';

/// Sauvegarde et synchronisation en ligne (Supabase). L'application marche sans internet :
/// les modifications sont notées localement puis envoyées dès que le réseau revient.
const kSupabaseUrl = 'https://fzksezfjwtkajxkapxni.supabase.co';
const kSupabaseKey = 'sb_publishable_FELrH1_2TtRlT3gOgCdkpg_fC7LHTb0';

class SyncStatus {
  const SyncStatus({this.email, this.lastSync, this.pending = 0, this.running = false, this.error});
  final String? email;
  final int? lastSync;
  final int pending;
  final bool running;
  final String? error;

  bool get loggedIn => email != null;

  SyncStatus copy({String? email, int? lastSync, int? pending, bool? running, String? error, bool clearError = false, bool clearEmail = false}) =>
      SyncStatus(
        email: clearEmail ? null : (email ?? this.email),
        lastSync: lastSync ?? this.lastSync,
        pending: pending ?? this.pending,
        running: running ?? this.running,
        error: clearError ? null : (error ?? this.error),
      );
}

class SyncException implements Exception {
  SyncException(this.message);
  final String message;
  @override
  String toString() => message;
}

class SyncService {
  SyncService._();
  static final SyncService i = SyncService._();

  final ValueNotifier<SyncStatus> status = ValueNotifier(const SyncStatus());
  Timer? _timer;
  Timer? _debounce;
  bool _running = false;
  bool _started = false;

  Map<String, dynamic>? _session; // access_token, refresh_token, expires_at (s), user_id, email

  // ----------------------------------------------------------------- démarrage

  Future<void> start() async {
    if (_started) return;
    _started = true;
    final db = await Db.instance;
    final raw = await db.getSetting('sb_session');
    if (raw != null && raw.isNotEmpty) {
      try {
        _session = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {}
    }
    final last = int.tryParse(await db.getSetting('sync_last') ?? '');
    status.value = SyncStatus(email: _session?['email'] as String?, lastSync: last, pending: await db.pendingCount());
    AppState.i.dataVersion.addListener(_onData);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 90), (_) => kick());
    kick();
  }

  void _onData() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 4), kick);
    _refreshPending();
  }

  Future<void> _refreshPending() async {
    final db = await Db.instance;
    status.value = status.value.copy(pending: await db.pendingCount());
  }

  /// Lance une synchronisation si on est connecté (silencieux en cas d'échec réseau).
  Future<void> kick() async {
    if (_session == null || _running) return;
    try {
      await syncNow();
    } catch (_) {}
  }

  // -------------------------------------------------------------------- compte

  Map<String, String> get _baseHeaders => {'apikey': kSupabaseKey, 'Content-Type': 'application/json'};

  String _errorOf(http.Response r) {
    try {
      final j = jsonDecode(r.body);
      final msg = (j['msg'] ?? j['error_description'] ?? j['message'] ?? j['error'] ?? '').toString();
      final code = (j['error_code'] ?? j['code'] ?? '').toString();
      final l = '$msg $code'.toLowerCase();
      if (l.contains('invalid login') || l.contains('invalid_credentials')) return 'E-mail ou mot de passe incorrect.';
      if (l.contains('not confirmed') || l.contains('email_not_confirmed')) return 'Confirmez d\'abord votre e-mail (lien reçu par e-mail), puis connectez-vous.';
      if (l.contains('already registered') || l.contains('user_already_exists')) return 'Ce compte existe déjà : connectez-vous.';
      if (l.contains('password') && l.contains('characters')) return 'Mot de passe trop court (6 caractères minimum).';
      if (l.contains('rate limit') || r.statusCode == 429) return 'Trop de tentatives, réessayez dans quelques minutes.';
      if (msg.isNotEmpty) return msg;
    } catch (_) {}
    return 'Erreur ${r.statusCode}';
  }

  Future<http.Response> _post(String path, Object body, {Map<String, String>? headers}) async {
    try {
      return await http
          .post(Uri.parse('$kSupabaseUrl$path'), headers: {..._baseHeaders, ...?headers}, body: jsonEncode(body))
          .timeout(const Duration(seconds: 25));
    } on TimeoutException {
      throw SyncException('Pas de connexion internet.');
    } catch (e) {
      throw SyncException('Pas de connexion internet.');
    }
  }

  Future<void> _saveSession(Map<String, dynamic> j) async {
    final user = (j['user'] ?? {}) as Map;
    final expires = j['expires_at'] ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000 + ((j['expires_in'] ?? 3600) as num).toInt());
    _session = {
      'access_token': j['access_token'],
      'refresh_token': j['refresh_token'],
      'expires_at': (expires as num).toInt(),
      'user_id': user['id'] ?? _session?['user_id'],
      'email': user['email'] ?? _session?['email'],
    };
    final db = await Db.instance;
    await db.setSetting('sb_session', jsonEncode(_session));
  }

  /// Crée le compte. Retourne true si on est directement connecté,
  /// false si Supabase demande d'abord de confirmer l'e-mail.
  Future<bool> signUp(String email, String password) async {
    final r = await _post('/auth/v1/signup', {'email': email.trim(), 'password': password});
    if (r.statusCode >= 300) throw SyncException(_errorOf(r));
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    if (j['access_token'] != null) {
      await _saveSession(j);
      await _afterLogin();
      return true;
    }
    return false;
  }

  Future<void> signIn(String email, String password) async {
    final r = await _post('/auth/v1/token?grant_type=password', {'email': email.trim(), 'password': password});
    if (r.statusCode >= 300) throw SyncException(_errorOf(r));
    await _saveSession(jsonDecode(r.body) as Map<String, dynamic>);
    await _afterLogin();
  }

  Future<void> _afterLogin() async {
    final db = await Db.instance;
    status.value = status.value.copy(email: _session!['email'] as String?, clearError: true, pending: await db.pendingCount());
    kick();
  }

  Future<void> signOut() async {
    _session = null;
    final db = await Db.instance;
    await db.deleteSetting('sb_session');
    status.value = SyncStatus(lastSync: status.value.lastSync, pending: await db.pendingCount());
  }

  Future<String> _token() async {
    final s = _session;
    if (s == null) throw SyncException('Non connecté.');
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if ((s['expires_at'] as int) - now > 60) return s['access_token'] as String;
    final r = await _post('/auth/v1/token?grant_type=refresh_token', {'refresh_token': s['refresh_token']});
    if (r.statusCode >= 300) {
      if (r.statusCode == 400 || r.statusCode == 401) {
        await signOut();
        throw SyncException('Session expirée : reconnectez-vous.');
      }
      throw SyncException(_errorOf(r));
    }
    await _saveSession(jsonDecode(r.body) as Map<String, dynamic>);
    return _session!['access_token'] as String;
  }

  Future<Map<String, String>> _authHeaders({Map<String, String>? extra}) async =>
      {..._baseHeaders, 'Authorization': 'Bearer ${await _token()}', ...?extra};

  Future<String> _deviceId(Db db) async {
    var id = await db.getSetting('device_id');
    if (id == null || id.isEmpty) {
      final t = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      id = 'dev-$t-${(DateTime.now().millisecondsSinceEpoch % 9973).toRadixString(36)}';
      await db.setSetting('device_id', id);
    }
    return id;
  }

  // ------------------------------------------------------------- synchronisation

  Future<void> _upsert(String table, String conflict, List<Map<String, Object?>> rows) async {
    final r = await http
        .post(
          Uri.parse('$kSupabaseUrl/rest/v1/$table?on_conflict=$conflict'),
          headers: await _authHeaders(extra: {'Prefer': 'resolution=merge-duplicates,return=minimal'}),
          body: jsonEncode(rows),
        )
        .timeout(const Duration(seconds: 40));
    if (r.statusCode >= 300) throw SyncException(_errorOf(r));
  }

  /// Envoie tout ce qui est en attente. Retourne le nombre d'enregistrements envoyés.
  Future<int> syncNow() async {
    if (_running) return 0;
    _running = true;
    status.value = status.value.copy(running: true, clearError: true);
    var sent = 0;
    try {
      final db = await Db.instance;
      final uid = _session?['user_id'] as String?;
      if (uid == null) throw SyncException('Non connecté.');
      final device = await _deviceId(db);

      while (true) {
        final batch = await db.nextSyncBatch();
        if (batch.records.isEmpty) break;
        final rows = [
          for (final r in batch.records)
            {
              'user_id': uid,
              'device_id': device,
              'tbl': r['tbl'],
              'id': r['id'],
              'data': r['data'],
              'deleted': r['deleted'],
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            }
        ];
        await _upsert('gf_records', 'user_id,device_id,tbl,id', rows);
        await db.ackSync(batch.maxLogId);
        sent += rows.length;
      }

      // Réglages de la boutique (nom, logo, couleur…) : envoyés seulement s'ils ont changé.
      final snap = jsonEncode(await db.settingsSnapshot());
      if (snap != await db.getSetting('sync_settings_pushed')) {
        await _upsert('gf_records', 'user_id,device_id,tbl,id', [
          {'user_id': uid, 'device_id': device, 'tbl': 'settings', 'id': 1, 'data': jsonDecode(snap), 'deleted': false, 'updated_at': DateTime.now().toUtc().toIso8601String()}
        ]);
        await db.setSetting('sync_settings_pushed', snap);
        sent++;
      }

      await _upsert('gf_devices', 'user_id,device_id', [
        {'user_id': uid, 'device_id': device, 'name': 'Terminal', 'app_version': '2.2', 'last_sync': DateTime.now().toUtc().toIso8601String()}
      ]);

      final now = DateTime.now().millisecondsSinceEpoch;
      await db.setSetting('sync_last', now.toString());
      status.value = status.value.copy(running: false, lastSync: now, pending: await db.pendingCount(), clearError: true);
      return sent;
    } on SyncException catch (e) {
      status.value = status.value.copy(running: false, error: e.message);
      rethrow;
    } catch (_) {
      status.value = status.value.copy(running: false, error: 'Pas de connexion internet.');
      throw SyncException('Pas de connexion internet.');
    } finally {
      _running = false;
    }
  }

  // ---------------------------------------------------------------- restauration

  /// Récupère la dernière sauvegarde du compte. Seulement sur un appareil encore vide.
  /// Retourne le nombre d'enregistrements restaurés.
  Future<int> restore() async {
    final db = await Db.instance;
    if (!await db.isLocalEmpty()) {
      throw SyncException('Cet appareil contient déjà des données : restauration impossible.');
    }
    try {
      final dr = await http
          .get(Uri.parse('$kSupabaseUrl/rest/v1/gf_devices?select=device_id,last_sync&order=last_sync.desc&limit=1'), headers: await _authHeaders())
          .timeout(const Duration(seconds: 25));
      if (dr.statusCode >= 300) throw SyncException(_errorOf(dr));
      final devs = jsonDecode(dr.body) as List;
      if (devs.isEmpty) throw SyncException('Aucune sauvegarde trouvée sur ce compte.');
      final device = devs.first['device_id'] as String;

      final records = <Map<String, Object?>>[];
      Map<String, String>? settings;
      var offset = 0;
      while (true) {
        final r = await http
            .get(
              Uri.parse('$kSupabaseUrl/rest/v1/gf_records?select=tbl,id,data,deleted&device_id=eq.${Uri.encodeQueryComponent(device)}&order=tbl,id&limit=1000&offset=$offset'),
              headers: await _authHeaders(),
            )
            .timeout(const Duration(seconds: 60));
        if (r.statusCode >= 300) throw SyncException(_errorOf(r));
        final page = (jsonDecode(r.body) as List).cast<Map<String, dynamic>>();
        for (final e in page) {
          if (e['tbl'] == 'settings') {
            if (e['data'] is Map) settings = {for (final x in (e['data'] as Map).entries) x.key.toString(): x.value.toString()};
          } else {
            records.add(Map<String, Object?>.from(e));
          }
        }
        if (page.length < 1000) break;
        offset += 1000;
      }
      await db.restoreRecords(records, settings);
      await db.setSetting('device_id', device); // cet appareil reprend l'identité sauvegardée
      await AppState.i.load();
      AppState.i.touch();
      await _refreshPending();
      return records.where((r) => r['deleted'] != true).length;
    } on SyncException {
      rethrow;
    } catch (_) {
      throw SyncException('Pas de connexion internet.');
    }
  }
}
