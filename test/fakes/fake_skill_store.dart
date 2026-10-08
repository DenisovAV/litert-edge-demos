import 'package:litert_hackathon/config/model_catalog.dart'
    show kMaxSkillTokens;
import 'package:litert_hackathon/data/services/skills/skill_store_service.dart';
import 'package:litert_hackathon/domain/models/skill_catalog.dart';

/// [SkillStoreService] without a disk: seeding does nothing and every scan
/// finds [catalog] (by default an empty skills folder). Wrap it in a
/// `SkillRepository` for a chat opened without skills.
final class FakeSkillStore implements SkillStoreService {
  FakeSkillStore({this.catalog = emptyCatalog});

  static const emptyCatalog = SkillCatalog(
    directory: '/fake/skills',
    fingerprint: 'empty',
  );

  /// What every scan returns.
  SkillCatalog catalog;

  @override
  int get maxBytes => 4 * 1024;

  @override
  int get maxTokens => kMaxSkillTokens;

  @override
  Future<SeedReport> seed() async =>
      const SeedReport(created: [], updated: [], keptEdits: [], skipped: true);

  @override
  Future<SkillCatalog> scan() async => catalog;
}
