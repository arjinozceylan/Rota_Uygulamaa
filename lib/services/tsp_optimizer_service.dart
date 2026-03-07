/// Held-Karp exact TSP solver.
///
/// Problem model:
/// - Start node is fixed at index 0.
/// - Must visit every other node exactly once.
/// - Must return to the start node.
/// - Cost matrix is expected to be square and cost[i][j] is the travel cost
///   from i -> j (typically duration in seconds or minutes).
///
/// This gives the exact optimal solution for small/medium N.
/// Complexity is O(n^2 * 2^n), so keep N modest.
class TspOptimizerService {
  const TspOptimizerService();

  /// Solves TSP exactly using Held-Karp dynamic programming.
  ///
  /// [cost] must be an NxN matrix.
  /// Node 0 is treated as the fixed start/end node.
  TspSolveResult solveExact(List<List<double>> cost) {
    _validateMatrix(cost);

    final n = cost.length;
    if (n == 1) {
      return const TspSolveResult(route: [0, 0], totalCost: 0);
    }

    // Number nodes 1..n-1 as the visit set.
    final subsetCount = 1 << (n - 1);

    // dp[mask][j] = minimum cost to start at 0, visit all nodes in [mask],
    // and finish at node j.
    // Here j is in 1..n-1 and must be included in mask.
    final dp = List.generate(
      subsetCount,
      (_) => List<double>.filled(n, double.infinity),
    );

    // parent[mask][j] = previous node before j in the optimal path.
    final parent = List.generate(subsetCount, (_) => List<int>.filled(n, -1));

    // Base case: directly go from 0 -> j.
    for (int j = 1; j < n; j++) {
      final mask = 1 << (j - 1);
      dp[mask][j] = cost[0][j];
      parent[mask][j] = 0;
    }

    // Fill DP.
    for (int mask = 1; mask < subsetCount; mask++) {
      for (int j = 1; j < n; j++) {
        // j must be inside mask.
        if ((mask & (1 << (j - 1))) == 0) continue;

        final prevMask = mask ^ (1 << (j - 1));
        if (prevMask == 0) continue;

        for (int k = 1; k < n; k++) {
          if ((prevMask & (1 << (k - 1))) == 0) continue;

          final candidate = dp[prevMask][k] + cost[k][j];
          if (candidate < dp[mask][j]) {
            dp[mask][j] = candidate;
            parent[mask][j] = k;
          }
        }
      }
    }

    // Close the tour: last node j -> 0.
    final fullMask = subsetCount - 1;
    double bestCost = double.infinity;
    int bestLast = -1;

    for (int j = 1; j < n; j++) {
      final candidate = dp[fullMask][j] + cost[j][0];
      if (candidate < bestCost) {
        bestCost = candidate;
        bestLast = j;
      }
    }

    if (bestLast == -1 || bestCost.isInfinite) {
      throw StateError('No valid TSP route could be constructed.');
    }

    final route = _reconstructRoute(parent, fullMask, bestLast, n);

    return TspSolveResult(route: route, totalCost: bestCost);
  }

  List<int> _reconstructRoute(
    List<List<int>> parent,
    int fullMask,
    int bestLast,
    int n,
  ) {
    final reversed = <int>[0]; // will append return-to-start later

    int mask = fullMask;
    int current = bestLast;

    // Reconstruct visited nodes backwards.
    while (current != 0 && current != -1) {
      reversed.add(current);
      final prev = parent[mask][current];
      mask ^= (1 << (current - 1));
      current = prev;
    }

    final ordered = reversed.reversed.toList();

    // Ensure tour starts and ends at 0.
    if (ordered.isEmpty || ordered.first != 0) {
      ordered.insert(0, 0);
    }
    if (ordered.last != 0) {
      ordered.add(0);
    }

    // Safety: all nodes should be present exactly once except 0 twice.
    _validateRouteShape(ordered, n);

    return ordered;
  }

  void _validateMatrix(List<List<double>> cost) {
    if (cost.isEmpty) {
      throw ArgumentError('Cost matrix cannot be empty.');
    }

    final n = cost.length;
    for (final row in cost) {
      if (row.length != n) {
        throw ArgumentError('Cost matrix must be square.');
      }
    }

    for (int i = 0; i < n; i++) {
      for (int j = 0; j < n; j++) {
        final v = cost[i][j];
        if (v.isNaN || v.isInfinite) {
          throw ArgumentError('Cost matrix contains invalid values.');
        }
        if (v < 0) {
          throw ArgumentError('Cost matrix cannot contain negative costs.');
        }
      }
    }
  }

  void _validateRouteShape(List<int> route, int n) {
    if (route.length != n + 1) {
      throw StateError('Route length is invalid for TSP tour.');
    }
    if (route.first != 0 || route.last != 0) {
      throw StateError('Route must start and end at node 0.');
    }
  }
}

class TspSolveResult {
  const TspSolveResult({required this.route, required this.totalCost});

  /// Node indices in visit order, including returning to 0.
  /// Example: [0, 2, 1, 3, 0]
  final List<int> route;

  /// Total route cost according to the input matrix.
  final double totalCost;
}
