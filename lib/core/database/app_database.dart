import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// Central database configuration and helpers shared by the offline builder
/// and the runtime explorer repository.
class AppDatabase {
  AppDatabase._();

  /// Extracted PGN file used only by the offline builder.
  static const sourcePgnFileName =
      'ficsgamesdb_202601_chess_nomovetimes_2089363.pgn';

  /// Prebuilt SQLite database opened directly by the app at runtime.
  static const explorerDatabaseFileName = 'explorer_fics_202601.sqlite';

  /// JSON manifest written alongside the database by the offline builder.
  static const explorerManifestFileName = 'explorer_fics_202601_manifest.json';

  static const stockfishExecutableFileName = 'stockfish.exe';

  static const explorerSchemaVersion = 1;

  static Directory get executableDirectory {
    return File(Platform.resolvedExecutable).parent.absolute;
  }

  static Directory get chessDatabaseDirectory {
    return Directory(p.join(_projectRoot.path, 'chessdatabase'));
  }

  static List<String> get explorerDatabaseCandidatePaths {
    return _absolutePaths([
      p.join(
        executableDirectory.path,
        'chessdatabase',
        explorerDatabaseFileName,
      ),
      p.join(
        Directory.current.absolute.path,
        'chessdatabase',
        explorerDatabaseFileName,
      ),
      p.join(
        _projectRoot.path,
        'chessdatabase',
        explorerDatabaseFileName,
      ),
    ]);
  }

  static List<String> get sourcePgnCandidatePaths {
    return _absolutePaths([
      p.join(
        Directory.current.absolute.path,
        'chessdatabase',
        sourcePgnFileName,
      ),
      p.join(
        _projectRoot.path,
        'chessdatabase',
        sourcePgnFileName,
      ),
    ]);
  }

  static List<String> get stockfishExecutableCandidatePaths {
    return _absolutePaths([
      p.join(executableDirectory.path, stockfishExecutableFileName),
      p.join(Directory.current.absolute.path, stockfishExecutableFileName),
      p.join(_projectRoot.path, stockfishExecutableFileName),
    ]);
  }

  static File get sourcePgnFile {
    return File(p.join(chessDatabaseDirectory.path, sourcePgnFileName));
  }

  static File get resolvedSourcePgnFile {
    return findFirstExistingFile(sourcePgnCandidatePaths);
  }

  static File get explorerDatabaseFile {
    return File(
      p.join(chessDatabaseDirectory.path, explorerDatabaseFileName),
    );
  }

  static File get resolvedExplorerDatabaseFile {
    return findFirstExistingFile(explorerDatabaseCandidatePaths);
  }

  static File get resolvedStockfishExecutableFile {
    return findFirstExistingFile(stockfishExecutableCandidatePaths);
  }

  static File get explorerManifestFile {
    return File(
      p.join(chessDatabaseDirectory.path, explorerManifestFileName),
    );
  }

  static File findFirstExistingFile(List<String> candidatePaths) {
    for (final candidatePath in candidatePaths) {
      final candidate = File(candidatePath);
      if (candidate.existsSync()) {
        return candidate.absolute;
      }
    }

    if (candidatePaths.isEmpty) {
      return File('');
    }

    return File(candidatePaths.first).absolute;
  }

  /// Normalized position key derived from a FEN string.
  ///
  /// Uses the first four FEN fields: piece placement, side to move, castling
  /// rights, and en passant. It removes the halfmove clock and fullmove number
  /// so identical positions share the same key.
  static String positionKeyFromFen(String fen) {
    final candidates = positionKeyCandidatesFromFen(fen);
    return candidates.isEmpty ? fen.trim() : candidates.first;
  }

  /// Ordered lookup keys for explorer databases built with slightly different
  /// en-passant normalization rules.
  static List<String> positionKeyCandidatesFromFen(String fen) {
    final fields = fen.trim().split(RegExp(r'\s+'));
    if (fields.length < 4) {
      final trimmedFen = fen.trim();
      return trimmedFen.isEmpty ? const [] : [trimmedFen];
    }

    final placement = fields[0];
    final turn = fields[1];
    final castling = fields[2].isEmpty ? '-' : fields[2];
    final enPassant = fields[3].isEmpty ? '-' : fields[3];
    final candidates = <String>[
      '$placement $turn $castling $enPassant',
      '$placement $turn $castling -',
    ];

    final seen = <String>{};
    final uniqueCandidates = <String>[];
    for (final candidate in candidates) {
      if (seen.add(candidate)) {
        uniqueCandidates.add(candidate);
      }
    }

    return uniqueCandidates;
  }

  /// Creates the explorer schema if it does not already exist.
  static void ensureExplorerSchema(
    Database db, {
    bool createLookupIndexes = true,
  }) {
    _createExplorerTables(db);

    if (createLookupIndexes) {
      ensureExplorerIndexes(db);
    }
  }

  /// Drops and recreates the explorer tables for a fresh offline build.
  static void resetExplorerSchema(Database db) {
    db.execute('DROP INDEX IF EXISTS idx_explorer_position_key;');
    db.execute('DROP INDEX IF EXISTS idx_explorer_position_games;');
    db.execute('DROP TABLE IF EXISTS explorer_moves;');
    db.execute('DROP TABLE IF EXISTS explorer_metadata;');
    _createExplorerTables(db);
  }

  static void ensureExplorerIndexes(Database db) {
    db.execute('''
      CREATE INDEX IF NOT EXISTS idx_explorer_position_key
      ON explorer_moves (position_key);
    ''');

    db.execute('''
      CREATE INDEX IF NOT EXISTS idx_explorer_position_games
      ON explorer_moves (position_key, games_count DESC);
    ''');
  }

  /// Returns true when the prebuilt database file exists and has the expected
  /// explorer table.
  static bool prebuiltDatabaseExists() {
    final file = resolvedExplorerDatabaseFile;
    if (!file.existsSync()) return false;

    Database? db;
    try {
      db = sqlite3.open(file.absolute.path);
      final result = db.select(
        '''
        SELECT name
        FROM sqlite_master
        WHERE type IN ('table', 'view')
          AND name IN ('explorer_moves', 'explorer_move_stats')
        LIMIT 1;
        ''',
      );
      return result.isNotEmpty;
    } catch (_) {
      return false;
    } finally {
      db?.dispose();
    }
  }

  static List<String> _absolutePaths(List<String> paths) {
    return [
      for (final path in paths) File(path).absolute.path,
    ];
  }

  static void _createExplorerTables(Database db) {
    db.execute('''
      CREATE TABLE IF NOT EXISTS explorer_moves (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        position_key TEXT NOT NULL,
        move_san TEXT NOT NULL,
        move_uci TEXT NOT NULL,
        games_count INTEGER NOT NULL DEFAULT 0,
        white_wins INTEGER NOT NULL DEFAULT 0,
        draws INTEGER NOT NULL DEFAULT 0,
        black_wins INTEGER NOT NULL DEFAULT 0,
        avg_white_elo REAL,
        avg_black_elo REAL,
        white_elo_games INTEGER NOT NULL DEFAULT 0,
        black_elo_games INTEGER NOT NULL DEFAULT 0,
        UNIQUE(position_key, move_san, move_uci)
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS explorer_metadata (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      );
    ''');
  }

  static Directory get _projectRoot {
    final current = Directory.current.absolute;
    final candidates = <Directory>[
      current,
      current.parent,
      current.parent.parent,
      current.parent.parent.parent,
      File(Platform.resolvedExecutable).parent,
      File(Platform.resolvedExecutable).parent.parent,
      File(Platform.resolvedExecutable).parent.parent.parent,
    ];

    for (final candidate in candidates) {
      if (Directory(p.join(candidate.path, 'chessdatabase')).existsSync() &&
          File(p.join(candidate.path, 'pubspec.yaml')).existsSync()) {
        return candidate;
      }
    }

    return current;
  }
}
