import 'package:chess_trainer/features/game_review/domain/game_move_review.dart';

class PlayerStats {
  final double accuracy;
  final int bestCount;
  final int excellentCount;
  final int goodCount;
  final int inaccuracyCount;
  final int mistakeCount;
  final int blunderCount;
  final int totalMoves;
  final double totalEvalLoss;

  const PlayerStats({
    required this.accuracy,
    required this.bestCount,
    required this.excellentCount,
    required this.goodCount,
    required this.inaccuracyCount,
    required this.mistakeCount,
    required this.blunderCount,
    required this.totalMoves,
    required this.totalEvalLoss,
  });

  bool get hasIssues => inaccuracyCount + mistakeCount + blunderCount > 0;
}

class GameReviewReport {
  final List<GameMoveReview> moves;
  final PlayerStats whiteStats;
  final PlayerStats blackStats;
  final String? openingName;
  final String result;
  final List<GameMoveReview> criticalMoments;
  final String? coachSummary;
  final List<String> trainingThemes;

  const GameReviewReport({
    required this.moves,
    required this.whiteStats,
    required this.blackStats,
    this.openingName,
    required this.result,
    required this.criticalMoments,
    this.coachSummary,
    this.trainingThemes = const [],
  });

  int get totalMoves => moves.length;
  bool get hasResult => result.isNotEmpty;
  GameMoveReview? get lastMove => moves.isNotEmpty ? moves.last : null;
}
