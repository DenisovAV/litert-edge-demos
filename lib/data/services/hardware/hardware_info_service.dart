import 'dart:io' show Platform;

import '../../../domain/models/hardware_profile.dart';
import 'android_hardware_info_service.dart';
import 'linux_hardware_info_service.dart';
import 'macos_hardware_info_service.dart';

/// Probes what the device is (docs/design/hardware-visibility.md §2). One
/// implementation per platform; tests use a fake.
abstract interface class HardwareInfoService {
  /// Never throws for a missing fact: it is left null and explained in
  /// [HardwareProfile.notes]. Throws only on a bug.
  Future<HardwareProfile> probe();
}

/// The service for the running platform. iOS (the Metal device over a
/// MethodChannel) is phase 2: until then it gets the OS and core count only,
/// and says so.
HardwareInfoService hardwareInfoServiceForPlatform() =>
    switch (HostPlatform.fromOperatingSystem(Platform.operatingSystem)) {
      HostPlatform.linux => LinuxHardwareInfoService(),
      HostPlatform.macos => MacHardwareInfoService(),
      HostPlatform.android => AndroidHardwareInfoService(),
      final other => BasicHardwareInfoService(other),
    };

/// OS and core count from `dart:io`; no chip, GPU or RAM yet.
final class BasicHardwareInfoService implements HardwareInfoService {
  const BasicHardwareInfoService(this._platform);

  final HostPlatform _platform;

  @override
  Future<HardwareProfile> probe() async => HardwareProfile(
    platform: _platform,
    os: '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    cpu: CpuInfo(model: 'unknown', cores: Platform.numberOfProcessors),
    notes: [
      'The ${_platform.name} hardware probe (chip, GPU, RAM) is not '
          'implemented yet (phase 2).',
    ],
  );
}
