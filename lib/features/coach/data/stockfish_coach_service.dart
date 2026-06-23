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

      final bestEvalAtPosition = _bestEvalForPosition(
        resultBefore,
        fenBefore,
      );
      final playedEvalAfter = evalAfter;

      final isWhiteMove = _isWhiteMove(fenBefore);
      final evalLoss = isWhiteMove
          ? (bestEvalAtPosition - playedEvalAfter)
          : (playedEvalAfter - bestEvalAtPosition);

      final bestMoveUci = resultBefore.bestMoveUci;
      final bestMoveSan = _uciToSan(fenBefore, bestMoveUci);
      final pvSan = _pvToSan(fenBefore, resultBefore.principalVariation);

      final quality = _classifyQuality(
        evalLoss: evalLoss,
        isBestMove: playedUci == bestMoveUci,
        bestMoveUci: bestMoveUci,
        mateBefore: resultBefore.mateIn,
        mateAfter: resultAfter.mateIn,
      );

      final displayedBestMove =
          bestMoveSan.isNotEmpty ? bestMoveSan : bestMoveUci;

      final fallbackExplanation = _generateFallbackExplanation(
        playedSan: playedSan,
        quality: quality,
        bestMoveDisplay: displayedBestMove,
        evalLoss: evalLoss,
        isBestMove: playedUci == bestMoveUci,
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
        bestMoveUci: bestMoveUci,
        bestMoveSan: bestMoveSan,
        pvLine: pvSan,
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
    required String bestMoveDisplay,
    required double evalLoss,
    required bool isBestMove,
  }) {
    switch (quality) {
      case MoveQuality.brilliant:
        return '$playedSan is a brilliant move! It finds the strongest idea in the position and gives you a clear advantage. Keep looking for tactical shots and forcing sequences like this.';
      case MoveQuality.excellent:
        return '$playedSan is a strong move. It keeps your position healthy and follows the engine recommendation. The idea is to improve your pieces without creating weaknesses.';
      case MoveQuality.good:
        return '$playedSan is a solid move. It maintains a stable position without significant disadvantage. Focus on developing pieces and controlling the center.';
      case MoveQuality.inaccuracy:
        final lossPawns = evalLoss.toStringAsFixed(2);
        return '$playedSan is slightly inaccurate. It does not lose immediately, but $bestMoveDisplay improves your position more. Try to develop pieces, control the center, and avoid moving the same piece too many times early. (eval loss: $lossPawns pawns)';
      case MoveQuality.mistake:
        final lossPawns = evalLoss.toStringAsFixed(2);
        return '$playedSan is a mistake. It may look active, but it gives the opponent a stronger response. $bestMoveDisplay was better because it keeps your position stable and follows the engine main line. Before capturing or attacking, check if your piece can be challenged or if your opponent gains tempo. (eval loss: $lossPawns pawns)';
      case MoveQuality.blunder:
        final lossPawns = evalLoss.toStringAsFixed(2);
        return '$playedSan is a blunder because it changes the position sharply against you. The better move was $bestMoveDisplay, which keeps the position safer. After $playedSan, your evaluation drops by $lossPawns pawns, meaning you likely lose material, initiative, or king safety.';
    }
  }
}
