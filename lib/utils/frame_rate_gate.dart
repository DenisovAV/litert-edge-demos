/// Lets frames through at most [fps] on average while tolerating jitter.
///
/// It keeps a cadence of `1/fps`: a frame passes when it arrives no earlier
/// than [slack] before the next slot, and the slot then advances by one
/// period from where it was scheduled, so early and late frames average out.
/// After a gap longer than a period (paused, worker busy) the cadence
/// restarts from the frame that passes, so there is no catch-up burst.
///
/// A 30 or 60 fps source is cut to exactly 15; a 15 fps source with up to
/// [slack] of jitter passes every frame.
final class FrameRateGate {
  FrameRateGate({required int fps, required Duration slack})
    : assert(fps > 0),
      _period = 1000000 ~/ fps,
      _slack = slack.inMicroseconds;

  final int _period;
  final int _slack;
  int? _nextSlot;

  /// Whether a frame arriving at [nowMicros] (a monotonic clock) passes.
  bool tryPass(int nowMicros) {
    final slot = _nextSlot;
    if (slot != null && nowMicros < slot - _slack) return false;
    _nextSlot = slot == null || nowMicros - slot > _period
        ? nowMicros + _period
        : slot + _period;
    return true;
  }

  /// Forgets the cadence: the next frame passes.
  void reset() => _nextSlot = null;
}
