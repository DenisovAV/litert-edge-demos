/// Where a model really runs, and how sure we are
/// (docs/design/hardware-visibility.md §1). Rule 2: anything not confirmed
/// is labelled [EvidenceSource.inferred] or [EvidenceSource.requested],
/// never shown as a plain fact.
library;

/// How a fact about a model's accelerator is known.
enum EvidenceSource {
  /// A native log line printed during that model's load.
  log('confirmed: native log'),

  /// The runtime's API (`activeBackend`; the detector's strict accelerator
  /// set plus `isFullyAccelerated`).
  api('confirmed: API'),

  /// Deduced from the platform and the hardware probe.
  inferred('inferred'),

  /// What the app asked for; the runtime cannot report what it did.
  requested('requested');

  const EvidenceSource(this.label);

  /// `confirmed: API`, `inferred`, …
  final String label;

  bool get confirmed => this == log || this == api;
}

/// One model's accelerator: requested → actual backend, the GPU API and the
/// adapter, each with its own [EvidenceSource].
final class const AcceleratorEvidence({
  /// `gpu` or `cpu`, as the app asked.
  required final String requested,

  /// What it runs on; equal to [requested] when only that is known.
  required final String actual,
  required final EvidenceSource backendSource,

  /// `Metal`, `WebGPU/Vulkan`, `OpenCL`, `CPU`; null when unknown.
  final String? api,
  final EvidenceSource apiSource = EvidenceSource.inferred,

  /// `Tesla T4 (Discrete GPU)`, `Apple M4 Pro`; null when unknown or on the
  /// CPU.
  final String? adapter,
  final EvidenceSource adapterSource = EvidenceSource.inferred,

  /// The "GPU" is a software rasterizer (llvmpipe & co.): an error.
  final bool softwareGpu = false,

  /// Part of the load runs on the CPU (XNNPACK delegate), from the log.
  final bool cpuDelegate = false,

  /// The GPU sampler was not available, so sampling runs on the CPU.
  final bool samplerOnCpu = false,

  /// The log says a GPU accelerator could not be loaded (shown as a note: a
  /// load may try more than one accelerator).
  final bool noGpuLogged = false,

  /// The native log lines this evidence came from.
  final List<String> logLines = const [],
}) {
  /// Confirmed on another backend than requested.
  bool get mismatch => backendSource.confirmed && actual != requested;

  /// On the GPU, but neither the log nor the probe can name the adapter: a
  /// software GPU cannot be ruled out.
  bool get adapterUnknown => actual == 'gpu' && adapter == null;

  /// Red in the UI and a failure in the self-test.
  bool get isError => mismatch || softwareGpu;
}

/// `Selected adapter: …` from WebGPU/Dawn: the GPU LiteRT really opened.
final class const AdapterLine({
  required final String name,
  final String? arch,
  final String? vendor,

  /// `Vulkan`, `Metal`, `D3D12`.
  final String? backend,

  /// `Discrete GPU`, `Integrated GPU`, `CPU`.
  final String? adapterType,
});

/// What a load's native log says (`parseNativeLog`).
final class const NativeLogEvidence({
  final AdapterLine? adapter,

  /// `Metal`, `WebGPU/Vulkan`: the GPU API a line confirms.
  final String? api,

  /// `GPU accelerator could not be loaded`.
  final bool noGpu = false,
  final bool cpuDelegate = false,
  final bool samplerOnCpu = false,
  final bool softwareGpu = false,

  /// Every line that matched a pattern, in order.
  final List<String> lines = const [],
});
