import 'dart:async';
import 'dart:math' as math;

import 'package:chess/chess.dart' as rules;
import 'package:flutter/foundation.dart';

import 'package:chess_trainer/core/chess/move.dart';
import 'package:chess_trainer/features/coach/domain/coach_move_review.dart';
import 'package:chess_trainer/features/coach/domain/move_quality.dart';
import 'package:chess_trainer/features/engine/data/stockfish_engine_service.dart';
import 'package:chess_trainer/features/engine/domain/engine_analysis_result.dart';

class StockfishCoachService {
  final StockfishEngineService _engine;
  final Map<String, CoachMoveReview> _cache = {};

  StockfishCoachService(this._engine);

  void invalidateCache() {
    _cache.clear();
  }

  Future<CoachMoveReview> reviewMove({
    required MoveNode moveNode,
    String? openingName,
    int depth = 14,
  }) async {
    final cacheKey = moveNode.id;
    final cached = _cache[cacheKey];
    if (cached != null) return cached;

    try {
      final fenBefore = moveNode.fenBefore;
      final fenAfter = moveNode.fenAfter;
      final playedUci = moveNode.uci;
      final playedSan = moveNode.san;

      final results = await Future.wait([
        _engine.searchPosition(fenBefore, depth: depth),
        _engine.searchPosition(fenAfter, depth: depth),
      ]);

      final resultBefore = results[0];
      final resultAfter = results[1];

      final evalBefore = _normalizeEval(
        resultBefore.evaluationPawns,
        fenBefore,
      );
      final evalAfter = _normalizeEval(
        resultAfter.evaluationPawns,
        fenAfter,
      );

      final isWhiteMove = _isWhiteMove(fenBefore);
      final isOpeningPhase = _isOpeningPhase(moveNode, openingName);
      final bestMoveUci = resultBefore.bestMoveUci;
      final bestMoveSan = _uciToSan(fenBefore, bestMoveUci);
      final playedMatchesBest = _sameMove(
        playedUci: playedUci,
        playedSan: playedSan,
        bestMoveUci: bestMoveUci,
        bestMoveSan: bestMoveSan,
      );
      final isCheckmateMove = _isCheckmateMove(
        playedSan: playedSan,
        fenAfter: fenAfter,
        bestMoveSan: bestMoveSan,
        playedMatchesBest: playedMatchesBest,
      );
      final hasMateScore = resultBefore.mateIn != null ||
          resultAfter.mateIn != null ||
          isCheckmateMove;
      final mateBefore = _mateAdvantageForMover(
        resultBefore.mateIn,
        isWhiteMove,
      );
      final mateAfter = _mateAdvantageForMover(
        resultAfter.mateIn,
        isWhiteMove,
      );
      final mateDescription = isCheckmateMove
          ? 'delivers checkmate'
          : _mateDescription(
              mateBefore: mateBefore,
              mateAfter: mateAfter,
            );
      final isMateBlunder = isCheckmateMove
          ? false
          : _isMateBlunder(
              mateBefore: mateBefore,
              mateAfter: mateAfter,
            );
      final bestEvalAtPosition = _bestEvalForPosition(resultBefore);
      final playedEvalAfter = _scoreForComparison(resultAfter);
      final evalLoss = isWhiteMove
          ? (bestEvalAtPosition - playedEvalAfter)
          : (playedEvalAfter - bestEvalAtPosition);
      final displayEvalLoss = isCheckmateMove
          ? 0.0
          : _displayEvalLoss(
              rawLoss: evalLoss,
              hasMateScore: hasMateScore,
              isMateBlunder: isMateBlunder,
            );
      final evalSwing = _evalSwingForMover(
        evalBefore: evalBefore,
        evalAfter: evalAfter,
        isWhiteMove: isWhiteMove,
      );
      final pvSan = _pvToSan(fenBefore, resultBefore.principalVariation);

      final quality = isCheckmateMove
          ? MoveQuality.checkmate
          : _classifyQuality(
              evalLoss: displayEvalLoss,
              evalSwing: evalSwing,
              isBestMove: playedMatchesBest,
              bestMoveUci: bestMoveUci,
              hasMateScore: hasMateScore,
              isMateBlunder: isMateBlunder,
              mateBefore: mateBefore,
              mateAfter: mateAfter,
              isOpeningPhase: isOpeningPhase,
            );

      final displayedBestMove =
          bestMoveSan.isNotEmpty ? bestMoveSan : bestMoveUci;

      final fallbackExplanation = _generateFallbackExplanation(
        playedSan: playedSan,
        quality: quality,
        bestMoveDisplay: displayedBestMove,
        evalLoss: displayEvalLoss,
        isBestMove: playedMatchesBest,
        isCheckmateMove: isCheckmateMove,
        mateDescription: mateDescription,
      );

      final review = CoachMoveReview(
        playedSan: playedSan,
        playedUci: playedUci,
        fenBefore: fenBefore,
        fenAfter: fenAfter,
        evalBefore: evalBefore,
        evalAfter: evalAfter,
        evalLoss: displayEvalLoss,
        quality: quality,
        bestMoveUci: bestMoveUci,
        bestMoveSan: bestMoveSan,
        pvLine: pvSan,
        depth: resultBefore.depth,
        openingName: openingName,
        fallbackExplanation: fallbackExplanation,
        hasMateScore: hasMateScore,
        isMateBlunder: isMateBlunder,
        isCheckmateMove: isCheckmateMove,
        mateDescription: mateDescription,
        isOpeningPhase: isOpeningPhase,
      );

      _cache[cacheKey] = review;
      return review;
    } catch (error) {
      debugPrint('coach analysis error: $error');
      return CoachMoveReview(
        playedSan: moveNode.san,
        playedUci: moveNode.uci,
        fenBefore: moveNode.fenBefore,
        fenAfter: moveNode.fenAfter,
        evalBefore: null,
        evalAfter: null,
        evalLoss: null,
        quality: MoveQuality.good,
        bestMoveUci: '',
        pvLine: const [],
        depth: 0,
        openingName: openingName,
        fallbackExplanation: 'Deeper analysis is needed to review this move.',
        isOpeningPhase: _isOpeningPhase(moveNode, openingName),
        error: error.toString(),
      );
    }
  }

  String _uciToSan(String fen, String uci) {
    if (uci.length < 4) return '';
    try {
      final chess = rules.Chess.fromFEN(fen);
      final from = uci.substring(0, 2);
      final to = uci.substring(2, 4);
      final promotion =
          uci.length >= 5 ? uci.substring(4, 5).toLowerCase() : null;

      final moves = chess.moves({'verbose': true}).cast<Map<String, dynamic>>();
      for (final move in moves) {
        if (move['from'] != from || move['to'] != to) continue;
        if (promotion != null) {
          final san = move['san'] as String;
          if (san.contains('=${promotion.toUpperCase()}')) {
            return san;
          }
        } else {
          return move['san'] as String;
        }
      }
      return '';
    } catch (_) {
      return '';
    }
  }

  List<String> _pvToSan(String fen, List<String> pvUci) {
    if (pvUci.isEmpty) return [];
    try {
      final chess = rules.Chess.fromFEN(fen);
      final sanList = <String>[];
      for (final uci in pvUci) {
        if (uci.length < 4) break;
        final from = uci.substring(0, 2);
        final to = uci.substring(2, 4);
        final promotion =
            uci.length >= 5 ? uci.substring(4, 5).toLowerCase() : null;

        final moves =
            chess.moves({'verbose': true}).cast<Map<String, dynamic>>();
        String? san;
        for (final move in moves) {
          if (move['from'] != from || move['to'] != to) continue;
          if (promotion != null) {
            final mSan = move['san'] as String;
            if (mSan.contains('=${promotion.toUpperCase()}')) {
              san = mSan;
              break;
            }
          } else {
            san = move['san'] as String;
            break;
          }
        }

        if (san == null) break;
        sanList.add(san);

        final args = <String, dynamic>{
          'from': from,
          'to': to,
          if (promotion != null) 'promotion': promotion,
        };
        chess.move(args);
      }
      return sanList;
    } catch (_) {
      return pvUci;
    }
  }

  double _normalizeEval(double? eval, String fen) {
    return eval ?? 0.0;
  }

  double _bestEvalForPosition(EngineAnalysisResult result) {
    return _scoreForComparison(result);
  }

  double _scoreForComparison(EngineAnalysisResult result) {
    final mateIn = result.mateIn;
    if (mateIn != null) {
      return mateIn > 0 ? 9.99 : -9.99;
    }

    return result.evaluationPawns ?? 0.0;
  }

  double _displayEvalLoss({
    required double rawLoss,
    required bool hasMateScore,
    required bool isMateBlunder,
  }) {
    if (isMateBlunder) return 9.99;
    final loss = math.max(0.0, rawLoss);
    if (hasMateScore) return loss.clamp(0.0, 9.99).toDouble();
    return loss.clamp(0.0, 9.99).toDouble();
  }

  double _evalSwingForMover({
    required double? evalBefore,
    required double? evalAfter,
    required bool isWhiteMove,
  }) {
    if (evalBefore == null || evalAfter == null) return 0.0;
    return isWhiteMove ? evalAfter - evalBefore : evalBefore - evalAfter;
  }

  int _mateAdvantageForMover(int? mateIn, bool isWhiteMove) {
    if (mateIn == null || mateIn == 0) return 0;
    final moverHasMate = isWhiteMove ? mateIn > 0 : mateIn < 0;
    return moverHasMate ? 1 : -1;
  }

  bool _isMateBlunder({
    required int mateBefore,
    required int mateAfter,
  }) {
    return mateAfter < 0 && mateBefore >= 0 || mateBefore > 0 && mateAfter <= 0;
  }

  String? _mateDescription({
    required int mateBefore,
    required int mateAfter,
  }) {
    if (mateBefore > 0 && mateAfter <= 0) {
      return 'missed forced mate';
    }
    if (mateAfter < 0 && mateBefore >= 0) {
      return 'allows a forced mate';
    }
    if (mateAfter > 0 && mateBefore <= 0) {
      return 'creates a forced mate threat';
    }
    if (mateBefore < 0 && mateAfter >= 0) {
      return 'escapes a mate threat';
    }
    if (mateAfter > 0) return 'keeps a forced mate';
    if (mateAfter < 0) return 'faces a forced mate';
    return null;
  }

  bool _isCheckmateMove({
    required String playedSan,
    required String fenAfter,
    required String bestMoveSan,
    required bool playedMatchesBest,
  }) {
    if (_isMateSan(playedSan)) return true;
    if (playedMatchesBest && _isMateSan(bestMoveSan)) return true;

    try {
      return rules.Chess.fromFEN(fenAfter).in_checkmate;
    } catch (_) {
      return false;
    }
  }

  bool _isMateSan(String san) {
    return san.trim().endsWith('#');
  }

  bool _sameMove({
    required String playedUci,
    required String playedSan,
    required String bestMoveUci,
    required String bestMoveSan,
  }) {
    if (bestMoveUci.isNotEmpty &&
        playedUci.toLowerCase() == bestMoveUci.toLowerCase()) {
      return true;
    }

    return _normalizeSan(playedSan) == _normalizeSan(bestMoveSan);
  }

  String _normalizeSan(String san) {
    return san
        .trim()
        .replaceAll('0-0-0', 'O-O-O')
        .replaceAll('0-0', 'O-O')
        .replaceAll(RegExp(r'[+#?!]'), '');
  }

  bool _isWhiteMove(String fen) {
    final parts = fen.split(RegExp(r'\s+'));
    return parts.length < 2 || parts[1] == 'w';
  }

  MoveQuality _classifyQuality({
    required double evalLoss,
    required double evalSwing,
    required bool isBestMove,
    required String bestMoveUci,
    required bool hasMateScore,
    required bool isMateBlunder,
    required int mateBefore,
    required int mateAfter,
    required bool isOpeningPhase,
  }) {
    if (isBestMove && bestMoveUci.isNotEmpty) {
      if ((hasMateScore && mateAfter > 0 && !isMateBlunder) ||
          evalSwing >= 2.0) {
        return MoveQuality.brilliant;
      }
      return MoveQuality.excellent;
    }

    if (isMateBlunder) return MoveQuality.blunder;

    if (hasMateScore && mateBefore < 0 && mateAfter >= 0) {
      return MoveQuality.brilliant;
    }

    final loss = math.max(0.0, evalLoss);
    if (isOpeningPhase) {
      if (loss > 2.50) return MoveQuality.blunder;
      if (loss >= 1.20) return MoveQuality.mistake;
      if (loss >= 0.60) return MoveQuality.inaccuracy;
      return MoveQuality.good;
    }

    if (loss > 2.00) return MoveQuality.blunder;
    if (loss >= 0.90) return MoveQuality.mistake;
    if (loss >= 0.35) return MoveQuality.inaccuracy;

    return MoveQuality.good;
  }

  bool _isOpeningPhase(MoveNode moveNode, String? openingName) {
    final ply = (moveNode.moveNumber - 1) * 2 + (moveNode.isWhiteMove ? 1 : 2);
    if (ply <= 10) return true;
    return openingName != null && openingName.trim().isNotEmpty && ply <= 14;
  }

  String _generateFallbackExplanation({
    required String playedSan,
    required MoveQuality quality,
    required String bestMoveDisplay,
    required double evalLoss,
    required bool isBestMove,
    required bool isCheckmateMove,
    String? mateDescription,
  }) {
    final mateText =
        mateDescription == null ? '' : ' This involves a $mateDescription.';
    switch (quality) {
      case MoveQuality.checkmate:
        return '$playedSan is the winning move. It ends the game immediately by checkmate, so there is no better continuation. Lesson: always look for forcing moves - checks, captures, and threats - especially near the enemy king.';
      case MoveQuality.brilliant:
        return '$playedSan is a brilliant move! It finds a forcing idea and gives you a clear advantage.$mateText Keep looking for tactics, checks, captures, and threats.';
      case MoveQuality.excellent:
        return '$playedSan is a strong move. It keeps your position healthy and improves your pieces without creating weaknesses.$mateText';
      case MoveQuality.good:
        return '$playedSan is a solid move. It maintains a stable position without significant disadvantage. Focus on developing pieces and controlling the center.';
      case MoveQuality.inaccuracy:
        final lossPawns = evalLoss.toStringAsFixed(2);
        return '$playedSan is slightly inaccurate. It does not lose immediately, but $bestMoveDisplay improves your position more.$mateText Try to compare candidate moves before committing. (eval loss: $lossPawns pawns)';
      case MoveQuality.mistake:
        final lossPawns = evalLoss.toStringAsFixed(2);
        return '$playedSan is a mistake. It gives the opponent a stronger response. $bestMoveDisplay was better because it keeps your position stable.$mateText Before attacking or capturing, check your opponent\'s forcing replies. (eval loss: $lossPawns pawns)';
      case MoveQuality.blunder:
        if (mateDescription != null && !isCheckmateMove) {
          return '$playedSan is a blunder because it $mateDescription. The better move was $bestMoveDisplay, which keeps the position safer. Always check forcing moves before deciding.';
        }
        final lossPawns = evalLoss.toStringAsFixed(2);
        return '$playedSan is a blunder because it changes the position sharply against you. The better move was $bestMoveDisplay, which keeps the position safer. After $playedSan, your evaluation drops by $lossPawns pawns, meaning you likely lose material, initiative, or king safety.';
    }
  }
}
