/// Whether flutter_edge_ai would accept `PreferredBackend.npu` on this
/// device.
sealed class const NpuAvailability();

/// The NPU dispatch stack ships here and (Android) the device's Qualcomm
/// FastRPC library opens. Necessary, not sufficient: the model must also be
/// compiled for this SoC, which only a load can tell. [soc] is the SoC the
/// OS names (Android `ro.soc.model`), when it names one.
final class const NpuAvailable({final String? soc}) extends NpuAvailability;

/// flutter_edge_ai drops `npu` from its candidates here (so a request would
/// run on the GPU or CPU); [reason] is its own wording.
final class const NpuUnavailable(final String reason, {final String? soc})
    extends NpuAvailability;

/// `available (SoC SM8650)` or `unavailable: <reason>`.
String describeNpu(NpuAvailability npu) => switch (npu) {
  NpuAvailable(:final soc) =>
    'available${soc == null ? '' : ' (SoC $soc)'}: the model must be '
        'compiled for this SoC',
  NpuUnavailable(:final reason, :final soc) =>
    'unavailable: $reason${soc == null ? '' : ' (SoC $soc)'}',
};
