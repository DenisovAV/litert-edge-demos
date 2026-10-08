/// The diagnostics overlay: a panel over every screen with the models, their
/// backends, fps and latency (AGENTS.md rule 2). One import for all of it:
///
/// - `overlay_host.dart`: `DebugOverlayHost`, which puts the panel over the
///   app, and `DebugOverlayToggle`, its app-bar switch;
/// - `overlay_layout.dart`: `DebugOverlayLayout`, where the panel goes and
///   how large it may be;
/// - `overlay_panel.dart`: the `DebugOverlay` panel, with its handle and
///   scroll strip;
/// - `overlay_lines.dart`: its text, `debugOverlayLines` and
///   `debugOverlaySummaryLines`;
/// - `overlay_keys.dart`: `DebugOverlayKeys`, for tests.
library;

export 'debug_overlay/overlay_host.dart';
export 'debug_overlay/overlay_keys.dart';
export 'debug_overlay/overlay_layout.dart';
export 'debug_overlay/overlay_lines.dart';
export 'debug_overlay/overlay_panel.dart';
