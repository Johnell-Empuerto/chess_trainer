import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:chess/chess.dart' as rules;
import 'package:sqlite3/sqlite3.dart';

import 'package:chess_trainer/core/database/app_database.dart';
import 'package:chess_trainer/features/explorer/domain/explorer_import_status.dart';

class GameDatabaseImportSession {
  final Stream<ExplorerImportStatus> statuses;
  final Future<void> Function() cancel;

  const GameDatabaseImportSession({
    required this.statuses,
    required this.cancel,
  });
}

class GameDatabaseImportService {
  GameDatabaseImportSession startImport({
    required String sourcePgnPath,
    required String sourceBz2Path,
    required String databasePath,
  }) {
    final receivePort = ReceivePort();
    final controller = StreamController<ExplorerImportStatus>.broadcast();
    Isolate? isolate;
    SendPort? controlPort;
    var closed = false;

    void closePorts() {
      if (closed) return;
      closed = true;
      receivePort.close();
      unawaited(controller.close());
    }

    receivePort.listen((message) {
      if (message is SendPort) {
        controlPort = message;
        return;
      }

      if (message is Map) {
        final status = ExplorerImportStatus.fromMap(message);
        controller.add(status);

        if (status.state != ExplorerImportState.importing) {
          closePorts();
        }
      }
    });

    Isolate.spawn(
      _importEntryPoint,
      {
        'sendPort': receivePort.sendPort,
        'sourcePgnPath': sourcePgnPath,
        'sourceBz2Path': sourceBz2Path,
        'databasePath': databasePath,
      },
      debugName: 'opening-explorer-import',
    ).then((spawnedIsolate) {
      isolate = spawnedIsolate;
    }).catchError((Object error) {
      controller.add(
        ExplorerImportStatus.error(
          sourcePgnPath: sourcePgnPath,
          sourceBz2Path: sourceBz2Path,
          databasePath: databasePath,
          message: error.toString(),
        ),
      );
      closePorts();
    });

    return GameDatabaseImportSession(
      statuses: controller.stream,
      cancel: () async {
        controlPort?.send('cancel');
        await Future<void>.delayed(const Duration(milliseconds: 250));
        isolate?.kill(priority: Isolate.beforeNextEvent);
      },
    );
  }
}

Future<void> _importEntryPoint(Map<String, Object?> args) async {
  final sendPort = args['sendPort']! as SendPort;
  final sourcePgnPath = args['sourcePgnPath']! as String;
  final sourceBz2Path = args['sourceBz2Path']! as String;
  final databasePath = args['databasePath']! as String;
  final controlPort = ReceivePort();
  var cancelled = false;

  sendPort.send(controlPort.sendPort);
  controlPort.listen((message) {
    if (message == 'cancel') {
      cancelled = true;
    }
  });

  Database? db;

  void sendStatus(
    ExplorerImportState state, {
    int importedGames = 0,
    int indexedPositions = 0,
    int indexedMoveRows = 0,
    int bytesRead = 0,
    int totalBytes = 0,
    required String statusText,
  }) {
    sendPort.send(
      ExplorerImportStatus(
        state: state,
        sourcePgnPath: sourcePgnPath,
        sourceBz2Path: sourceBz2Path,
        databasePath: databasePath,
        importedGames: importedGames,
        indexedPositions: indexedPositions,
        indexedMoveRows: indexedMoveRows,
        bytesRead: bytesRead,
        totalBytes: totalBytes,
        statusText: statusText,
      ).toMap(),
    );
  }

  try {
    final pgnFile = File(sourcePgnPath);
    final bz2File = File(sourceBz2Path);

    if (!await pgnFile.exists()) {
      final message = await bz2File.exists()
          ? 'Please extract the .bz2 file to .pgn inside chessdatabase/.'
          : 'PGN source file not found.';
      sendStatus(
        await bz2File.exists()
            ? ExplorerImportState.needsExtraction
            : ExplorerImportState.error,
        statusText: message,
      );
      return;
    }

    await File(databasePath).parent.create(recursive: true);
    db = sqlite3.open(databasePath);
    AppDatabase.ensureExplorerSchema(db);

    db.execute('PRAGMA journal_mode = WAL;');
    db.execute('PRAGMA synchronous = NORMAL;');
    db.execute('PRAGMA temp_store = MEMORY;');
    db.execute('PRAGMA foreign_keys = OFF;');
    db.execute('DELETE FROM explorer_move_stats;');
    db.execute('DELETE FROM explorer_import_meta;');

    final totalBytes = await pgnFile.length();
    var bytesRead = 0;
    var importedGames = 0;
    var indexedMoveRows = 0;
    var lastProgressAt = DateTime.now();
    final headers = <String, String>{};
    final moveText = StringBuffer();
    final pending = <String, _PendingMoveStat>{};

    sendStatus(
      ExplorerImportState.importing,
      totalBytes: totalBytes,
      statusText: 'Importing PGN database...',
    );

    Future<void> flushPending() async {
      if (pending.isEmpty || db == null) return;

      final database = db;
      database.execute('BEGIN IMMEDIATE TRANSACTION;');
      final statement = database.prepare('''
        INSERT INTO explorer_move_stats (
          position_key,
          move_san,
          move_uci,
          games_count,
          white_wins,
          draws,
          black_wins,
          white_elo_total,
          white_elo_games,
          black_elo_total,
          black_elo_games
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(position_key, move_san, move_uci) DO UPDATE SET
          games_count = games_count + excluded.games_count,
          white_wins = white_wins + excluded.white_wins,
          draws = draws + excluded.draws,
          black_wins = black_wins + excluded.black_wins,
          white_elo_total = white_elo_total + excluded.white_elo_total,
          white_elo_games = white_elo_games + excluded.white_elo_games,
          black_elo_total = black_elo_total + excluded.black_elo_total,
          black_elo_games = black_elo_games + excluded.black_elo_games;
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
            stat.whiteEloTotal,
            stat.whiteEloGames,
            stat.blackEloTotal,
            stat.blackEloGames,
          ]);
        }
        database.execute('COMMIT;');
      } catch (_) {
        database.execute('ROLLBACK;');
        rethrow;
      } finally {
        statement.dispose();
        pending.clear();
      }
    }

    Future<void> finishGame() async {
      if (moveText.isEmpty) {
        headers.clear();
        return;
      }

      final result = _gameResult(headers, moveText.toString());
      if (result != null) {
        final indexedMoves = _indexGame(
          headers: headers,
          rawMoveText: moveText.toString(),
          result: result,
          pending: pending,
        );

        if (indexedMoves > 0) {
          importedGames++;
          indexedMoveRows += indexedMoves;
        }
      }

      headers.clear();
      moveText.clear();

      if (pending.length >= 25000 || importedGames % 500 == 0) {
        await flushPending();
      }

      final now = DateTime.now();
      if (now.difference(lastProgressAt).inMilliseconds >= 350) {
        lastProgressAt = now;
        sendStatus(
          ExplorerImportState.importing,
          importedGames: importedGames,
          indexedMoveRows: indexedMoveRows,
          bytesRead: bytesRead,
          totalBytes: totalBytes,
          statusText: 'Importing PGN database...',
        );
      }
    }

    await for (final originalLine
        in pgnFile.openRead().transform(latin1.decoder).transform(
              const LineSplitter(),
            )) {
      if (cancelled) break;

      bytesRead += originalLine.length + 1;
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
        headers[headerMatch.group(1)!] = headerMatch.group(2)!;
        continue;
      }

      moveText.write(' ');
      moveText.write(line);
    }

    if (!cancelled && moveText.isNotEmpty) {
      await finishGame();
    }

    await flushPending();

    if (cancelled) {
      sendStatus(
        ExplorerImportState.cancelled,
        importedGames: importedGames,
        indexedMoveRows: indexedMoveRows,
        bytesRead: bytesRead,
        totalBytes: totalBytes,
        statusText: 'Database import cancelled.',
      );
      return;
    }

    final indexedPositions = db
        .select(
            'SELECT COUNT(DISTINCT position_key) AS total FROM explorer_move_stats')
        .first['total'] as int;
    final indexedRows = db
        .select('SELECT COUNT(*) AS total FROM explorer_move_stats')
        .first['total'] as int;

    db.execute('BEGIN IMMEDIATE TRANSACTION;');
    _setMeta(db, 'imported', 'true');
    _setMeta(db, 'source_pgn_path', sourcePgnPath);
    _setMeta(db, 'imported_games', importedGames.toString());
    _setMeta(db, 'indexed_positions', indexedPositions.toString());
    _setMeta(db, 'indexed_rows', indexedRows.toString());
    _setMeta(db, 'imported_at', DateTime.now().toIso8601String());
    db.execute('COMMIT;');

    sendStatus(
      ExplorerImportState.imported,
      importedGames: importedGames,
      indexedPositions: indexedPositions,
      indexedMoveRows: indexedRows,
      bytesRead: totalBytes,
      totalBytes: totalBytes,
      statusText: 'Database imported.',
    );
  } catch (error) {
    sendStatus(
      ExplorerImportState.error,
      statusText: error.toString(),
    );
  } finally {
    db?.dispose();
    controlPort.close();
  }
}

int _indexGame({
  required Map<String, String> headers,
  required String rawMoveText,
  required _GameResult result,
  required Map<String, _PendingMoveStat> pending,
}) {
  final chess = rules.Chess();
  final initialFen = headers['FEN'];

  if (initialFen != null && initialFen.isNotEmpty && !chess.load(initialFen)) {
    return 0;
  }

  final whiteElo = int.tryParse(headers['WhiteElo'] ?? '');
  final blackElo = int.tryParse(headers['BlackElo'] ?? '');
  final tokens = _moveTokens(rawMoveText);
  var indexedMoves = 0;

  for (final token in tokens) {
    if (_isResultToken(token)) break;

    final move = _matchingVerboseMove(chess, token);
    if (move == null) break;

    final positionKey = AppDatabase.positionKeyFromFen(chess.fen);
    final san = move['san'] as String;
    final from = move['from'] as String;
    final to = move['to'] as String;
    final promotion = _promotionFromSan(san);
    final uci = '$from$to${promotion ?? ''}';
    final key = '$positionKey\u0001$san\u0001$uci';

    pending.update(
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

    if (!chess.move(moveMap)) break;
    indexedMoves++;
  }

  return indexedMoves;
}

List<String> _moveTokens(String rawMoveText) {
  var text = rawMoveText
      .replaceAll(RegExp(r'\{[^}]*\}', dotAll: true), ' ')
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
      .replaceAll(RegExp(r'[+#?!]+$'), '')
      .trim();
}

String? _promotionFromSan(String san) {
  final match = RegExp(r'=([QRBN])').firstMatch(san);
  return match?.group(1)?.toLowerCase();
}

String _stripSemicolonComment(String line) {
  final index = line.indexOf(';');
  if (index == -1) return line;
  return line.substring(0, index);
}

_GameResult? _gameResult(Map<String, String> headers, String moveText) {
  final result = headers['Result'] ?? _moveTokens(moveText).lastOrNull;

  switch (result) {
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

void _setMeta(Database db, String key, String value) {
  db.execute(
    '''
    INSERT INTO explorer_import_meta (key, value)
    VALUES (?, ?)
    ON CONFLICT(key) DO UPDATE SET value = excluded.value;
    ''',
    [key, value],
  );
}

enum _GameResult { whiteWin, draw, blackWin }

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
    return const _PendingMoveStat(
      positionKey: '',
      moveSan: '',
      moveUci: '',
      gamesCount: 0,
      whiteWins: 0,
      draws: 0,
      blackWins: 0,
      whiteEloTotal: 0,
      whiteEloGames: 0,
      blackEloTotal: 0,
      blackEloGames: 0,
    )
        .copyWith(
          positionKey: positionKey,
          moveSan: moveSan,
          moveUci: moveUci,
        )
        .addGame(
          result: result,
          whiteElo: whiteElo,
          blackElo: blackElo,
        );
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

  _PendingMoveStat copyWith({
    String? positionKey,
    String? moveSan,
    String? moveUci,
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
      positionKey: positionKey ?? this.positionKey,
      moveSan: moveSan ?? this.moveSan,
      moveUci: moveUci ?? this.moveUci,
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

extension _LastOrNull<T> on List<T> {
  T? get lastOrNull => isEmpty ? null : last;
}
