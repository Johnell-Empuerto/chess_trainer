import 'package:chess_trainer/features/coach/domain/move_quality.dart';

class GameMoveReview {
  final String nodeId;
  final int moveNumber;
  final String playedBy;
  final String playedSan;
  final String fenBefore;
  final String fenAfter;
  final double? evalBefore;
  final double? evalAfter;
  final double evalLoss;
  final MoveQuality quality;
  final String bestMoveUci;
  final String bestMoveSan;
  final List<String> pvLine;
  final String? openingName;
  final bool isBookMove;
  final bool isDatabaseMove;
  final String? bookMoveSource;
  final int? bookMoveGames;
  final double? bookMoveWhiteWinRate;
  final double? bookMoveDrawRate;
  final double? bookMoveBlackWinRate;
  final String? openingMoveNote;
  final bool hasMateScore;
  final bool isMateBlunder;
  final bool isCheckmateMove;
  final String? mateDescription;
  final bool playedMatchesBest;
  final bool isMiss;
  final String? missReason;
  final double evalSwing;
  final bool isCritical;

  const GameMoveReview({
    required this.nodeId,
    required this.moveNumber,
    required this.playedBy,
    required this.playedSan,
    required this.fenBefore,
    required this.fenAfter,
    required this.evalBefore,
    required this.evalAfter,
    required this.evalLoss,
    required this.quality,
    required this.bestMoveUci,
    required this.bestMoveSan,
    required this.pvLine,
    this.openingName,
    this.isBookMove = false,
    this.isDatabaseMove = false,
    this.bookMoveSource,
    this.bookMoveGames,
    this.bookMoveWhiteWinRate,
    this.bookMoveDrawRate,
    this.bookMoveBlackWinRate,
    this.openingMoveNote,
    this.hasMateScore = false,
    this.isMateBlunder = false,
    this.isCheckmateMove = false,
    this.mateDescription,
    this.playedMatchesBest = false,
    this.isMiss = false,
    this.missReason,
    this.evalSwing = 0,
    this.isCritical = false,
  });

  bool get shouldShowDetailedInsight {
    if (isBookMove) return false;
    if (isCheckmateMove || quality == MoveQuality.checkmate) return true;

    return quality == MoveQuality.blunder ||
        quality == MoveQuality.mistake ||
        quality == MoveQuality.miss ||
        quality == MoveQuality.inaccuracy ||
        quality == MoveQuality.brilliant ||
        quality == MoveQuality.excellent;
  }

  double get displayEvalLoss => evalLoss.clamp(0.0, 9.99).toDouble();

  GameMoveReview copyWith({
    String? nodeId,
    int? moveNumber,
    String? playedBy,
    String? playedSan,
    String? fenBefore,
    String? fenAfter,
    double? evalBefore,
    bool clearEvalBefore = false,
    double? evalAfter,
    bool clearEvalAfter = false,
    double? evalLoss,
    MoveQuality? quality,
    String? bestMoveUci,
    String? bestMoveSan,
    List<String>? pvLine,
    String? openingName,
    bool clearOpeningName = false,
    bool? isBookMove,
    bool? isDatabaseMove,
    String? bookMoveSource,
    bool clearBookMoveSource = false,
    int? bookMoveGames,
    bool clearBookMoveGames = false,
    double? bookMoveWhiteWinRate,
    bool clearBookMoveWhiteWinRate = false,
    double? bookMoveDrawRate,
    bool clearBookMoveDrawRate = false,
    double? bookMoveBlackWinRate,
    bool clearBookMoveBlackWinRate = false,
    String? openingMoveNote,
    bool clearOpeningMoveNote = false,
    bool? hasMateScore,
    bool? isMateBlunder,
    bool? isCheckmateMove,
    String? mateDescription,
    bool clearMateDescription = false,
    bool? playedMatchesBest,
    bool? isMiss,
    String? missReason,
    bool clearMissReason = false,
    double? evalSwing,
    bool? isCritical,
  }) {
    return GameMoveReview(
      nodeId: nodeId ?? this.nodeId,
      moveNumber: moveNumber ?? this.moveNumber,
      playedBy: playedBy ?? this.playedBy,
      playedSan: playedSan ?? this.playedSan,
      fenBefore: fenBefore ?? this.fenBefore,
      fenAfter: fenAfter ?? this.fenAfter,
      evalBefore: clearEvalBefore ? null : evalBefore ?? this.evalBefore,
      evalAfter: clearEvalAfter ? null : evalAfter ?? this.evalAfter,
      evalLoss: evalLoss ?? this.evalLoss,
      quality: quality ?? this.quality,
      bestMoveUci: bestMoveUci ?? this.bestMoveUci,
      bestMoveSan: bestMoveSan ?? this.bestMoveSan,
      pvLine: pvLine ?? this.pvLine,
      openingName: clearOpeningName ? null : openingName ?? this.openingName,
      isBookMove: isBookMove ?? this.isBookMove,
      isDatabaseMove: isDatabaseMove ?? this.isDatabaseMove,
      bookMoveSource:
          clearBookMoveSource ? null : bookMoveSource ?? this.bookMoveSource,
      bookMoveGames:
          clearBookMoveGames ? null : bookMoveGames ?? this.bookMoveGames,
      bookMoveWhiteWinRate: clearBookMoveWhiteWinRate
          ? null
          : bookMoveWhiteWinRate ?? this.bookMoveWhiteWinRate,
      bookMoveDrawRate: clearBookMoveDrawRate
          ? null
          : bookMoveDrawRate ?? this.bookMoveDrawRate,
      bookMoveBlackWinRate: clearBookMoveBlackWinRate
          ? null
          : bookMoveBlackWinRate ?? this.bookMoveBlackWinRate,
      openingMoveNote:
          clearOpeningMoveNote ? null : openingMoveNote ?? this.openingMoveNote,
      hasMateScore: hasMateScore ?? this.hasMateScore,
      isMateBlunder: isMateBlunder ?? this.isMateBlunder,
      isCheckmateMove: isCheckmateMove ?? this.isCheckmateMove,
      mateDescription:
          clearMateDescription ? null : mateDescription ?? this.mateDescription,
      playedMatchesBest: playedMatchesBest ?? this.playedMatchesBest,
      isMiss: isMiss ?? this.isMiss,
      missReason: clearMissReason ? null : missReason ?? this.missReason,
      evalSwing: evalSwing ?? this.evalSwing,
      isCritical: isCritical ?? this.isCritical,
    );
  }
}
