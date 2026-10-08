import 'package:flutter/foundation.dart';

/// Keys for tests.
abstract final class DebugOverlayKeys {
  static const toggle = ValueKey('debug-overlay-toggle');
  static const panel = ValueKey('debug-overlay-panel');

  /// The panel's scroll view (the full list scrolls inside the panel).
  static const scroll = ValueKey('debug-overlay-scroll');

  /// The handle that collapses and expands the panel.
  static const expand = ValueKey('debug-overlay-expand');

  /// The scroll strip on the panel's right edge, while its text overflows.
  static const scrollbar = ValueKey('debug-overlay-scrollbar');
}
