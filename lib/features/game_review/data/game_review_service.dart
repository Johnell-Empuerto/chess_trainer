import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:chess_trainer/core/chess/move.dart';
import 'package:chess_trainer/features/coach/data/ai_explainer_service.dart';
import 'package:chess_trainer/features/coach/data/stockfish_coach_service.dart';
import 'package:chess_trainer/features/coach/domain/move_quality.dart';
import 'package:chess_trainer/features/explorer/data/opening_explorer_repository.dart';
import 'package:chess_trainer/features/explorer/domain/explorer_move_stat.dart';
import 'package:chess_trainer/features/game_review/domain/game_move_review.dart';
import 'package:chess_trainer/features/game_review/domain/game_review_report.dart';
import 'package:chess_trainer/features/game_review/domain/training_theme.dart';

class GameReviewService {
  static const int _bookLookupLimit = 512;

  final StockfishCoachService _coachService;
  final OpeningExplorerRepository? _explorerRepository;
  final AiExplainerService? _aiService;
  bool _explorerBookLookupUnavailable = false;

  GameReviewService({
    required StockfishCoachService coachService,
    OpeningExplorerRepository? explorerRepository,
    AiExplainerService? aiService,
  })  : _coachService = coachService,
        _explorerRepository = explorerRepository,
        _aiService = aiService;

  Future<GameReviewReport?> reviewGame({
    required Map<String, MoveNode> moveTree,
    required List<String> mainLineNodeIds,
    String? openingName,
    String? result,
  }) async {
    if (mainLineNodeIds.isEmpty) return null;

    final gameMoves = <GameMoveReview>[];

    for (var i = 0; i < mainLineNodeIds.length; i++) {
      final nodeId = mainLineNodeIds[i];
      final node = moveTree[nodeId];
      if (node == null || node.isRoot) continue;

      try {
        final coachReview = await _coachService.reviewMove(
          moveNode: node,
          openingName: openingName,
        );
        final bookMatch = await _bookMoveForNode(node);
        final moveNumber = node.moveNumber;
        final playedBy = node.colorName;
        final evalLoss = coachReview.playedMatchesBest
            ? 0.0
            : _safeEvalLoss(coachReview.evalLoss);
        final evalSwing = _evalSwingForMover(
          evalBefore: coachReview.evalBefore,
          evalAfter: coachReview.evalAfter,
          playedBy: playedBy,
        );
        final isExplorerDatabaseMove = bookMatch != null;
        final useOpeningTolerance = _useOpeningTolerance(
          plyIndex: i + 1,
          openingName: openingName,
          evalLoss: evalLoss,
          hasMateScore: coachReview.hasMateScore,
        );
        final quality = _qualityForGameReview(
          coachReview.quality,
          evalLoss: evalLoss,
          isExplorerDatabaseMove: isExplorerDatabaseMove,
          useOpeningTolerance: useOpeningTolerance,
          hasMateScore: coachReview.hasMateScore,
          isMateBlunder: coachReview.isMateBlunder,
          isCheckmateMove: coachReview.isCheckmateMove,
          playedMatchesBest: coachReview.playedMatchesBest,
          isMiss: coachReview.isMiss,
          evalBefore: coachReview.evalBefore,
          evalAfter: coachReview.evalAfter,
          playedBy: playedBy,
        );
        final isMiss = coachReview.isMiss || quality == MoveQuality.miss;
        final isBookMove = _shouldDisplayBookMove(
          isExplorerDatabaseMove: isExplorerDatabaseMove,
          evalLoss: evalLoss,
          quality: quality,
          isMateBlunder: coachReview.isMateBlunder,
          isCheckmateMove: coachReview.isCheckmateMove,
          isMiss: isMiss,
        );
        final openingMoveNote = _openingMoveNote(
          isBookMove: isBookMove,
          isExplorerDatabaseMove: isExplorerDatabaseMove,
          quality: quality,
          bestMoveSan: coachReview.bestMoveSan,
          bestMoveUci: coachReview.bestMoveUci,
        );

        gameMoves.add(GameMoveReview(
          nodeId: nodeId,
          moveNumber: moveNumber,
          playedBy: playedBy,
          playedSan: node.san,
          fenBefore: node.fenBefore,
          fenAfter: node.fenAfter,
          evalBefore: coachReview.evalBefore,
          evalAfter: coachReview.evalAfter,
          evalLoss: evalLoss,
          quality: quality,
          bestMoveUci: coachReview.bestMoveUci,
          bestMoveSan: coachReview.bestMoveSan,
          pvLine: coachReview.pvLine,
          openingName: coachReview.openingName,
          isBookMove: isBookMove,
          isDatabaseMove: isExplorerDatabaseMove,
          bookMoveSource: bookMatch?.source,
          bookMoveGames: bookMatch?.stat.gamesCount,
          bookMoveWhiteWinRate: bookMatch?.stat.whiteWinRate,
          bookMoveDrawRate: bookMatch?.stat.drawRate,
          bookMoveBlackWinRate: bookMatch?.stat.blackWinRate,
          openingMoveNote: openingMoveNote,
          hasMateScore: coachReview.hasMateScore,
          isMateBlunder: coachReview.isMateBlunder,
          isCheckmateMove: coachReview.isCheckmateMove,
          mateDescription: coachReview.mateDescription,
          playedMatchesBest: coachReview.playedMatchesBest,
          isMiss: isMiss,
          missReason: coachReview.missReason,
          evalSwing: evalSwing,
        ));
      } catch (e) {
        debugPrint('game review: error at node $nodeId: $e');
      }
    }

    if (gameMoves.isEmpty) return null;

    final whiteMoves = gameMoves.where((m) => m.playedBy == 'white').toList();
    final blackMoves = gameMoves.where((m) => m.playedBy == 'black').toList();

    final whiteStats = _computeStats(whiteMoves);
    final blackStats = _computeStats(blackMoves);

    final criticalMoments = _findCriticalMoments(gameMoves);
    final themes = _detectTrainingThemes(
      gameMoves,
      whiteStats,
      blackStats,
    );
    final coachSummary = await _generateCoachSummary(
      gameMoves: gameMoves,
      whiteStats: whiteStats,
      blackStats: blackStats,
      openingName: openingName,
      result: result,
      criticalMoments: criticalMoments,
      themes: themes,
    );

    return GameReviewReport(
      moves: gameMoves,
      whiteStats: whiteStats,
      blackStats: blackStats,
      openingName: openingName,
      result: result ?? '',
      criticalMoments: criticalMoments,
      coachSummary: coachSummary,
      trainingThemes: themes.map((t) => t.label).toList(),
    );
  }

  double _safeEvalLoss(double? evalLoss) {
    if (evalLoss == null || evalLoss.isNaN || evalLoss.isInfinite) return 0.0;
    return evalLoss.clamp(0.0, 9.99).toDouble();
  }

  double _evalSwingForMover({
    required double? evalBefore,
    required double? evalAfter,
    required String playedBy,
  }) {
    if (evalBefore == null || evalAfter == null) return 0.0;
    return playedBy == 'white'
        ? evalAfter - evalBefore
        : evalBefore - evalAfter;
  }

  bool _useOpeningTolerance({
    required int plyIndex,
    required String? openingName,
    required double evalLoss,
    required bool hasMateScore,
  }) {
    if (hasMateScore) return false;
    if (plyIndex <= 10) return evalLoss < 2.5;
    return openingName != null &&
        openingName.trim().isNotEmpty &&
        plyIndex <= 14 &&
        evalLoss < 2.5;
  }

  MoveQuality _qualityForGameReview(
    MoveQuality original, {
    required double evalLoss,
    required bool isExplorerDatabaseMove,
    required bool useOpeningTolerance,
    required bool hasMateScore,
    required bool isMateBlunder,
    required bool isCheckmateMove,
    required bool playedMatchesBest,
    required bool isMiss,
    required double? evalBefore,
    required double? evalAfter,
    required String playedBy,
  }) {
    if (isCheckmateMove || original == MoveQuality.checkmate) {
      return MoveQuality.checkmate;
    }
    if (playedMatchesBest) {
      return original == MoveQuality.brilliant
          ? MoveQuality.brilliant
          : MoveQuality.excellent;
    }
    final moverEvalBefore = _moverEval(evalBefore, playedBy);
    final moverEvalAfter = _moverEval(evalAfter, playedBy);
    if (isMateBlunder) {
      return (moverEvalBefore ?? 0) <= -6.0
          ? MoveQuality.mistake
          : MoveQuality.blunder;
    }
    if (isMiss || original == MoveQuality.miss) return MoveQuality.miss;

    if (isExplorerDatabaseMove) {
      if (evalLoss >= 4.0) return MoveQuality.blunder;
      if (evalLoss >= 2.5) return MoveQuality.mistake;
      if (evalLoss >= 1.2) return MoveQuality.inaccuracy;
      return original == MoveQuality.brilliant ||
              original == MoveQuality.excellent
          ? original
          : MoveQuality.good;
    }

    if (useOpeningTolerance) {
      if (evalLoss > 2.5) return MoveQuality.blunder;
      if (evalLoss >= 1.2) return MoveQuality.mistake;
      if (evalLoss >= 0.6) return MoveQuality.inaccuracy;
      return MoveQuality.good;
    }

    if (hasMateScore) return original;

    if (moverEvalBefore != null && moverEvalBefore <= -6.0) {
      if (evalLoss >= 4.0) return MoveQuality.mistake;
      if (evalLoss >= 1.5) return MoveQuality.inaccuracy;
      return MoveQuality.good;
    }

    if (moverEvalBefore != null && moverEvalBefore <= -3.0) {
      if (evalLoss >= 4.0) return MoveQuality.mistake;
      if (evalLoss >= 1.5) return MoveQuality.inaccuracy;
      return MoveQuality.good;
    }

    if (moverEvalBefore != null &&
        moverEvalAfter != null &&
        moverEvalBefore >= 2.5) {
      if (moverEvalAfter < 0.5 && evalLoss >= 2.5) {
        return MoveQuality.blunder;
      }
      if (evalLoss >= 1.2) return MoveQuality.mistake;
      if (evalLoss >= 0.6) return MoveQuality.inaccuracy;
      return original == MoveQuality.excellent ||
              original == MoveQuality.brilliant
          ? original
          : MoveQuality.good;
    }

    if (evalLoss >= 2.5) return MoveQuality.blunder;
    if (evalLoss >= 1.0) return MoveQuality.mistake;
    if (evalLoss >= 0.35) return MoveQuality.inaccuracy;
    return original == MoveQuality.brilliant ||
            original == MoveQuality.excellent
        ? original
        : MoveQuality.good;
  }

  double? _moverEval(double? eval, String playedBy) {
    if (eval == null) return null;
    return playedBy == 'white' ? eval : -eval;
  }

  Future<_BookMoveMatch?> _bookMoveForNode(MoveNode node) async {
    final repository = _explorerRepository;
    if (repository == null || _explorerBookLookupUnavailable) return null;

    try {
      final explorerMoves = await repository.movesForFen(
        node.fenBefore,
        limit: _bookLookupLimit,
      );
      if (explorerMoves.isEmpty) return null;

      final playedUci = normalizeUciForCompare(node.uci);
      if (playedUci.isNotEmpty) {
        for (final move in explorerMoves) {
          if (normalizeUciForCompare(move.moveUci) == playedUci) {
            return _BookMoveMatch(move);
          }
        }
      }

      final playedSan = normalizeSanForCompare(node.san);
      if (playedSan.isNotEmpty) {
        for (final move in explorerMoves) {
          if (normalizeSanForCompare(move.moveSan) == playedSan) {
            return _BookMoveMatch(move);
          }
        }
      }
    } catch (error) {
      _explorerBookLookupUnavailable = true;
      debugPrint('game review: explorer book lookup unavailable: $error');
    }

    return null;
  }

  bool _shouldDisplayBookMove({
    required bool isExplorerDatabaseMove,
    required double evalLoss,
    required MoveQuality quality,
    required bool isMateBlunder,
    required bool isCheckmateMove,
    required bool isMiss,
  }) {
    if (!isExplorerDatabaseMove) return false;
    if (isCheckmateMove || isMateBlunder || isMiss) return false;
    if (evalLoss >= 1.2) return false;

    return quality == MoveQuality.brilliant ||
        quality == MoveQuality.excellent ||
        quality == MoveQuality.good;
  }

  String? _openingMoveNote({
    required bool isBookMove,
    required bool isExplorerDatabaseMove,
    required MoveQuality quality,
    required String bestMoveSan,
    required String bestMoveUci,
  }) {
    if (isBookMove) {
      return 'This is a book opening move. It appears in the explorer database and follows known opening theory.';
    }

    if (!isExplorerDatabaseMove) return null;

    final bestMove = bestMoveSan.isNotEmpty ? bestMoveSan : bestMoveUci;
    switch (quality) {
      case MoveQuality.inaccuracy:
        return bestMove.isEmpty || bestMove == 'none'
            ? 'This move exists in the database, but it is not engine-approved. Treat it as a risky sideline rather than the main recommendation.'
            : 'This move appears in the explorer database, so it has been played before, but the engine prefers $bestMove. Treat it as a risky sideline rather than the main recommendation.';
      case MoveQuality.mistake:
      case MoveQuality.blunder:
        return 'This is a known database move, but it creates a practical problem. The database can show what people play, while Stockfish shows what is best.';
      case MoveQuality.checkmate:
      case MoveQuality.miss:
      case MoveQuality.brilliant:
      case MoveQuality.excellent:
      case MoveQuality.good:
        return null;
    }
  }

  PlayerStats _computeStats(List<GameMoveReview> moves) {
    if (moves.isEmpty) {
      return const PlayerStats(
        accuracy: 0,
        bestCount: 0,
        excellentCount: 0,
        goodCount: 0,
        missCount: 0,
        inaccuracyCount: 0,
        mistakeCount: 0,
        blunderCount: 0,
        totalMoves: 0,
        totalEvalLoss: 0,
      );
    }

    var best = 0,
        excellent = 0,
        good = 0,
        miss = 0,
        inaccuracy = 0,
        mistake = 0,
        blunder = 0;
    var totalLoss = 0.0;

    for (final move in moves) {
      switch (move.quality) {
        case MoveQuality.checkmate:
          best++;
        case MoveQuality.brilliant:
          best++;
        case MoveQuality.excellent:
          excellent++;
        case MoveQuality.good:
          good++;
        case MoveQuality.miss:
          miss++;
        case MoveQuality.inaccuracy:
          inaccuracy++;
        case MoveQuality.mistake:
          mistake++;
        case MoveQuality.blunder:
          blunder++;
      }
      if (!move.hasMateScore) {
        totalLoss += move.displayEvalLoss;
      } else {
        totalLoss += move.isMateBlunder ? 9.99 : move.displayEvalLoss;
      }
    }

    final accuracy = _computeAccuracy(moves);

    return PlayerStats(
      accuracy: accuracy,
      bestCount: best,
      excellentCount: excellent,
      goodCount: good,
      missCount: miss,
      inaccuracyCount: inaccuracy,
      mistakeCount: mistake,
      blunderCount: blunder,
      totalMoves: moves.length,
      totalEvalLoss: totalLoss,
    );
  }

  double _computeAccuracy(List<GameMoveReview> moves) {
    if (moves.isEmpty) return 0;
    var total = 0.0;
    for (final move in moves) {
      final loss = move.displayEvalLoss.clamp(0.0, 6.0);
      final score = (1.0 - loss / 6.0) * 100;
      total += score.clamp(0.0, 100.0);
    }
    return (total / moves.length * 10).roundToDouble() / 10;
  }

  List<GameMoveReview> _findCriticalMoments(List<GameMoveReview> moves) {
    final candidates = moves.where(_isCriticalMoment).toList()
      ..sort((a, b) => _criticalScore(b).compareTo(_criticalScore(a)));

    final criticalIds = candidates
        .where((move) =>
            move.isCheckmateMove || move.quality == MoveQuality.checkmate)
        .map((move) => move.nodeId)
        .toSet();
    final maxCriticalCount = math.max(6, criticalIds.length);

    for (final move in candidates) {
      if (criticalIds.length >= maxCriticalCount) break;
      criticalIds.add(move.nodeId);
    }

    for (var i = 0; i < moves.length; i++) {
      if (criticalIds.contains(moves[i].nodeId)) {
        moves[i] = moves[i].copyWith(isCritical: true);
      }
    }

    return moves.where((m) => m.isCritical).toList();
  }

  bool _isCriticalMoment(GameMoveReview move) {
    if (move.isCheckmateMove) return true;
    if (move.isBookMove) return false;
    if (move.isMateBlunder) return true;
    if (move.isMiss || move.quality == MoveQuality.miss) return true;
    if (move.displayEvalLoss >= 2.0) return true;

    switch (move.quality) {
      case MoveQuality.checkmate:
        return true;
      case MoveQuality.miss:
        return true;
      case MoveQuality.blunder:
      case MoveQuality.mistake:
        return true;
      case MoveQuality.inaccuracy:
        return move.displayEvalLoss >= 0.5;
      case MoveQuality.brilliant:
      case MoveQuality.excellent:
        return move.evalSwing >= 2.0 ||
            (move.hasMateScore && move.isMateBlunder == false);
      case MoveQuality.good:
        return false;
    }
  }

  double _criticalScore(GameMoveReview move) {
    final qualityWeight = switch (move.quality) {
      MoveQuality.checkmate => 7.0,
      MoveQuality.blunder => 6.0,
      MoveQuality.miss => 5.5,
      MoveQuality.mistake => 5.0,
      MoveQuality.inaccuracy => 3.0,
      MoveQuality.brilliant => 4.0,
      MoveQuality.excellent => 2.0,
      MoveQuality.good => 0.0,
    };

    final mateWeight = move.hasMateScore ? 4.0 : 0.0;
    return qualityWeight + mateWeight + move.displayEvalLoss + move.evalSwing;
  }

  List<TrainingTheme> _detectTrainingThemes(
    List<GameMoveReview> moves,
    PlayerStats whiteStats,
    PlayerStats blackStats,
  ) {
    final themes = <TrainingTheme>{};

    final totalIssues = whiteStats.inaccuracyCount +
        whiteStats.missCount +
        whiteStats.mistakeCount +
        whiteStats.blunderCount +
        blackStats.inaccuracyCount +
        blackStats.missCount +
        blackStats.mistakeCount +
        blackStats.blunderCount;

    if (totalIssues >= 3) themes.add(TrainingTheme.tactics);

    if (moves.length > 30) {
      final last10 = moves.skip(moves.length - 10).toList();
      final endgameIssues = last10
          .where((m) =>
              m.quality == MoveQuality.miss ||
              m.quality == MoveQuality.mistake ||
              m.quality == MoveQuality.blunder)
          .length;
      if (endgameIssues >= 2) themes.add(TrainingTheme.endgame);
    }

    final earlyMoves = moves.take(10).toList();
    final openingIssues = earlyMoves
        .where((m) =>
            !m.isBookMove &&
            (m.quality == MoveQuality.miss ||
                m.quality == MoveQuality.inaccuracy ||
                m.quality == MoveQuality.mistake))
        .length;
    if (openingIssues >= 2) themes.add(TrainingTheme.opening);

    final blunders =
        moves.where((m) => m.quality == MoveQuality.blunder).length;
    if (blunders >= 2) {
      themes.add(TrainingTheme.materialAwareness);
    }

    if (totalIssues >= 3) themes.add(TrainingTheme.prophylaxis);

    if (themes.isEmpty) {
      themes.add(TrainingTheme.pieceDevelopment);
      themes.add(TrainingTheme.coordination);
    }

    return themes.toList();
  }

  Future<String?> _generateCoachSummary({
    required List<GameMoveReview> gameMoves,
    required PlayerStats whiteStats,
    required PlayerStats blackStats,
    required String? openingName,
    required String? result,
    required List<GameMoveReview> criticalMoments,
    required List<TrainingTheme> themes,
  }) async {
    final aiService = _aiService;
    if (aiService != null && aiService.isAvailable) {
      try {
        final summary = await _requestAiSummary(
          gameMoves: gameMoves,
          whiteStats: whiteStats,
          blackStats: blackStats,
          openingName: openingName,
          result: result,
          criticalMoments: criticalMoments,
          themes: themes,
          aiService: aiService,
        );
        if (summary != null && !_looksLikeRawData(summary)) {
          return summary;
        }
      } catch (_) {}
    }

    return _templateSummary(
      gameMoves: gameMoves,
      whiteStats: whiteStats,
      blackStats: blackStats,
      openingName: openingName,
      result: result,
      themes: themes,
    );
  }

  bool _looksLikeRawData(String text) {
    final markers = [
      'game review over',
      'white accuracy:',
      'black accuracy:',
      'white blunders:',
      'black blunders:',
      'played move:',
      'move quality:',
      'eval before:',
      'eval after:',
      'eval loss:',
      'principal variation:',
    ];
    var count = 0;
    final lower = text.toLowerCase();
    for (final marker in markers) {
      if (lower.contains(marker)) count++;
    }
    return count >= 2;
  }

  Future<String?> _requestAiSummary({
    required List<GameMoveReview> gameMoves,
    required PlayerStats whiteStats,
    required PlayerStats blackStats,
    required String? openingName,
    required String? result,
    required List<GameMoveReview> criticalMoments,
    required List<TrainingTheme> themes,
    required AiExplainerService aiService,
  }) async {
    final criticalSummary = criticalMoments
        .where((m) =>
            m.quality == MoveQuality.blunder ||
            m.quality == MoveQuality.miss ||
            m.quality == MoveQuality.mistake ||
            m.quality == MoveQuality.inaccuracy)
        .take(3)
        .map((m) =>
            'Move ${m.moveNumber} ${m.playedSan} (${m.playedBy}): ${m.quality.label}, ${_lossSummary(m)}')
        .join('\n');
    final decisiveSummary = criticalMoments
        .where((m) =>
            m.isCheckmateMove ||
            m.quality == MoveQuality.checkmate ||
            m.quality == MoveQuality.brilliant ||
            m.quality == MoveQuality.excellent)
        .take(3)
        .map((m) =>
            'Move ${m.moveNumber} ${m.playedSan} (${m.playedBy}): ${m.quality.label}, ${_lossSummary(m)}')
        .join('\n');
    final openingDatabaseSummary = _openingDatabaseSummary(gameMoves);

    final themesList = themes.map((t) => t.label).join(', ');
    const systemPrompt =
        'You are a chess coach. Do not repeat raw statistics as a list. Turn the game review data into practical training advice. Use only the provided facts. Be specific, short, and helpful.';

    final prompt = '''
Game facts:
Opening: ${openingName ?? 'Unknown'}
Result: ${result == null || result.isEmpty ? 'Unknown' : result}
White accuracy: ${whiteStats.accuracy}%
Black accuracy: ${blackStats.accuracy}%
White issues: ${_issueSummary(whiteStats)}
Black issues: ${_issueSummary(blackStats)}
Opening database: ${openingDatabaseSummary ?? 'No notable database departure or risky known line.'}

Critical mistakes:
${criticalSummary.isEmpty ? 'None' : criticalSummary}

Decisive moves:
${decisiveSummary.isEmpty ? 'None' : decisiveSummary}

Training patterns:
${themesList.isEmpty ? 'None' : themesList}

Write output in this format:
1. Overall:
2. Turning point:
3. What White did well:
4. What Black should improve:
5. Training focus:

Rules:
- Do not say "Game review over..."
- Do not repeat all raw stats.
- Explain the biggest lesson from the game.
- Mention only the most important 2 or 3 critical moves.
- If a decisive checkmate is listed, treat it as a winning tactic, not a mistake.
- Keep it under 150 words.
''';

    try {
      final result = await aiService.generateExplanationRaw(
        prompt,
        systemPrompt: systemPrompt,
      );
      return result;
    } catch (_) {
      return null;
    }
  }

  String _templateSummary({
    required List<GameMoveReview> gameMoves,
    required PlayerStats whiteStats,
    required PlayerStats blackStats,
    required String? openingName,
    required String? result,
    required List<TrainingTheme> themes,
  }) {
    final criticalMoves = gameMoves.where(_isCriticalMoment).take(3).toList();
    final openingDatabaseSummary = _openingDatabaseSummary(gameMoves);
    final overallSummary = _overallSummary(whiteStats, blackStats, openingName);
    final turningPoint = criticalMoves.isEmpty
        ? 'No single move decided the game; both sides mostly kept the balance.'
        : 'Move ${criticalMoves.first.moveNumber} ${criticalMoves.first.playedSan} was the key moment because ${_lossSummary(criticalMoves.first)}.';
    final focus = themes.isEmpty ? null : themes.first;
    final trainingFocus = focus == null
        ? 'Review candidate moves before committing.'
        : '${focus.label} - ${focus.description}';
    final coachTemplate = [
      '1. Overall: $overallSummary${openingDatabaseSummary == null ? '' : ' $openingDatabaseSummary'}',
      '2. Turning point: $turningPoint',
      '3. What White did well: ${_sideStrength("white", gameMoves)}',
      '4. What Black should improve: ${_sideImprovement("black", gameMoves)}',
      '5. Training focus: $trainingFocus',
    ].join('\n');

    if (coachTemplate.isNotEmpty) return coachTemplate;

    final buffer = StringBuffer();

    buffer.writeln(
        'Overall performance: White played ${whiteStats.accuracy}% accuracy, Black played ${blackStats.accuracy}%.');
    buffer.writeln();

    if (openingName != null && openingName.isNotEmpty) {
      buffer.writeln('Opening: $openingName');
      buffer.writeln();
    }

    if (whiteStats.blunderCount +
            whiteStats.mistakeCount +
            blackStats.blunderCount +
            blackStats.mistakeCount >
        0) {
      buffer.writeln('Main mistakes:');
      if (whiteStats.blunderCount > 0) {
        buffer.writeln('- White had ${whiteStats.blunderCount} blunder(s).');
      }
      if (whiteStats.mistakeCount > 0) {
        buffer.writeln('- White made ${whiteStats.mistakeCount} mistake(s).');
      }
      if (blackStats.blunderCount > 0) {
        buffer.writeln('- Black had ${blackStats.blunderCount} blunder(s).');
      }
      if (blackStats.mistakeCount > 0) {
        buffer.writeln('- Black made ${blackStats.mistakeCount} mistake(s).');
      }
      buffer.writeln();
    }

    if (themes.isNotEmpty) {
      buffer.writeln(
          'Training themes: ${themes.map((t) => t.label).join(', ')}.');
      buffer.writeln();
      buffer.writeln(
          'Tip: Focus on ${themes.first.label.toLowerCase()} first — ${themes.first.description}');
    }

    return buffer.toString().trim();
  }

  String _issueSummary(PlayerStats stats) {
    return '${stats.blunderCount} blunders, ${stats.mistakeCount} mistakes, ${stats.missCount} misses, ${stats.inaccuracyCount} inaccuracies';
  }

  String? _openingDatabaseSummary(List<GameMoveReview> gameMoves) {
    final parts = <String>[];
    GameMoveReview? leftDatabaseMove;
    var sawInitialDatabaseMove = false;

    for (final move in gameMoves) {
      if (move.isDatabaseMove) {
        sawInitialDatabaseMove = true;
        continue;
      }

      if (sawInitialDatabaseMove) {
        leftDatabaseMove = move;
      }
      break;
    }

    if (leftDatabaseMove != null) {
      parts.add(
        'The game left the database around move ${_moveMarker(leftDatabaseMove)} ${leftDatabaseMove.playedSan}.',
      );
    }

    final hasRiskyKnownLine = gameMoves.any(
      (move) =>
          move.isDatabaseMove &&
          !move.isBookMove &&
          (move.quality == MoveQuality.inaccuracy ||
              move.quality == MoveQuality.mistake ||
              move.quality == MoveQuality.blunder),
    );
    if (hasRiskyKnownLine) {
      parts.add(
        'Some moves appear in the database but were still inaccurate according to Stockfish.',
      );
    }

    return parts.isEmpty ? null : parts.join(' ');
  }

  String _moveMarker(GameMoveReview move) {
    return move.playedBy == 'white'
        ? '${move.moveNumber}.'
        : '${move.moveNumber}...';
  }

  String _lossSummary(GameMoveReview move) {
    if (move.isCheckmateMove || move.quality == MoveQuality.checkmate) {
      return 'delivers checkmate';
    }
    if (move.mateDescription != null && move.mateDescription!.isNotEmpty) {
      return move.mateDescription!;
    }
    if (move.isMiss || move.quality == MoveQuality.miss) {
      return move.missReason ?? 'missed a major opportunity';
    }

    return 'lost ${move.displayEvalLoss.toStringAsFixed(1)} pawns';
  }

  String _overallSummary(
    PlayerStats whiteStats,
    PlayerStats blackStats,
    String? openingName,
  ) {
    final openingText = openingName == null || openingName.isEmpty
        ? 'the opening'
        : openingName;
    if (!whiteStats.hasIssues && !blackStats.hasIssues) {
      return 'Both sides handled $openingText steadily, so the lesson is to keep improving small advantages.';
    }
    if (whiteStats.accuracy >= blackStats.accuracy) {
      return 'White was steadier in $openingText and gave away fewer important chances.';
    }
    return 'Black handled $openingText more accurately and punished more of the important moments.';
  }

  String _sideStrength(String side, List<GameMoveReview> gameMoves) {
    final sideMoves = gameMoves.where((move) => move.playedBy == side);
    if (sideMoves.any((move) =>
        move.isCheckmateMove || move.quality == MoveQuality.checkmate)) {
      return '${_sideName(side)} found the decisive checkmate finish.';
    }
    if (sideMoves.any((move) =>
        move.quality == MoveQuality.brilliant ||
        move.quality == MoveQuality.excellent)) {
      return '${_sideName(side)} found at least one strong forcing move.';
    }
    final quietMoves = sideMoves
        .where((move) => move.quality == MoveQuality.good || move.isBookMove)
        .length;
    if (quietMoves >= 3) {
      return '${_sideName(side)} kept several positions stable and avoided forcing weaknesses.';
    }
    return '${_sideName(side)} found playable moves, but the biggest gains came from avoiding major mistakes.';
  }

  String _sideImprovement(String side, List<GameMoveReview> gameMoves) {
    final sideIssues = gameMoves
        .where((move) =>
            move.playedBy == side &&
            (move.quality == MoveQuality.blunder ||
                move.quality == MoveQuality.miss ||
                move.quality == MoveQuality.mistake ||
                move.quality == MoveQuality.inaccuracy))
        .toList();
    if (sideIssues.isEmpty) {
      return '${_sideName(side)} should keep checking tactics before changing the pawn structure.';
    }

    final first = sideIssues.first;
    return '${_sideName(side)} should slow down around move ${first.moveNumber} and compare the engine line with the played move.';
  }

  String _sideName(String side) {
    return side == 'white' ? 'White' : 'Black';
  }
}

class _BookMoveMatch {
  final ExplorerMoveStat stat;
  final String source;

  const _BookMoveMatch(this.stat) : source = 'explorer';
}
