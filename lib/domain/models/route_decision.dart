/// What a fast answer is about.
enum FastIntent {
  /// "What do you see?"
  inventory,

  /// "Is there a dog?"
  presence,

  /// "How many cats?"
  count,
}

/// Where a camera question goes (design demo3 §6). [rule] names the rule
/// that decided, for the chip and the overlay.
sealed class RouteDecision {
  const RouteDecision(this.rule);

  final String rule;
}

/// Answered from the detection summary with a template: no LLM.
final class FastRoute extends RouteDecision {
  const FastRoute(this.intent, super.rule, {this.cls});

  final FastIntent intent;

  /// The class asked about; null for [FastIntent.inventory].
  final int? cls;

  @override
  String toString() => 'FastRoute(${intent.name}, cls=$cls, rule=$rule)';
}

/// Needs the frame and Gemma.
final class DetailedRoute extends RouteDecision {
  const DetailedRoute(super.rule);

  @override
  String toString() => 'DetailedRoute(rule=$rule)';
}
