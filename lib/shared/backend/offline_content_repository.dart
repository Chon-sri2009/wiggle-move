import 'content_models.dart';
import 'content_repository.dart';
import 'demo_content.dart';
import 'trainer_data.dart';

/// Built-in content for `--dart-define=WM_OFFLINE=true`.
class OfflineContentRepository implements ContentRepository {
  const OfflineContentRepository();

  @override
  Future<List<Trainer>> fetchTrainers() async => [
    ...builtInTrainers,
    demoTrainer,
  ];
}
