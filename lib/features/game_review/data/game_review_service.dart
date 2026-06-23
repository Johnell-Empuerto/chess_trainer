import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:chess_trainer/core/chess/move.dart';
import 'package:chess_trainer/features/coach/data/ai_explainer_service.dart';
import 'package:chess_trainer/features/coach/data/stockfish_coach_service.dart';
import 'package:chess_trainer/features/coach/domain/move_quality.dart';
import 'package:chess_trainer/features/game_review/domain/game_move_review.dart';
import 'package:chess_trainer/features/game_review/domain/game_review_report.dart';
import 'package:chess_trainer/features/game_review/domain/training_theme.dart';

class GameReviewService {
  final StockfishCoachService _coachService;
  final AiExplainerService? _aiService;

  GameReviewService({
    required StockfishCoachService coachService,
    AiExplainerService? aiService,
  })  : _coachService = coachService,
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
        final moveNumber = node.moveNumber;
        final playedBy = node.colorName;
        final evalLoss = _safeEvalLoss(coachReview.evalLoss);
        final evalSwing = _evalSwingForMover(
          evalBefore: coachReview.evalBefore,
          evalAfter: coachReview.evalAfter,
          playedBy: playedBy,
        );
        final isBookMove = _isBookLikeMove(
          plyIndex: i + 1,
          openingName: openingName,
          evalLoss: evalLoss,
          hasMateScore: coachReview.hasMateScore,
        );
        final quality = _qualityForGameReview(
          coachReview.quality,
          evalLoss: evalLoss,
          isBookMove: isBookMove,
          hasMateScore: coachReview.hasMateScore,
          isMateBlunder: coachReview.isMateBlunder,
          isCheckmateMove: coachReview.isCheckmateMove,
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
          openingMoveNote: isBookMove
              ? 'This is playable opening theory, even if Stockfish slightly prefers another move.'
              : null,
          hasMateScore: coachReview.hasMateScore,
          isMateBlunder: coachReview.isMateBlunder,
          isCheckmateMove: coachReview.isCheckmateMove,
          mateDescription: coachReview.mateDescription,
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

  bool _isBookLikeMove({
    required int plyIndex,
    required String? openingName,
    required double evalLoss,
    required bool hasMateScore,
  }) {
    if (hasMateScore) return false;
    if (openingName == null || openingName.trim().isEmpty) return false;
    return plyIndex <= 10 && evalLoss < 2.5;
  }

  MoveQuality _qualityForGameReview(
    MoveQuality original, {
    required double evalLoss,
    required bool isBookMove,
    required bool hasMateScore,
    required bool isMateBlunder,
    required bool isCheckmateMove,
  }) {
    if (isCheckmateMove || original == MoveQuality.checkmate) {
      return MoveQuality.checkmate;
    }
    if (isMateBlunder) return MoveQuality.blunder;
    if (isBookMove) {
      if (evalLoss > 2.5) return MoveQuality.blunder;
      if (evalLoss >= 1.2) return MoveQuality.mistake;
      return MoveQuality.good;
    }

    if (hasMateScore) return original;
    if (evalLoss > 2.0) return MoveQuality.blunder;
    if (evalLoss >= 0.9) return MoveQuality.mistake;
    if (evalLoss >= 0.35) return MoveQuality.inaccuracy;
    return original == MoveQuality.brilliant ||
            original == MoveQuality.excellent
        ? original
        : MoveQuality.good;
  }

  PlayerStats _computeStats(List<GameMoveReview> moves) {
    if (moves.isEmpty) {
      return const PlayerStats(
        accuracy: 0,
        bestCount: 0,
        excellentCount: 0,
        goodCount: 0,
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
    if (move.displayEvalLoss >= 2.0) return true;

    switch (move.quality) {
      case MoveQuality.checkmate:
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
        whiteStats.mistakeCount +
        whiteStats.blunderCount +
        blackStats.inaccuracyCount +
        blackStats.mistakeCount +
        blackStats.blunderCount;

    if (totalIssues >= 3) themes.add(TrainingTheme.tactics);

    if (moves.length > 30) {
      final last10 = moves.skip(moves.length - 10).toList();
      final endgameIssues = last10
          .where((m) =>
              m.quality == MoveQuality.mistake ||
              m.quality == MoveQuality.blunder)
          .length;
      if (endgameIssues >= 2) themes.add(TrainingTheme.endgame);
    }

    final earlyMoves = moves.take(10).toList();
    final openingIssues = earlyMoves
        .where((m) =>
            !m.isBookMove &&
            (m.quality == MoveQuality.inaccuracy ||
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
    final turningPoint = criticalMoves.isEmpty
        ? 'No single move decided the game; both sides mostly kept the balance.'
        : 'Move ${criticalMoves.first.moveNumber} ${criticalMoves.first.playedSan} was the key moment because ${_lossSummary(criticalMoves.first)}.';
    final focus = themes.isEmpty ? null : themes.first;
    final trainingFocus = focus == null
        ? 'Review candidate moves before committing.'
        : '${focus.label} - ${focus.description}';
    final coachTemplate = [
      '1. Overall: ${_overallSummary(whiteStats, blackStats, openingName)}',
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
    return '${stats.blunderCount} blunders, ${stats.mistakeCount} mistakes, ${stats.inaccuracyCount} inaccuracies';
  }

  String _lossSummary(GameMoveReview move) {
    if (move.isCheckmateMove || move.quality == MoveQuality.checkmate) {
      return 'delivers checkmate';
    }
    if (move.mateDescription != null && move.mateDescription!.isNotEmpty) {
      return move.mateDescription!;
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
