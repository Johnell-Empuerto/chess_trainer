import 'dart:convert';

import 'package:chess/chess.dart' as rules;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:chess_trainer/core/database/app_database.dart';
import 'package:chess_trainer/features/explorer/domain/opening_name.dart';

class OpeningNameService {
  static const bool debugOpeningNames = false;
  static const _assetPath = 'assets/openings/eco_openings.json';
  static Future<_OpeningIndex>? _cachedIndex;

  Future<void> preload() async {
    await _loadIndex();
  }

  Future<OpeningName?> matchOpening({
    required String currentFen,
    required List<String> sanMoveHistory,
  }) async {
    final startedAt = debugOpeningNames ? DateTime.now() : null;
    final normalizedHistory = _normalizeSanHistory(sanMoveHistory);
    final positionCandidates =
        AppDatabase.positionKeyCandidatesFromFen(currentFen);

    _debugStart(
      currentFen: currentFen,
      sanMoveHistory: sanMoveHistory,
      positionCandidates: positionCandidates,
    );

    if (normalizedHistory.isEmpty) {
      _debugResult('starting position', OpeningName.startingPosition);
      _debugElapsed(startedAt);
      return OpeningName.startingPosition;
    }

    final index = await _loadIndex();

    for (final candidate in positionCandidates) {
      final positionMatch = index.openingByPositionKey[candidate];
      if (positionMatch != null) {
        _debugResult('position', positionMatch, detail: candidate);
        _debugElapsed(startedAt);
        return positionMatch;
      }
    }

    final sanMatch = _matchBySanPrefix(
      index: index,
      normalizedHistory: normalizedHistory,
    );
    if (sanMatch != null) {
      _debugResult('SAN prefix', sanMatch);
      _debugElapsed(startedAt);
      return sanMatch;
    }

    final fallbackMatch = _matchByFallback(
      index: index,
      normalizedHistory: normalizedHistory,
    );
    if (fallbackMatch != null) {
      _debugResult('fallback', fallbackMatch);
      _debugElapsed(startedAt);
      return fallbackMatch;
    }

    _debugResult('none', null);
    _debugElapsed(startedAt);
    return null;
  }

  Future<_OpeningIndex> _loadIndex() {
    final cached = _cachedIndex;
    if (cached != null) return cached;

    final created = _readIndex();
    _cachedIndex = created;
    return created;
  }

  Future<_OpeningIndex> _readIndex() async {
    try {
      final rawJson = await rootBundle.loadString(_assetPath);
      final payload = await compute(_buildOpeningIndexPayload, rawJson);
      return _OpeningIndex.fromPayload(payload);
    } catch (error) {
      if (debugOpeningNames) {
        debugPrint('[Openings] load failed: $error');
      }

      return _OpeningIndex.fromPayload(
        _buildOpeningIndexPayloadFromOpeningJson(const []),
      );
    }
  }

  OpeningName? _matchBySanPrefix({
    required _OpeningIndex index,
    required List<String> normalizedHistory,
  }) {
    for (var length = normalizedHistory.length; length > 0; length--) {
      final key = _sanKey(normalizedHistory.sublist(0, length));
      final match = index.openingBySanKey[key];
      if (match != null) return match;
    }

    return null;
  }

  OpeningName? _matchByFallback({
    required _OpeningIndex index,
    required List<String> normalizedHistory,
  }) {
    for (var length = normalizedHistory.length; length > 1; length--) {
      final key = _sanKey(normalizedHistory.sublist(0, length));
      final match = index.fallbackOpeningBySanKey[key];
      if (match != null) return match;
    }

    return index.fallbackOpeningBySanKey[_sanKey([normalizedHistory.first])];
  }

  List<String> _normalizeSanHistory(List<String> sanMoveHistory) {
    return sanMoveHistory
        .map(_normalizeSanMove)
        .where((move) => move.isNotEmpty)
        .toList(growable: false);
  }

  void _debugStart({
    required String currentFen,
    required List<String> sanMoveHistory,
    required List<String> positionCandidates,
  }) {
    if (!debugOpeningNames) return;

    debugPrint('[Openings] currentFen: $currentFen');
    debugPrint('[Openings] sanMoveHistory: $sanMoveHistory');
    debugPrint('[Openings] position candidates: $positionCandidates');
  }

  void _debugResult(String source, OpeningName? opening, {String? detail}) {
    if (!debugOpeningNames) return;

    final detailText = detail == null ? '' : ' ($detail)';
    debugPrint('[Openings] matched by $source$detailText');
    debugPrint(
      '[Openings] final opening: ${opening?.displayName ?? 'Unknown Opening'}',
    );
  }

  void _debugElapsed(DateTime? startedAt) {
    if (!debugOpeningNames || startedAt == null) return;

    final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
    debugPrint('[Openings] resolve ms: $elapsedMs');
  }
}

Map<String, Object?> _buildOpeningIndexPayload(String rawJson) {
  final decoded = jsonDecode(rawJson) as List<dynamic>;
  final openingJson = decoded
      .map((item) => (item as Map<dynamic, dynamic>).cast<String, dynamic>())
      .toList(growable: false);

  return _buildOpeningIndexPayloadFromOpeningJson(openingJson);
}

Map<String, Object?> _buildOpeningIndexPayloadFromOpeningJson(
  List<Map<String, dynamic>> sourceOpeningJson,
) {
  final openingJson = _withBroadFallbackOpenings(sourceOpeningJson);
  final positionIndex = <String, int>{};
  final sanPrefixIndex = <String, int>{};
  final fallbackSanIndex = <String, int>{};
  final fallbackKeys = _broadFallbackOpeningJson
      .map((opening) => _sanKey(_normalizedMovesFromJson(opening)))
      .toSet();

  for (var i = 0; i < openingJson.length; i++) {
    final opening = OpeningName.fromJson(openingJson[i]);
    final normalizedMoves = opening.moves
        .map(_normalizeSanMove)
        .where((move) => move.isNotEmpty)
        .toList(growable: false);
    if (normalizedMoves.isEmpty) continue;

    final sanKey = _sanKey(normalizedMoves);
    _putBestOpeningIndex(
      sanPrefixIndex,
      key: sanKey,
      candidateIndex: i,
      openingJson: openingJson,
    );

    if (fallbackKeys.contains(sanKey)) {
      _putBestOpeningIndex(
        fallbackSanIndex,
        key: sanKey,
        candidateIndex: i,
        openingJson: openingJson,
      );
    }

    final positionKeys = _positionKeysForOpening(opening);
    if (positionKeys.isEmpty) continue;

    for (final positionKey in positionKeys) {
      _putBestOpeningIndex(
        positionIndex,
        key: positionKey,
        candidateIndex: i,
        openingJson: openingJson,
      );
    }
  }

  return {
    'openings': openingJson,
    'positionIndex': positionIndex,
    'sanPrefixIndex': sanPrefixIndex,
    'fallbackSanIndex': fallbackSanIndex,
  };
}

List<Map<String, dynamic>> _withBroadFallbackOpenings(
  List<Map<String, dynamic>> sourceOpeningJson,
) {
  final openingJson = sourceOpeningJson.map(_copyOpeningJson).toList();
  final seenSanKeys = <String, int>{};

  for (var i = 0; i < openingJson.length; i++) {
    final key = _sanKey(_normalizedMovesFromJson(openingJson[i]));
    seenSanKeys.putIfAbsent(key, () => i);
  }

  for (final fallbackOpening in _broadFallbackOpeningJson) {
    final key = _sanKey(_normalizedMovesFromJson(fallbackOpening));
    final existingIndex = seenSanKeys[key];
    if (existingIndex == null) {
      openingJson.add(_copyOpeningJson(fallbackOpening));
      seenSanKeys[key] = openingJson.length - 1;
    } else {
      openingJson[existingIndex] = _copyOpeningJson(fallbackOpening);
    }
  }

  return openingJson;
}

Map<String, dynamic> _copyOpeningJson(Map<String, Object?> opening) {
  return {
    'eco': opening['eco'] as String,
    'name': opening['name'] as String,
    'moves': List<String>.from(opening['moves'] as List<dynamic>),
  };
}

List<String> _normalizedMovesFromJson(Map<String, Object?> opening) {
  return (opening['moves'] as List<dynamic>)
      .cast<String>()
      .map(_normalizeSanMove)
      .where((move) => move.isNotEmpty)
      .toList(growable: false);
}

void _putBestOpeningIndex(
  Map<String, int> target, {
  required String key,
  required int candidateIndex,
  required List<Map<String, dynamic>> openingJson,
}) {
  final existingIndex = target[key];
  if (existingIndex == null ||
      _openingDepth(openingJson[candidateIndex]) >
          _openingDepth(openingJson[existingIndex])) {
    target[key] = candidateIndex;
  }
}

int _openingDepth(Map<String, dynamic> opening) {
  return (opening['moves'] as List<dynamic>).length;
}

List<String> _positionKeysForOpening(OpeningName opening) {
  final chess = rules.Chess();

  for (final san in opening.moves) {
    final move = _matchingVerboseMove(chess, san);
    if (move == null) {
      return const [];
    }

    final promotion = _promotionFromMove(move);
    final success = chess.move({
      'from': move['from'] as String,
      'to': move['to'] as String,
      if (promotion != null) 'promotion': promotion,
    });

    if (!success) {
      return const [];
    }
  }

  return AppDatabase.positionKeyCandidatesFromFen(chess.fen);
}

Map<String, dynamic>? _matchingVerboseMove(rules.Chess chess, String rawSan) {
  final target = _normalizeSanMove(rawSan);
  final moves = chess.moves({'verbose': true}).cast<Map<String, dynamic>>();

  for (final move in moves) {
    if (_normalizeSanMove(move['san'] as String) == target) {
      return move;
    }
  }

  return null;
}

String? _promotionFromMove(Map<String, dynamic> move) {
  final promotion = move['promotion'];
  if (promotion is String && promotion.isNotEmpty) {
    return promotion.toLowerCase();
  }

  final san = move['san'] as String;
  final match = RegExp(r'=([QRBN])').firstMatch(san);
  return match?.group(1)?.toLowerCase();
}

String _normalizeSanMove(String san) {
  return san
      .trim()
      .replaceAll('0-0-0', 'O-O-O')
      .replaceAll('0-0', 'O-O')
      .replaceAll(RegExp(r'[+#?!]'), '');
}

String _sanKey(Iterable<String> moves) {
  return moves.join('\u0001');
}

class _OpeningIndex {
  final List<OpeningName> openings;
  final Map<String, OpeningName> openingByPositionKey;
  final Map<String, OpeningName> openingBySanKey;
  final Map<String, OpeningName> fallbackOpeningBySanKey;

  const _OpeningIndex({
    required this.openings,
    required this.openingByPositionKey,
    required this.openingBySanKey,
    required this.fallbackOpeningBySanKey,
  });

  factory _OpeningIndex.fromPayload(Map<String, Object?> payload) {
    final openingMaps =
        (payload['openings'] as List<dynamic>).cast<Map<dynamic, dynamic>>();
    final openings = openingMaps
        .map(
          (item) => OpeningName.fromJson(
            item.cast<String, dynamic>(),
          ),
        )
        .toList(growable: false);

    return _OpeningIndex(
      openings: openings,
      openingByPositionKey: _mapOpeningsByIndex(
        openings,
        payload['positionIndex'] as Map<dynamic, dynamic>,
      ),
      openingBySanKey: _mapOpeningsByIndex(
        openings,
        payload['sanPrefixIndex'] as Map<dynamic, dynamic>,
      ),
      fallbackOpeningBySanKey: _mapOpeningsByIndex(
        openings,
        payload['fallbackSanIndex'] as Map<dynamic, dynamic>,
      ),
    );
  }

  static Map<String, OpeningName> _mapOpeningsByIndex(
    List<OpeningName> openings,
    Map<dynamic, dynamic> rawIndex,
  ) {
    final openingByKey = <String, OpeningName>{};

    for (final entry in rawIndex.entries) {
      final key = entry.key as String;
      final index = entry.value as int;
      if (index >= 0 && index < openings.length) {
        openingByKey[key] = openings[index];
      }
    }

    return openingByKey;
  }
}

const _broadFallbackOpeningJson = <Map<String, Object>>[
  {
    'eco': 'B00',
    'name': "King's Pawn Opening",
    'moves': <String>['e4'],
  },
  {
    'eco': 'D00',
    'name': "Queen's Pawn Game",
    'moves': <String>['d4'],
  },
  {
    'eco': 'A10',
    'name': 'English Opening',
    'moves': <String>['c4'],
  },
  {
    'eco': 'A04',
    'name': 'Zukertort Opening',
    'moves': <String>['Nf3'],
  },
  {
    'eco': 'C20',
    'name': "King's Pawn Game",
    'moves': <String>['e4', 'e5'],
  },
  {
    'eco': 'B20',
    'name': 'Sicilian Defense',
    'moves': <String>['e4', 'c5'],
  },
  {
    'eco': 'C00',
    'name': 'French Defense',
    'moves': <String>['e4', 'e6'],
  },
  {
    'eco': 'B10',
    'name': 'Caro-Kann Defense',
    'moves': <String>['e4', 'c6'],
  },
  {
    'eco': 'B01',
    'name': 'Scandinavian Defense',
    'moves': <String>['e4', 'd5'],
  },
  {
    'eco': 'D06',
    'name': "Queen's Gambit",
    'moves': <String>['d4', 'd5', 'c4'],
  },
];
