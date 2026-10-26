/// Result of comparing the user's spending in one category against a
/// "typical" benchmark. `isDemo` is always surfaced in the UI so the
/// insight is never mistaken for a real cross-user ML comparison.
class PeerComparisonResult {
  final String category;
  final double percentDifference; // positive = spends more than benchmark
  final bool isDemo;

  const PeerComparisonResult({
    required this.category,
    required this.percentDifference,
    required this.isDemo,
  });

  String get summary {
    final direction = percentDifference >= 0 ? 'more' : 'less';
    return 'You spend ${percentDifference.abs().round()}% $direction on '
        '$category than similar users.';
  }
}

/// Interface for comparing a user's category spending against other users
/// with a similar profile/persona. No real cross-user dataset is wired up
/// yet — swap `DemoPeerComparisonService` for a real implementation
/// (backed by an aggregated, privacy-safe peer dataset) without touching
/// any screen that consumes this.
abstract class PeerComparisonService {
  Future<PeerComparisonResult?> compareTopCategory({
    required String category,
    required double userCategoryTotal,
    required double userTotalSpend,
    String? persona,
  });
}

/// Clearly-marked demo/fallback comparison. Rather than inventing a
/// specific peer number, it compares the user's top category share of
/// their own spending against a generic "typical discretionary share"
/// benchmark (25%) — a rough rule of thumb, not a real aggregated
/// statistic. The UI must always label this as a demo insight.
class DemoPeerComparisonService implements PeerComparisonService {
  static const double _benchmarkShare = 0.25;

  @override
  Future<PeerComparisonResult?> compareTopCategory({
    required String category,
    required double userCategoryTotal,
    required double userTotalSpend,
    String? persona,
  }) async {
    if (userTotalSpend <= 0) return null;
    final userShare = userCategoryTotal / userTotalSpend;
    final diffPct = ((userShare - _benchmarkShare) / _benchmarkShare) * 100;
    return PeerComparisonResult(
      category: category,
      percentDifference: diffPct,
      isDemo: true,
    );
  }
}
