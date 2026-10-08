import 'package:flutter/foundation.dart';
import 'package:litert_hackathon/data/repositories/provisioning_repository.dart';
import 'package:litert_hackathon/domain/models/model_id.dart';
import 'package:litert_hackathon/domain/models/provisioning.dart';

/// [ProvisioningRepository] for widget tests: every model present (built
/// in, the chat model by `GEMMA_MODEL_PATH`) unless [presence] says
/// otherwise. No disk.
class FakeProvisioningRepository implements ProvisioningRepository {
  FakeProvisioningRepository({Map<ModelId, ModelPresence>? presence})
    : presence = presence ?? {};

  /// Overrides per model; the rest are present.
  final Map<ModelId, ModelPresence> presence;
  final ValueNotifier<bool> busyNotifier = ValueNotifier(false);

  @override
  ValueListenable<bool> get busy => busyNotifier;

  @override
  ModelPresence presenceOf(ModelId id) =>
      presence[id] ??
      (id == ModelId.chat
          ? const PresentByDefine('GEMMA_MODEL_PATH', '/store/chat/model')
          : const PresentBundled());

  @override
  bool get requiredPresent => ModelId.values
      .where((id) => id.spec.required)
      .every((id) => ProvisioningRepository.isPresent(presenceOf(id)));

  int prunes = 0;

  @override
  Future<List<String>> pruneOldModelFolders() async {
    prunes++;
    return const [];
  }
}
