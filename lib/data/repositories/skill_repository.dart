import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/models/skill_catalog.dart';
import '../services/skills/skill_store_service.dart';

/// The runtime skills (D12, wiring §4), app-scoped: seeds the skills
/// directory from the bundle once, then holds the latest scan. Demo 1 opens
/// its chat with [catalog]'s skills and re-opens it when a later scan
/// changes them ([SkillCatalog.fingerprint]).
///
/// Rescans run on Reload (the Skills sheet) and on app resume, never on a
/// timer: a scan reads every file.
class SkillRepository {
  SkillRepository({required this._store});

  final SkillStoreService _store;

  final ValueNotifier<SkillCatalog?> _catalog = ValueNotifier(null);
  Future<SkillCatalog>? _scanning;
  bool _seeded = false;
  bool _disposed = false;

  /// The latest scan; null before the first one finished. Replaced only
  /// when the files changed (or the directory became (un)available).
  ValueListenable<SkillCatalog?> get catalog => _catalog;

  /// The latest scan, scanning (and seeding) first if there is none yet.
  @visibleForTesting
  Future<SkillCatalog> ensureLoaded() async =>
      _catalog.value ?? await refresh();

  /// Seeds once per launch, then rescans. Concurrent calls share one run.
  /// Never fails: an unusable directory is a catalog with a
  /// [SkillCatalog.storeError].
  Future<SkillCatalog> refresh() =>
      _scanning ??= _refresh().whenComplete(() => _scanning = null);

  Future<SkillCatalog> _refresh() async {
    if (!_seeded) {
      try {
        await _store.seed();
        _seeded = true;
      } catch (e, st) {
        // The scan below reports the directory problem; a seed that failed
        // for another reason is retried on the next refresh.
        debugPrint('[Skills] seeding failed: $e\n$st');
      }
    }
    final scanned = await _store.scan();
    final current = _catalog.value;
    if (_disposed) return scanned;
    if (current != null &&
        current.fingerprint == scanned.fingerprint &&
        current.storeError == scanned.storeError &&
        current.directory == scanned.directory) {
      return current;
    }
    _catalog.value = scanned;
    return scanned;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _catalog.dispose();
  }
}
