import 'dart:async';
import 'dart:math' as math;

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

      final bestEvalAtPosition = _bestEvalForPosition(
        resultBefore,
        fenBefore,
      );
      final playedEvalAfter = evalAfter;

      final isWhiteMove = _isWhiteMove(fenBefore);
      final evalLoss = isWhiteMove
          ? (bestEvalAtPosition - playedEvalAfter)
          : (playedEvalAfter - bestEvalAtPosition);

      final quality = _classifyQuality(
        evalLoss: evalLoss,
        isBestMove: playedUci == resultBefore.bestMoveUci,
        bestMoveUci: resultBefore.bestMoveUci,
        mateBefore: resultBefore.mateIn,
        mateAfter: resultAfter.mateIn,
      );

      final fallbackExplanation = _generateFallbackExplanation(
        playedSan: playedSan,
        quality: quality,
        bestMoveUci: resultBefore.bestMoveUci,
        evalLoss: evalLoss,
        isBestMove: playedUci == resultBefore.bestMoveUci,
      );

      final review = CoachMoveReview(
        playedSan: playedSan,
        playedUci: playedUci,
        fenBefore: fenBefore,
        fenAfter: fenAfter,
        evalBefore: evalBefore,
        evalAfter: evalAfter,
        evalLoss: math.max(0.0, evalLoss),
        quality: quality,
        bestMoveUci: resultBefore.bestMoveUci,
        pvLine: resultBefore.principalVariation,
        depth: resultBefore.depth,
        openingName: openingName,
        fallbackExplanation: fallbackExplanation,
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
        error: error.toString(),
      );
    }
  }

  double _normalizeEval(double? eval, String fen) {
    return eval ?? 0.0;
  }

  double _bestEvalForPosition(
    EngineAnalysisResult result,
    String fen,
  ) {
    final eval = _normalizeEval(result.evaluationPawns, fen);
    if (result.mateIn != null) {
      return result.mateIn! > 0 ? 100.0 : -100.0;
    }
    return eval;
  }

  bool _isWhiteMove(String fen) {
    final parts = fen.split(RegExp(r'\s+'));
    return parts.length < 2 || parts[1] == 'w';
  }

  MoveQuality _classifyQuality({
    required double evalLoss,
    required bool isBestMove,
    required String bestMoveUci,
    required int? mateBefore,
    required int? mateAfter,
  }) {
    if (isBestMove && bestMoveUci.isNotEmpty) {
      if (evalLoss.abs() < 0.01) return MoveQuality.brilliant;
      return MoveQuality.excellent;
    }

    if (mateBefore != null && mateAfter != null) {
      if (mateBefore > 0 && mateAfter <= 0) return MoveQuality.blunder;
      if (mateBefore < 0 && mateAfter >= 0) return MoveQuality.brilliant;
    }

    if (mateBefore == null && mateAfter != null && mateAfter < 0) {
      return MoveQuality.blunder;
    }

    final loss = evalLoss.abs();
    if (loss >= 3.0) return MoveQuality.blunder;
    if (loss >= 1.0) return MoveQuality.mistake;
    if (loss >= 0.3) return MoveQuality.inaccuracy;

    return MoveQuality.good;
  }

  String _generateFallbackExplanation({
    required String playedSan,
    required MoveQuality quality,
    required String bestMoveUci,
    required double evalLoss,
    required bool isBestMove,
  }) {
    switch (quality) {
      case MoveQuality.brilliant:
        return '$playedSan is a brilliant move! '
            'Stockfish confirms it is the best move in this position.';
      case MoveQuality.excellent:
        return '$playedSan is an excellent move. '
            'It matches or closely follows the top engine recommendation.';
      case MoveQuality.good:
        return '$playedSan is a solid move. '
            'It maintains a stable position without significant disadvantage.';
      case MoveQuality.inaccuracy:
        final lossPawns = evalLoss.toStringAsFixed(2);
        return '$playedSan is an inaccuracy '
            '(eval loss: $lossPawns pawns). '
            'Consider $bestMoveUci instead, '
            'which would have given a better position.';
      case MoveQuality.mistake:
        final lossPawns = evalLoss.toStringAsFixed(2);
        return '$playedSan is a mistake '
            '(eval loss: $lossPawns pawns). '
            'Stockfish recommends $bestMoveUci '
            'to maintain a stronger position.';
      case MoveQuality.blunder:
        return '$playedSan is a blunder! '
            'Stockfish strongly recommends $bestMoveUci '
            'instead. This move significantly worsened the position.';
    }
  }
}
