import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:chess_trainer/core/database/app_database.dart';
import 'package:chess_trainer/features/explorer/domain/explorer_import_status.dart';
import 'package:chess_trainer/features/explorer/domain/explorer_move_stat.dart';
import 'package:chess_trainer/features/explorer/domain/explorer_query_result.dart';

class PrebuiltExplorerRepository {
  static const bool debugExplorer = false;
  static const int _maxCachedPositions = 500;

  Database? _db;
  _ExplorerSchema? _schema;
  final LinkedHashMap<String, ExplorerQueryResult> _queryCache =
      LinkedHashMap<String, ExplorerQueryResult>();

  String get sourcePgnPath => '';
  String get databasePath =>
      AppDatabase.resolvedExplorerDatabaseFile.absolute.path;
  String get manifestPath => '';

  Future<ExplorerImportStatus> loadStatus() async {
    if (!await File(databasePath).exists()) {
      return ExplorerImportStatus.notImported(
        sourcePgnPath: sourcePgnPath,
        databasePath: databasePath,
        manifestPath: manifestPath,
        checkedDatabasePaths: AppDatabase.explorerDatabaseCandidatePaths,
      );
    }

    try {
      final db = _openDatabase();
      final schema = _currentSchema(db);

      return ExplorerImportStatus.imported(
        sourcePgnPath: sourcePgnPath,
        databasePath: databasePath,
        manifestPath: manifestPath,
        importedGames: _metadataInt(db, 'imported_games'),
        indexedPositions: _metadataInt(db, 'indexed_positions'),
        indexedMoveRows: _metadataInt(db, 'indexed_rows'),
        statusText: schema == _ExplorerSchema.legacySchema
            ? 'Explorer database loaded using legacy schema.'
            : 'Explorer database ready.',
      );
    } catch (error) {
      dispose();
      return ExplorerImportStatus.error(
        sourcePgnPath: sourcePgnPath,
        databasePath: databasePath,
        manifestPath: manifestPath,
        message: error.toString(),
      );
    }
  }

  Future<ExplorerQueryResult> queryForFen(
    String fen, {
    int limit = 15,
  }) async {
    final startedAt = debugExplorer ? DateTime.now() : null;
    final db = _openDatabase();
    final schema = _currentSchema(db);
    final candidates = AppDatabase.positionKeyCandidatesFromFen(fen);

    _debug('[Explorer] FEN: $fen');
    _debug('[Explorer] candidates: $candidates');
    _debug('[Explorer] schema: ${_schemaLabel(schema)}');

    for (final candidate in candidates) {
      final cached = _cachedResult(schema, candidate, limit);
      if (cached != null && cached.moves.isNotEmpty) {
        _debug('[Explorer] matched key: ${cached.positionKey} (cache)');
        _debug('[Explorer] rows: ${cached.moves.length}');
        _debugElapsed(startedAt);
        return cached;
      }
    }

    ExplorerQueryResult? firstEmptyResult;

    for (final candidate in candidates) {
      final cached = _cachedResult(schema, candidate, limit);
      if (cached != null) {
        firstEmptyResult ??= cached;
        continue;
      }

      final result = _queryPositionKey(
        db,
        schema: schema,
        positionKey: candidate,
        limit: limit,
      );
      _cacheResult(schema, limit, result);

      if (result.moves.isNotEmpty) {
        _debug('[Explorer] matched key: ${result.positionKey}');
        _debug('[Explorer] rows: ${result.moves.length}');
        _debugElapsed(startedAt);
        return result;
      }

      firstEmptyResult ??= result;
    }

    final emptyResult = firstEmptyResult ??
        const ExplorerQueryResult(
          positionKey: '',
          moves: [],
          totalGames: 0,
        );
    _debug('[Explorer] matched key: none');
    _debug('[Explorer] rows: 0');
    _debugElapsed(startedAt);
    return emptyResult;
  }

  Future<List<ExplorerMoveStat>> movesForFen(
    String fen, {
    int limit = 15,
  }) async {
    return (await queryForFen(fen, limit: limit)).moves;
  }

  Future<int> totalGamesForFen(String fen) async {
    return (await queryForFen(fen)).totalGames;
  }

  String positionKeyFromFen(String fen) {
    return AppDatabase.positionKeyFromFen(fen);
  }

  void dispose() {
    _db?.dispose();
    _db = null;
    _schema = null;
    _queryCache.clear();
  }

  ExplorerQueryResult _queryPositionKey(
    Database db, {
    required _ExplorerSchema schema,
    required String positionKey,
    required int limit,
  }) {
    final resultSet = db.select(
      _movesQuery(schema),
      [positionKey, limit],
    );
    final moves = resultSet
        .map((row) => _moveStatFromRow(row, positionKey: positionKey))
        .toList(growable: false);
    final totalGames = moves.isEmpty
        ? 0
        : _totalGamesForPositionKey(
            db,
            schema: schema,
            positionKey: positionKey,
          );

    return ExplorerQueryResult(
      positionKey: positionKey,
      moves: moves,
      totalGames: totalGames,
    );
  }

  int _totalGamesForPositionKey(
    Database db, {
    required _ExplorerSchema schema,
    required String positionKey,
  }) {
    final row = db.select(
      _totalGamesQuery(schema),
      [positionKey],
    ).first;

    return row['total'] as int;
  }

  ExplorerQueryResult? _cachedResult(
    _ExplorerSchema schema,
    String positionKey,
    int limit,
  ) {
    final key = _cacheKey(schema, positionKey, limit);
    final result = _queryCache.remove(key);
    if (result == null) return null;

    _queryCache[key] = result;
    return result;
  }

  void _cacheResult(
    _ExplorerSchema schema,
    int limit,
    ExplorerQueryResult result,
  ) {
    _queryCache[_cacheKey(schema, result.positionKey, limit)] = result;

    while (_queryCache.length > _maxCachedPositions) {
      _queryCache.remove(_queryCache.keys.first);
    }
  }

  String _cacheKey(_ExplorerSchema schema, String positionKey, int limit) {
    return '${schema.name}|$limit|$positionKey';
  }

  Database _openDatabase() {
    final existing = _db;
    if (existing != null) return existing;

    final file = File(databasePath);
    if (!file.existsSync()) {
      throw StateError(
        _missingDatabaseMessage(),
      );
    }

    final db = sqlite3.open(file.absolute.path);
    db.execute('PRAGMA query_only = ON;');
    _schema = _detectSchema(db);
    _db = db;
    return db;
  }

  String _missingDatabaseMessage() {
    final lines = <String>[
      'Explorer database not found. Checked:',
      '',
      for (var i = 0;
          i < AppDatabase.explorerDatabaseCandidatePaths.length;
          i++)
        '${i + 1}. ${AppDatabase.explorerDatabaseCandidatePaths[i]}',
    ];

    return lines.join('\n');
  }

  _ExplorerSchema _currentSchema(Database db) {
    return _schema ??= _detectSchema(db);
  }

  _ExplorerSchema _detectSchema(Database db) {
    if (_tableOrViewExists(db, 'explorer_moves')) {
      _validateColumns(
        db,
        tableName: 'explorer_moves',
        requiredColumns: const {
          'position_key',
          'move_san',
          'move_uci',
          'games_count',
          'white_wins',
          'draws',
          'black_wins',
          'avg_white_elo',
          'avg_black_elo',
        },
      );
      return _ExplorerSchema.newSchema;
    }

    if (_tableOrViewExists(db, 'explorer_move_stats')) {
      _validateColumns(
        db,
        tableName: 'explorer_move_stats',
        requiredColumns: const {
          'position_key',
          'move_san',
          'move_uci',
          'games_count',
          'white_wins',
          'draws',
          'black_wins',
          'white_elo_total',
          'white_elo_games',
          'black_elo_total',
          'black_elo_games',
        },
      );
      return _ExplorerSchema.legacySchema;
    }

    throw StateError(
      'Invalid explorer database: expected explorer_moves or explorer_move_stats table.',
    );
  }

  bool _tableOrViewExists(Database db, String name) {
    final result = db.select(
      '''
      SELECT name
      FROM sqlite_master
      WHERE type IN ('table', 'view') AND name = ?
      LIMIT 1;
      ''',
      [name],
    );

    return result.isNotEmpty;
  }

  void _validateColumns(
    Database db, {
    required String tableName,
    required Set<String> requiredColumns,
  }) {
    final columns = db
        .select('PRAGMA table_info($tableName);')
        .map((row) => row['name'] as String)
        .toSet();
    final missingColumns = requiredColumns.difference(columns);

    if (missingColumns.isNotEmpty) {
      throw StateError(
        'Invalid explorer database: $tableName missing ${missingColumns.join(', ')}.',
      );
    }
  }

  String _movesQuery(_ExplorerSchema schema) {
    switch (schema) {
      case _ExplorerSchema.newSchema:
        return '''
          SELECT
            move_san,
            move_uci,
            games_count,
            white_wins,
            draws,
            black_wins,
            avg_white_elo,
            avg_black_elo
          FROM explorer_moves
          WHERE position_key = ?
          ORDER BY games_count DESC
          LIMIT ?;
        ''';
      case _ExplorerSchema.legacySchema:
        return '''
          SELECT
            move_san,
            move_uci,
            games_count,
            white_wins,
            draws,
            black_wins,
            CASE
              WHEN white_elo_games > 0
                THEN white_elo_total * 1.0 / white_elo_games
              ELSE NULL
            END AS avg_white_elo,
            CASE
              WHEN black_elo_games > 0
                THEN black_elo_total * 1.0 / black_elo_games
              ELSE NULL
            END AS avg_black_elo
          FROM explorer_move_stats
          WHERE position_key = ?
          ORDER BY games_count DESC
          LIMIT ?;
        ''';
    }
  }

  String _totalGamesQuery(_ExplorerSchema schema) {
    switch (schema) {
      case _ExplorerSchema.newSchema:
        return '''
          SELECT COALESCE(SUM(games_count), 0) AS total
          FROM explorer_moves
          WHERE position_key = ?;
        ''';
      case _ExplorerSchema.legacySchema:
        return '''
          SELECT COALESCE(SUM(games_count), 0) AS total
          FROM explorer_move_stats
          WHERE position_key = ?;
        ''';
    }
  }

  int _metadataInt(Database db, String key) {
    final value = _metadataValue(db, key);
    return int.tryParse(value ?? '') ?? 0;
  }

  String? _metadataValue(Database db, String key) {
    final metadataTable = _metadataTable(db);
    if (metadataTable == null) return null;

    final result = db.select(
      'SELECT value FROM $metadataTable WHERE key = ? LIMIT 1;',
      [key],
    );
    if (result.isEmpty) return null;
    return result.first['value'] as String?;
  }

  String? _metadataTable(Database db) {
    if (_tableOrViewExists(db, 'explorer_metadata')) {
      return 'explorer_metadata';
    }
    if (_tableOrViewExists(db, 'explorer_import_meta')) {
      return 'explorer_import_meta';
    }
    return null;
  }

  ExplorerMoveStat _moveStatFromRow(
    Row row, {
    required String positionKey,
  }) {
    return ExplorerMoveStat(
      positionKey: positionKey,
      moveSan: row['move_san'] as String,
      moveUci: row['move_uci'] as String,
      gamesCount: row['games_count'] as int,
      whiteWins: row['white_wins'] as int,
      draws: row['draws'] as int,
      blackWins: row['black_wins'] as int,
      avgWhiteElo: _doubleOrNull(row['avg_white_elo']),
      avgBlackElo: _doubleOrNull(row['avg_black_elo']),
    );
  }

  double? _doubleOrNull(Object? value) {
    if (value == null) return null;
    if (value is int) return value.toDouble();
    if (value is double) return value;
    return double.tryParse(value.toString());
  }

  String _schemaLabel(_ExplorerSchema schema) {
    switch (schema) {
      case _ExplorerSchema.newSchema:
        return 'new';
      case _ExplorerSchema.legacySchema:
        return 'legacy';
    }
  }

  void _debug(String message) {
    if (debugExplorer) {
      debugPrint(message);
    }
  }

  void _debugElapsed(DateTime? startedAt) {
    if (!debugExplorer || startedAt == null) return;

    final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
    debugPrint('[Explorer] query ms: $elapsedMs');
  }
}

enum _ExplorerSchema {
  newSchema,
  legacySchema,
}
