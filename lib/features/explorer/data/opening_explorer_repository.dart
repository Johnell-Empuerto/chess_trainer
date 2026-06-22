import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'package:chess_trainer/core/database/app_database.dart';
import 'package:chess_trainer/features/explorer/data/game_database_import_service.dart';
import 'package:chess_trainer/features/explorer/domain/explorer_import_status.dart';
import 'package:chess_trainer/features/explorer/domain/explorer_move_stat.dart';

class OpeningExplorerRepository {
  final GameDatabaseImportService _importService;
  Database? _db;

  OpeningExplorerRepository({
    GameDatabaseImportService? importService,
  }) : _importService = importService ?? GameDatabaseImportService();

  String get sourcePgnPath => AppDatabase.sourcePgnFile.absolute.path;
  String get sourceBz2Path => AppDatabase.sourceBz2File.absolute.path;
  String get databasePath => AppDatabase.explorerDatabaseFile.absolute.path;

  Future<ExplorerImportStatus> loadStatus() async {
    final pgnExists = await File(sourcePgnPath).exists();
    final bz2Exists = await File(sourceBz2Path).exists();

    try {
      final db = _openDatabase();
      final imported = _metaValue(db, 'imported') == 'true';

      if (imported) {
        return ExplorerImportStatus.imported(
          sourcePgnPath: sourcePgnPath,
          sourceBz2Path: sourceBz2Path,
          databasePath: databasePath,
          importedGames:
              int.tryParse(_metaValue(db, 'imported_games') ?? '') ?? 0,
          indexedPositions:
              int.tryParse(_metaValue(db, 'indexed_positions') ?? '') ?? 0,
          indexedMoveRows:
              int.tryParse(_metaValue(db, 'indexed_rows') ?? '') ?? 0,
        );
      }

      return ExplorerImportStatus.notImported(
        sourcePgnPath: sourcePgnPath,
        sourceBz2Path: sourceBz2Path,
        databasePath: databasePath,
        needsExtraction: !pgnExists && bz2Exists,
      );
    } catch (error) {
      return ExplorerImportStatus.error(
        sourcePgnPath: sourcePgnPath,
        sourceBz2Path: sourceBz2Path,
        databasePath: databasePath,
        message: error.toString(),
      );
    }
  }

  GameDatabaseImportSession startImport() {
    return _importService.startImport(
      sourcePgnPath: sourcePgnPath,
      sourceBz2Path: sourceBz2Path,
      databasePath: databasePath,
    );
  }

  Future<List<ExplorerMoveStat>> movesForFen(
    String fen, {
    int limit = 15,
  }) async {
    final db = _openDatabase();
    final positionKey = AppDatabase.positionKeyFromFen(fen);
    final resultSet = db.select(
      '''
      SELECT
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
      FROM explorer_move_stats
      WHERE position_key = ?
      ORDER BY games_count DESC
      LIMIT ?;
      ''',
      [positionKey, limit],
    );

    return resultSet.map(_moveStatFromRow).toList();
  }

  Future<int> totalGamesForFen(String fen) async {
    final db = _openDatabase();
    final positionKey = AppDatabase.positionKeyFromFen(fen);
    final row = db.select(
      '''
      SELECT COALESCE(SUM(games_count), 0) AS total
      FROM explorer_move_stats
      WHERE position_key = ?;
      ''',
      [positionKey],
    ).first;

    return row['total'] as int;
  }

  String positionKeyFromFen(String fen) {
    return AppDatabase.positionKeyFromFen(fen);
  }

  void dispose() {
    _db?.dispose();
    _db = null;
  }

  Database _openDatabase() {
    final existing = _db;
    if (existing != null) return existing;

    AppDatabase.chessDatabaseDirectory.createSync(recursive: true);
    final db = sqlite3.open(databasePath);
    AppDatabase.ensureExplorerSchema(db);
    _db = db;
    return db;
  }

  String? _metaValue(Database db, String key) {
    final result = db.select(
      'SELECT value FROM explorer_import_meta WHERE key = ? LIMIT 1;',
      [key],
    );
    if (result.isEmpty) return null;
    return result.first['value'] as String?;
  }

  ExplorerMoveStat _moveStatFromRow(Row row) {
    final whiteEloTotal = row['white_elo_total'] as int;
    final whiteEloGames = row['white_elo_games'] as int;
    final blackEloTotal = row['black_elo_total'] as int;
    final blackEloGames = row['black_elo_games'] as int;

    return ExplorerMoveStat(
      positionKey: row['position_key'] as String,
      moveSan: row['move_san'] as String,
      moveUci: row['move_uci'] as String,
      gamesCount: row['games_count'] as int,
      whiteWins: row['white_wins'] as int,
      draws: row['draws'] as int,
      blackWins: row['black_wins'] as int,
      avgWhiteElo: whiteEloGames == 0 ? null : whiteEloTotal / whiteEloGames,
      avgBlackElo: blackEloGames == 0 ? null : blackEloTotal / blackEloGames,
    );
  }
}
