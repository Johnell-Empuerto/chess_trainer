import 'dart:convert';
import 'dart:io';

import 'package:chess/chess.dart' as rules;
import 'package:chess_trainer/core/database/app_database.dart';
import 'package:sqlite3/sqlite3.dart';

const _maxIndexedPlies = 40;
const _pendingFlushRows = 30000;
const _progressInterval = Duration(seconds: 2);

Future<void> main(List<String> args) async {
  final sourceFile = AppDatabase.resolvedSourcePgnFile;
  final databaseFile = AppDatabase.explorerDatabaseFile;
  final manifestFile = AppDatabase.explorerManifestFile;
  final tempDatabaseFile = File('${databaseFile.absolute.path}.tmp');

  if (!await sourceFile.exists()) {
    stderr.writeln('PGN source not found: ${sourceFile.absolute.path}');
    exitCode = 1;
    return;
  }

  await databaseFile.parent.create(recursive: true);
  await _deleteIfExists(tempDatabaseFile);
  await _deleteSqliteSidecars(tempDatabaseFile);

  final startedAt = DateTime.now().toUtc();
  var db = sqlite3.open(tempDatabaseFile.absolute.path);
  var dbDisposed = false;

  try {
    _configureBuildDatabase(db);
    AppDatabase.resetExplorerSchema(db);

    stdout.writeln('Building explorer database from ${sourceFile.path}');
    stdout.writeln('Writing temporary database to ${tempDatabaseFile.path}');

    final buildStats = await _buildFromPgn(
      db: db,
      sourceFile: sourceFile,
    );

    stdout.writeln('Creating lookup indexes...');
    AppDatabase.ensureExplorerIndexes(db);

    final indexedPositions = db
        .select(
          'SELECT COUNT(DISTINCT position_key) AS total FROM explorer_moves;',
        )
        .first['total'] as int;
    final indexedRows = db
        .select(
          'SELECT COUNT(*) AS total FROM explorer_moves;',
        )
        .first['total'] as int;
    final completedAt = DateTime.now().toUtc();

    _writeMetadata(
      db,
      {
        'schema_version': AppDatabase.explorerSchemaVersion.toString(),
        'source_pgn': sourceFile.absolute.path,
        'database': databaseFile.absolute.path,
        'manifest': manifestFile.absolute.path,
        'built_at': completedAt.toIso8601String(),
        'started_at': startedAt.toIso8601String(),
        'max_indexed_plies': _maxIndexedPlies.toString(),
        'imported_games': buildStats.importedGames.toString(),
        'skipped_games': buildStats.skippedGames.toString(),
        'indexed_positions': indexedPositions.toString(),
        'indexed_rows': indexedRows.toString(),
        'indexed_ply_occurrences': buildStats.indexedPlyOccurrences.toString(),
        'source_bytes': buildStats.sourceBytes.toString(),
      },
    );

    db.execute('PRAGMA optimize;');
    db.dispose();
    dbDisposed = true;

    await _deleteIfExists(databaseFile);
    await _deleteSqliteSidecars(databaseFile);
    await tempDatabaseFile.rename(databaseFile.absolute.path);

    await _writeManifest(
      manifestFile: manifestFile,
      sourceFile: sourceFile,
      databaseFile: databaseFile,
      startedAt: startedAt,
      completedAt: completedAt,
      importedGames: buildStats.importedGames,
      skippedGames: buildStats.skippedGames,
      indexedPositions: indexedPositions,
      indexedRows: indexedRows,
      indexedPlyOccurrences: buildStats.indexedPlyOccurrences,
      sourceBytes: buildStats.sourceBytes,
    );

    stdout.writeln(
      'Done: ${buildStats.importedGames} games, '
      '$indexedPositions positions, $indexedRows move rows.',
    );
  } catch (error, stackTrace) {
    stderr.writeln('Explorer database build failed: $error');
    stderr.writeln(stackTrace);
    if (!dbDisposed) {
      db.dispose();
    }
    await _deleteIfExists(tempDatabaseFile);
    await _deleteSqliteSidecars(tempDatabaseFile);
    exitCode = 1;
  }
}

void _configureBuildDatabase(Database db) {
  db.execute('PRAGMA journal_mode = OFF;');
  db.execute('PRAGMA synchronous = OFF;');
  db.execute('PRAGMA temp_store = MEMORY;');
  db.execute('PRAGMA locking_mode = EXCLUSIVE;');
  db.execute('PRAGMA foreign_keys = OFF;');
}

Future<_BuildStats> _buildFromPgn({
  required Database db,
  required File sourceFile,
}) async {
  final totalBytes = await sourceFile.length();
  var bytesRead = 0;
  var importedGames = 0;
  var skippedGames = 0;
  var indexedPlyOccurrences = 0;
  var lastProgressAt = DateTime.now();
  final headers = <String, String>{};
  final moveText = StringBuffer();
  final pending = <String, _PendingMoveStat>{};

  Future<void> flushPending() async {
    if (pending.isEmpty) return;

    db.execute('BEGIN IMMEDIATE TRANSACTION;');
    final statement = db.prepare('''
      INSERT INTO explorer_moves (
        position_key,
        move_san,
        move_uci,
        games_count,
        white_wins,
        draws,
        black_wins,
        avg_white_elo,
        avg_black_elo,
        white_elo_games,
        black_elo_games
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(position_key, move_san, move_uci) DO UPDATE SET
        games_count = explorer_moves.games_count + excluded.games_count,
        white_wins = explorer_moves.white_wins + excluded.white_wins,
        draws = explorer_moves.draws + excluded.draws,
        black_wins = explorer_moves.black_wins + excluded.black_wins,
        avg_white_elo = CASE
          WHEN explorer_moves.white_elo_games + excluded.white_elo_games = 0
            THEN NULL
          ELSE (
            COALESCE(explorer_moves.avg_white_elo, 0)
              * explorer_moves.white_elo_games
            + COALESCE(excluded.avg_white_elo, 0)
              * excluded.white_elo_games
          ) / (
            explorer_moves.white_elo_games + excluded.white_elo_games
          )
        END,
        avg_black_elo = CASE
          WHEN explorer_moves.black_elo_games + excluded.black_elo_games = 0
            THEN NULL
          ELSE (
            COALESCE(explorer_moves.avg_black_elo, 0)
              * explorer_moves.black_elo_games
            + COALESCE(excluded.avg_black_elo, 0)
              * excluded.black_elo_games
          ) / (
            explorer_moves.black_elo_games + excluded.black_elo_games
          )
        END,
        white_elo_games =
          explorer_moves.white_elo_games + excluded.white_elo_games,
        black_elo_games =
          explorer_moves.black_elo_games + excluded.black_elo_games;
    ''');

    try {
      for (final stat in pending.values) {
        statement.execute([
          stat.positionKey,
          stat.moveSan,
          stat.moveUci,
          stat.gamesCount,
          stat.whiteWins,
          stat.draws,
          stat.blackWins,
          stat.avgWhiteElo,
          stat.avgBlackElo,
          stat.whiteEloGames,
          stat.blackEloGames,
        ]);
      }
      db.execute('COMMIT;');
    } catch (_) {
      db.execute('ROLLBACK;');
      rethrow;
    } finally {
      statement.dispose();
      pending.clear();
    }
  }

  void printProgress() {
    final percent = totalBytes == 0 ? 0 : bytesRead * 100 / totalBytes;
    stdout.writeln(
      '${percent.toStringAsFixed(1)}% | games=$importedGames | '
      'skipped=$skippedGames | pending=${pending.length}',
    );
  }

  Future<void> finishGame() async {
    if (moveText.isEmpty) {
      headers.clear();
      return;
    }

    try {
      final result = _gameResult(headers, moveText.toString());
      final indexedGame = result == null
          ? null
          : _indexGame(
              headers: headers,
              rawMoveText: moveText.toString(),
              result: result,
              maxIndexedPlies: _maxIndexedPlies,
            );

      if (indexedGame == null || indexedGame.indexedPlies == 0) {
        skippedGames++;
      } else {
        _mergePending(pending, indexedGame.moves);
        importedGames++;
        indexedPlyOccurrences += indexedGame.indexedPlies;
      }
    } catch (_) {
      skippedGames++;
    } finally {
      headers.clear();
      moveText.clear();
    }

    if (pending.length >= _pendingFlushRows || importedGames % 5000 == 0) {
      await flushPending();
    }

    final now = DateTime.now();
    if (now.difference(lastProgressAt) >= _progressInterval) {
      lastProgressAt = now;
      printProgress();
    }
  }

  await for (final originalLine
      in sourceFile.openRead().transform(latin1.decoder).transform(
            const LineSplitter(),
          )) {
    bytesRead += latin1.encode(originalLine).length + 1;

    if (originalLine.startsWith('%')) {
      continue;
    }

    final line = _stripSemicolonComment(originalLine).trimRight();
    if (line.trim().isEmpty) {
      if (moveText.isNotEmpty) {
        await finishGame();
      }
      continue;
    }

    final headerMatch =
        RegExp(r'^\[([A-Za-z0-9_]+)\s+"(.*)"\]\s*$').firstMatch(line);
    if (headerMatch != null) {
      if (moveText.isNotEmpty) {
        await finishGame();
      }
      headers[headerMatch.group(1)!] = _unescapeHeaderValue(
        headerMatch.group(2)!,
      );
      continue;
    }

    moveText
      ..write(' ')
      ..write(line);
  }

  if (moveText.isNotEmpty) {
    await finishGame();
  }

  await flushPending();
  printProgress();

  return _BuildStats(
    importedGames: importedGames,
    skippedGames: skippedGames,
    indexedPlyOccurrences: indexedPlyOccurrences,
    sourceBytes: totalBytes,
  );
}

_IndexedGame? _indexGame({
  required Map<String, String> headers,
  required String rawMoveText,
  required _GameResult result,
  required int maxIndexedPlies,
}) {
  final chess = rules.Chess();
  final initialFen = headers['FEN'];

  if (initialFen != null && initialFen.isNotEmpty && !chess.load(initialFen)) {
    return null;
  }

  final whiteElo = int.tryParse(headers['WhiteElo'] ?? '');
  final blackElo = int.tryParse(headers['BlackElo'] ?? '');
  final tokens = _moveTokens(rawMoveText);
  final gameMoves = <String, _PendingMoveStat>{};
  var indexedPlies = 0;

  for (final token in tokens) {
    if (_isResultToken(token)) break;
    if (indexedPlies >= maxIndexedPlies) break;

    final move = _matchingVerboseMove(chess, token);
    if (move == null) return null;

    final positionKey = AppDatabase.positionKeyFromFen(chess.fen);
    final san = move['san'] as String;
    final from = move['from'] as String;
    final to = move['to'] as String;
    final promotion = _promotionFromMove(move);
    final uci = '$from$to${promotion ?? ''}';
    final key = '$positionKey\u0001$san\u0001$uci';

    gameMoves.update(
      key,
      (stat) => stat.addGame(
        result: result,
        whiteElo: whiteElo,
        blackElo: blackElo,
      ),
      ifAbsent: () => _PendingMoveStat.fromGame(
        positionKey: positionKey,
        moveSan: san,
        moveUci: uci,
        result: result,
        whiteElo: whiteElo,
        blackElo: blackElo,
      ),
    );

    final moveMap = <String, String>{
      'from': from,
      'to': to,
      if (promotion != null) 'promotion': promotion,
    };

    if (!chess.move(moveMap)) return null;
    indexedPlies++;
  }

  return _IndexedGame(moves: gameMoves, indexedPlies: indexedPlies);
}

void _mergePending(
  Map<String, _PendingMoveStat> target,
  Map<String, _PendingMoveStat> source,
) {
  for (final entry in source.entries) {
    target.update(
      entry.key,
      (stat) => stat.merge(entry.value),
      ifAbsent: () => entry.value,
    );
  }
}

List<String> _moveTokens(String rawMoveText) {
  var text = rawMoveText
      .replaceAll(RegExp(r'\{[^}]*\}', dotAll: true), ' ')
      .replaceAll(RegExp(r'<[^>]*>', dotAll: true), ' ')
      .replaceAll(RegExp(r'\$\d+'), ' ')
      .replaceAll(RegExp(r'\d+\.{1,3}'), ' ');

  var previous = '';
  while (previous != text) {
    previous = text;
    text = text.replaceAll(RegExp(r'\([^()]*\)', dotAll: true), ' ');
  }

  return text
      .split(RegExp(r'\s+'))
      .map((token) => token.trim())
      .where((token) => token.isNotEmpty && token != '...')
      .toList();
}

Map<String, dynamic>? _matchingVerboseMove(rules.Chess chess, String rawToken) {
  final target = _sanComparable(rawToken);
  final moves = chess.moves({'verbose': true}).cast<Map<String, dynamic>>();

  for (final move in moves) {
    if (_sanComparable(move['san'] as String) == target) {
      return move;
    }
  }

  return null;
}

String _sanComparable(String san) {
  return san
      .replaceAll('0-0-0', 'O-O-O')
      .replaceAll('0-0', 'O-O')
      .replaceAll(RegExp(r'[+#?!]+'), '')
      .replaceAll(RegExp(r'e\.p\.$'), '')
      .trim();
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

String _stripSemicolonComment(String line) {
  final index = line.indexOf(';');
  if (index == -1) return line;
  return line.substring(0, index);
}

String _unescapeHeaderValue(String value) {
  return value.replaceAll(r'\"', '"').replaceAll(r'\\', '\\');
}

_GameResult? _gameResult(Map<String, String> headers, String moveText) {
  final headerResult = headers['Result'];
  if (headerResult != null && _isResultToken(headerResult)) {
    return _resultFromToken(headerResult);
  }

  for (final token in _moveTokens(moveText).reversed) {
    if (_isResultToken(token)) {
      return _resultFromToken(token);
    }
  }

  return null;
}

_GameResult? _resultFromToken(String token) {
  switch (token) {
    case '1-0':
      return _GameResult.whiteWin;
    case '0-1':
      return _GameResult.blackWin;
    case '1/2-1/2':
      return _GameResult.draw;
    default:
      return null;
  }
}

bool _isResultToken(String token) {
  return token == '1-0' || token == '0-1' || token == '1/2-1/2' || token == '*';
}

void _writeMetadata(Database db, Map<String, String> values) {
  db.execute('BEGIN IMMEDIATE TRANSACTION;');
  final statement = db.prepare('''
    INSERT INTO explorer_metadata (key, value)
    VALUES (?, ?)
    ON CONFLICT(key) DO UPDATE SET value = excluded.value;
  ''');

  try {
    for (final entry in values.entries) {
      statement.execute([entry.key, entry.value]);
    }
    db.execute('COMMIT;');
  } catch (_) {
    db.execute('ROLLBACK;');
    rethrow;
  } finally {
    statement.dispose();
  }
}

Future<void> _writeManifest({
  required File manifestFile,
  required File sourceFile,
  required File databaseFile,
  required DateTime startedAt,
  required DateTime completedAt,
  required int importedGames,
  required int skippedGames,
  required int indexedPositions,
  required int indexedRows,
  required int indexedPlyOccurrences,
  required int sourceBytes,
}) async {
  final manifest = <String, Object?>{
    'schema_version': AppDatabase.explorerSchemaVersion,
    'source_pgn': sourceFile.absolute.path,
    'database': databaseFile.absolute.path,
    'built_at': completedAt.toIso8601String(),
    'started_at': startedAt.toIso8601String(),
    'max_indexed_plies': _maxIndexedPlies,
    'imported_games': importedGames,
    'skipped_games': skippedGames,
    'indexed_positions': indexedPositions,
    'indexed_rows': indexedRows,
    'indexed_ply_occurrences': indexedPlyOccurrences,
    'source_bytes': sourceBytes,
  };

  const encoder = JsonEncoder.withIndent('  ');
  await manifestFile.writeAsString('${encoder.convert(manifest)}\n');
}

Future<void> _deleteIfExists(File file) async {
  if (await file.exists()) {
    await file.delete();
  }
}

Future<void> _deleteSqliteSidecars(File databaseFile) async {
  await _deleteIfExists(File('${databaseFile.absolute.path}-wal'));
  await _deleteIfExists(File('${databaseFile.absolute.path}-shm'));
}

enum _GameResult { whiteWin, draw, blackWin }

class _BuildStats {
  final int importedGames;
  final int skippedGames;
  final int indexedPlyOccurrences;
  final int sourceBytes;

  const _BuildStats({
    required this.importedGames,
    required this.skippedGames,
    required this.indexedPlyOccurrences,
    required this.sourceBytes,
  });
}

class _IndexedGame {
  final Map<String, _PendingMoveStat> moves;
  final int indexedPlies;

  const _IndexedGame({
    required this.moves,
    required this.indexedPlies,
  });
}

class _PendingMoveStat {
  final String positionKey;
  final String moveSan;
  final String moveUci;
  final int gamesCount;
  final int whiteWins;
  final int draws;
  final int blackWins;
  final int whiteEloTotal;
  final int whiteEloGames;
  final int blackEloTotal;
  final int blackEloGames;

  const _PendingMoveStat({
    required this.positionKey,
    required this.moveSan,
    required this.moveUci,
    required this.gamesCount,
    required this.whiteWins,
    required this.draws,
    required this.blackWins,
    required this.whiteEloTotal,
    required this.whiteEloGames,
    required this.blackEloTotal,
    required this.blackEloGames,
  });

  factory _PendingMoveStat.fromGame({
    required String positionKey,
    required String moveSan,
    required String moveUci,
    required _GameResult result,
    required int? whiteElo,
    required int? blackElo,
  }) {
    return _PendingMoveStat(
      positionKey: positionKey,
      moveSan: moveSan,
      moveUci: moveUci,
      gamesCount: 0,
      whiteWins: 0,
      draws: 0,
      blackWins: 0,
      whiteEloTotal: 0,
      whiteEloGames: 0,
      blackEloTotal: 0,
      blackEloGames: 0,
    ).addGame(
      result: result,
      whiteElo: whiteElo,
      blackElo: blackElo,
    );
  }

  double? get avgWhiteElo {
    if (whiteEloGames == 0) return null;
    return whiteEloTotal / whiteEloGames;
  }

  double? get avgBlackElo {
    if (blackEloGames == 0) return null;
    return blackEloTotal / blackEloGames;
  }

  _PendingMoveStat addGame({
    required _GameResult result,
    required int? whiteElo,
    required int? blackElo,
  }) {
    return copyWith(
      gamesCount: gamesCount + 1,
      whiteWins: whiteWins + (result == _GameResult.whiteWin ? 1 : 0),
      draws: draws + (result == _GameResult.draw ? 1 : 0),
      blackWins: blackWins + (result == _GameResult.blackWin ? 1 : 0),
      whiteEloTotal: whiteEloTotal + (whiteElo ?? 0),
      whiteEloGames: whiteEloGames + (whiteElo == null ? 0 : 1),
      blackEloTotal: blackEloTotal + (blackElo ?? 0),
      blackEloGames: blackEloGames + (blackElo == null ? 0 : 1),
    );
  }

  _PendingMoveStat merge(_PendingMoveStat other) {
    return copyWith(
      gamesCount: gamesCount + other.gamesCount,
      whiteWins: whiteWins + other.whiteWins,
      draws: draws + other.draws,
      blackWins: blackWins + other.blackWins,
      whiteEloTotal: whiteEloTotal + other.whiteEloTotal,
      whiteEloGames: whiteEloGames + other.whiteEloGames,
      blackEloTotal: blackEloTotal + other.blackEloTotal,
      blackEloGames: blackEloGames + other.blackEloGames,
    );
  }

  _PendingMoveStat copyWith({
    int? gamesCount,
    int? whiteWins,
    int? draws,
    int? blackWins,
    int? whiteEloTotal,
    int? whiteEloGames,
    int? blackEloTotal,
    int? blackEloGames,
  }) {
    return _PendingMoveStat(
      positionKey: positionKey,
      moveSan: moveSan,
      moveUci: moveUci,
      gamesCount: gamesCount ?? this.gamesCount,
      whiteWins: whiteWins ?? this.whiteWins,
      draws: draws ?? this.draws,
      blackWins: blackWins ?? this.blackWins,
      whiteEloTotal: whiteEloTotal ?? this.whiteEloTotal,
      whiteEloGames: whiteEloGames ?? this.whiteEloGames,
      blackEloTotal: blackEloTotal ?? this.blackEloTotal,
      blackEloGames: blackEloGames ?? this.blackEloGames,
    );
  }
}
