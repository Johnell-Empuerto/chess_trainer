import 'move_quality.dart';

class CoachMoveReview {
  final String playedSan;
  final String playedUci;
  final String fenBefore;
  final String fenAfter;
  final double? evalBefore;
  final double? evalAfter;
  final double? evalLoss;
  final MoveQuality quality;
  final String bestMoveUci;
  final String bestMoveSan;
  final List<String> pvLine;
  final int depth;
  final String? openingName;
  final String? aiExplanation;
  final String fallbackExplanation;
  final bool aiAvailable;
  final bool hasMateScore;
  final bool isMateBlunder;
  final bool isCheckmateMove;
  final String? mateDescription;
  final bool isOpeningPhase;
  final String? error;

  const CoachMoveReview({
    required this.playedSan,
    required this.playedUci,
    required this.fenBefore,
    required this.fenAfter,
    required this.evalBefore,
    required this.evalAfter,
    required this.evalLoss,
    required this.quality,
    required this.bestMoveUci,
    this.bestMoveSan = '',
    required this.pvLine,
    required this.depth,
    this.openingName,
    this.aiExplanation,
    required this.fallbackExplanation,
    this.aiAvailable = false,
    this.hasMateScore = false,
    this.isMateBlunder = false,
    this.isCheckmateMove = false,
    this.mateDescription,
    this.isOpeningPhase = false,
    this.error,
  });

  bool get isBestMove => (evalLoss ?? 999) < 0.01;
  bool get hasError => error != null;
}
