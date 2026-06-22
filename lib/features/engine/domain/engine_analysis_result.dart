class EngineAnalysisLine {
  final int multiPv;
  final String? bestMoveUci;
  final double? evaluationPawns;
  final int? mateIn;
  final List<String> principalVariation;
  final int depth;
  final String rawSummary;

  const EngineAnalysisLine({
    required this.multiPv,
    required this.bestMoveUci,
    required this.evaluationPawns,
    required this.mateIn,
    required this.principalVariation,
    required this.depth,
    required this.rawSummary,
  });

  EngineAnalysisLine copyWith({
    int? multiPv,
    String? bestMoveUci,
    double? evaluationPawns,
    int? mateIn,
    bool clearMateIn = false,
    List<String>? principalVariation,
    int? depth,
    String? rawSummary,
  }) {
    return EngineAnalysisLine(
      multiPv: multiPv ?? this.multiPv,
      bestMoveUci: bestMoveUci ?? this.bestMoveUci,
      evaluationPawns: evaluationPawns ?? this.evaluationPawns,
      mateIn: clearMateIn ? null : mateIn ?? this.mateIn,
      principalVariation: principalVariation ?? this.principalVariation,
      depth: depth ?? this.depth,
      rawSummary: rawSummary ?? this.rawSummary,
    );
  }
}

class EngineAnalysisResult {
  final String bestMoveUci;
  final String? ponderMoveUci;
  final double? evaluationPawns;
  final int? mateIn;
  final List<String> principalVariation;
  final int depth;
  final String rawSummary;
  final List<EngineAnalysisLine> lines;
  final String fen;
  final int searchId;
  final bool isFinal;

  const EngineAnalysisResult({
    required this.bestMoveUci,
    required this.ponderMoveUci,
    required this.evaluationPawns,
    required this.mateIn,
    required this.principalVariation,
    required this.depth,
    required this.rawSummary,
    this.lines = const [],
    this.fen = '',
    this.searchId = 0,
    this.isFinal = false,
  });

  factory EngineAnalysisResult.fromLines({
    required List<EngineAnalysisLine> lines,
    required String fen,
    required int searchId,
    required bool isFinal,
    String? bestMoveOverride,
    String? ponderMoveUci,
    String rawSummary = '',
  }) {
    final sortedLines = [...lines]
      ..sort((a, b) => a.multiPv.compareTo(b.multiPv));
    final topLine = sortedLines.isEmpty ? null : sortedLines.first;
    final bestMove = bestMoveOverride ??
        topLine?.bestMoveUci ??
        topLine?.principalVariation.firstOrNull;

    return EngineAnalysisResult(
      bestMoveUci: bestMove ?? 'none',
      ponderMoveUci: ponderMoveUci,
      evaluationPawns: topLine?.evaluationPawns,
      mateIn: topLine?.mateIn,
      principalVariation: topLine?.principalVariation ?? const [],
      depth: topLine?.depth ?? 0,
      rawSummary:
          rawSummary.isNotEmpty ? rawSummary : topLine?.rawSummary ?? '',
      lines: sortedLines,
      fen: fen,
      searchId: searchId,
      isFinal: isFinal,
    );
  }
}

extension _FirstOrNullExtension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
