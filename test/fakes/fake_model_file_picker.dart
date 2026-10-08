import 'package:litert_hackathon/domain/ports/model_file_picker.dart';

/// [ModelFilePicker] that returns what the test set.
final class FakeModelFilePicker implements ModelFilePicker {
  FakeModelFilePicker({
    this.support = const ImportFromFolder(),
    this.temporaryCopies,
    this.modelFile,
  });

  @override
  ImportSupport support;
  String? temporaryCopies;

  /// What [pickModelFile] returns (null: cancelled).
  String? modelFile;
  int picks = 0;

  /// When set, every pick throws it (a picker that cannot open).
  Exception? error;

  @override
  Future<String?> pickModelFile() async {
    picks++;
    if (error case final e?) throw e;
    return modelFile;
  }

  @override
  Future<String?> temporaryCopiesDirectory() async => temporaryCopies;
}
