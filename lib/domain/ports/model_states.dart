// A port: an interface that the domain and the view models depend on and an
// outer layer implements. Every port lives in lib/domain/ports/;
// function-typed dependencies stay next to their one consumer.

import 'package:flutter/foundation.dart' show ValueListenable;

import '../models/model_id.dart';
import '../models/model_state.dart';

/// What the screens may read about the models: each one's state, whether a
/// setup run goes, and whether every required model is ready.
/// `ModelRepository` implements it; the screens get this read-only view, and
/// what changes the models (setup, reloads) is wired to them explicitly.
abstract interface class ModelStates {
  /// One entry per model; replaced (never mutated) on every change.
  ValueListenable<Map<ModelId, ModelState>> get states;

  /// True while a setup run goes.
  ValueListenable<bool> get preparing;

  /// True when every required model is [ModelReady]; optional ones may have
  /// failed or be unavailable.
  bool get requiredReady;
}
