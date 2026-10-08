import 'package:litert_hackathon/data/services/model_store/store_operation.dart';
import 'package:litert_hackathon/domain/models/provisioning.dart';

/// A [FileStateReporter] that keeps every update, marked as reported at once
/// or as progress, in order.
final class RecordingReporter implements FileStateReporter {
  final List<StoreFileState> reported = [];
  final List<StoreFileState> progressed = [];

  /// Every update in order: `('report', state)` or `('progress', state)`.
  final List<(String, StoreFileState)> all = [];

  @override
  void report(StoreFileState state) {
    reported.add(state);
    all.add(('report', state));
  }

  @override
  void progress(StoreFileState state) {
    progressed.add(state);
    all.add(('progress', state));
  }
}
