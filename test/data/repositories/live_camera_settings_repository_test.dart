import 'package:flutter_test/flutter_test.dart';
import 'package:litert_hackathon/config/live_camera_config.dart';
import 'package:litert_hackathon/data/repositories/live_camera_settings_repository.dart';
import 'package:litert_hackathon/data/services/settings/typed_settings.dart';
import 'package:litert_hackathon/domain/models/camera_source.dart';
import 'package:litert_hackathon/domain/models/detection.dart';
import 'package:litert_hackathon/domain/models/detector_choice.dart';
import 'package:litert_hackathon/domain/models/frame_source_spec.dart';
import 'package:litert_hackathon/utils/result.dart';

import '../../fakes/fake_settings_store.dart';

const _userChoice = Result<FrameSourceSpec>.ok(CameraSourceSpec());
const _phone = 'http://192.168.1.23:8080/video';

void main() {
  late InMemorySettingsStore store;

  setUp(() => store = InMemorySettingsStore());

  LiveCameraSettingsRepository repo({
    Result<FrameSourceSpec> environment = _userChoice,
    String backendDefine = '',
  }) => LiveCameraSettingsRepository(
    settings: TypedSettings(store: store),
    environment: environment,
    backendDefine: backendDefine,
  );

  group('camera source', () {
    test('nothing saved: the device camera, the example URL', () async {
      final r = repo();
      expect(r.sourceLock, isNull);
      expect(
        (await r.readSource() as Ok<CameraSourceChoice>).value,
        CameraSourceChoice.standard,
      );
      expect(
        (await r.resolveSource() as Ok<FrameSourceSpec>).value,
        isA<CameraSourceSpec>(),
      );
    });

    test('a saved network camera persists and resolves to its URL', () async {
      final r = repo();
      const choice = CameraSourceChoice(
        kind: CameraSourceKind.network,
        networkUrl: ' $_phone ',
      );
      expect(await r.saveSource(choice), isA<Ok<void>>());
      expect(store.values, {
        'camera.source': 'network',
        'camera.networkUrl': _phone,
      });

      // A new repository (the next launch) reads it back.
      final again = repo();
      expect(
        (await again.readSource() as Ok<CameraSourceChoice>).value,
        const CameraSourceChoice(
          kind: CameraSourceKind.network,
          networkUrl: _phone,
        ),
      );
      final spec = (await again.resolveSource() as Ok<FrameSourceSpec>).value;
      expect((spec as NetworkSourceSpec).url, Uri.parse(_phone));
    });

    test('switching back to the device camera keeps the URL', () async {
      final r = repo();
      await r.saveSource(
        const CameraSourceChoice(
          kind: CameraSourceKind.network,
          networkUrl: _phone,
        ),
      );
      await r.saveSource(
        const CameraSourceChoice(
          kind: CameraSourceKind.device,
          networkUrl: _phone,
        ),
      );
      expect(store.values['camera.networkUrl'], _phone);
      expect(
        (await r.resolveSource() as Ok<FrameSourceSpec>).value,
        isA<CameraSourceSpec>(),
      );
    });

    test('the network choice cannot be saved: the URL is put back, the '
        'device camera stays (never a half-written pair)', () async {
      final r = repo();
      store.values['camera.networkUrl'] = 'http://old.example:8080/video';
      store.failWritesOf.add('camera.source');

      final saved = await r.saveSource(
        const CameraSourceChoice(
          kind: CameraSourceKind.network,
          networkUrl: _phone,
        ),
      );

      expect(saved, isA<Error<void>>());
      expect(store.values, {
        'camera.networkUrl': 'http://old.example:8080/video',
      });
    });

    test('the device choice: the choice goes first, and a URL that cannot '
        'be saved puts the network camera back', () async {
      final r = repo();
      await r.saveSource(
        const CameraSourceChoice(
          kind: CameraSourceKind.network,
          networkUrl: _phone,
        ),
      );
      store.failWritesOf.add('camera.networkUrl');

      final saved = await r.saveSource(
        const CameraSourceChoice(
          kind: CameraSourceKind.device,
          networkUrl: 'not a url',
        ),
      );

      expect(saved, isA<Error<void>>());
      expect(store.values, {
        'camera.networkUrl': _phone,
        'camera.source': 'network',
      });
      final spec = (await r.resolveSource() as Ok<FrameSourceSpec>).value;
      expect((spec as NetworkSourceSpec).url, Uri.parse(_phone));
    });

    test('a network choice with the placeholder URL is refused and nothing '
        'is written', () async {
      final r = repo();
      final saved = await r.saveSource(
        const CameraSourceChoice(kind: CameraSourceKind.network),
      );
      expect((saved as Error<void>).error, isA<InvalidCameraUrlException>());
      expect(store.values, isEmpty);
    });

    test('FRAME_SOURCE=fixture (or a test source) wins and locks it', () async {
      await store.setString('camera.source', 'network');
      await store.setString('camera.networkUrl', _phone);
      final r = repo(
        environment: const Result.ok(FixtureSourceSpec(['/fixtures'])),
      );
      expect(r.sourceLock, 'FRAME_SOURCE=fixture');
      expect(
        (await r.resolveSource() as Ok<FrameSourceSpec>).value,
        isA<FixtureSourceSpec>(),
      );
    });

    test('a foreign saved value or a storage failure is an error, never a '
        'silent device camera', () async {
      await store.setString('camera.source', 'webcam');
      expect(
        (await repo().resolveSource() as Error<FrameSourceSpec>).error,
        isA<InvalidCameraSettingException>(),
      );
      store.failWith = Exception('disk');
      expect(await repo().readSource(), isA<Error<CameraSourceChoice>>());
    });
  });

  group('detector backend', () {
    test('nothing saved: the GPU', () async {
      final choice =
          (await repo().readBackend() as Ok<DetectorBackendChoice>).value;
      expect(choice.backend, DetectorBackend.gpu);
      expect(choice.source, DetectorChoiceSource.standard);
    });

    test('the saved choice persists', () async {
      expect(await repo().saveBackend(DetectorBackend.cpu), isA<Ok<void>>());
      final choice =
          (await repo().readBackend() as Ok<DetectorBackendChoice>).value;
      expect(choice.backend, DetectorBackend.cpu);
      expect(choice.source, DetectorChoiceSource.setting);
    });

    test('DETECTOR_BACKEND wins over the setting and locks it', () async {
      await repo().saveBackend(DetectorBackend.cpu);
      final locked = repo(backendDefine: 'gpu');
      expect(locked.backendLock, 'DETECTOR_BACKEND=gpu');
      final choice =
          (await locked.readBackend() as Ok<DetectorBackendChoice>).value;
      expect(choice.backend, DetectorBackend.gpu);
      expect(choice.source, DetectorChoiceSource.define);
      expect(await locked.saveBackend(DetectorBackend.cpu), isA<Error<void>>());
    });

    test('a bad define is its own error (the build is wrong)', () async {
      expect(
        (await repo(backendDefine: 'npu').readBackend()
                as Error<DetectorBackendChoice>)
            .error,
        isA<InvalidDetectorBackendDefineException>(),
      );
    });

    test('an unreadable setting is an error', () async {
      store.failWith = Exception('disk');
      expect(
        (await repo().readBackend() as Error<DetectorBackendChoice>).error,
        isA<InvalidDetectorSettingException>(),
      );
    });
  });

  group('frameSourceFromEnvironment', () {
    test('network needs a URL, and a usable one', () {
      expect(
        (frameSourceFromEnvironment(
          source: 'network',
          networkUrl: '',
        ) as Error<FrameSourceSpec>).error.toString(),
        contains('NETWORK_CAMERA_URL'),
      );
      final spec = (frameSourceFromEnvironment(
        source: 'network',
        networkUrl: _phone,
      ) as Ok<FrameSourceSpec>).value;
      expect((spec as NetworkSourceSpec).url.host, '192.168.1.23');
      expect(
        repo(environment: Result.ok(spec)).sourceLock,
        'FRAME_SOURCE=network (Network camera · 192.168.1.23:8080)',
      );
    });

    test('camera is the user choice; unknown values name the options', () {
      expect(
        (frameSourceFromEnvironment(
          source: 'camera',
        ) as Ok<FrameSourceSpec>).value,
        isA<CameraSourceSpec>(),
      );
      expect(
        (frameSourceFromEnvironment(source: 'usb') as Error<FrameSourceSpec>)
            .error
            .toString(),
        contains('camera, fixture or network'),
      );
    });
  });
}
