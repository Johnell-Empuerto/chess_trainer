import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

class AppDatabase {
  AppDatabase._();

  static const sourcePgnFileName =
      'ficsgamesdb_202601_chess_nomovetimes_2089363.pgn';
  static const sourceBz2FileName = '$sourcePgnFileName.bz2';
  static const explorerDatabaseFileName = 'opening_explorer.sqlite';

  static Directory get chessDatabaseDirectory {
    return Directory(p.join(_projectRoot.path, 'chessdatabase'));
  }

  static File get sourcePgnFile {
    return File(p.join(chessDatabaseDirectory.path, sourcePgnFileName));
  }

  static File get sourceBz2File {
    return File(p.join(chessDatabaseDirectory.path, sourceBz2FileName));
  }

  static File get explorerDatabaseFile {
    return File(
      p.join(chessDatabaseDirectory.path, explorerDatabaseFileName),
    );
  }

  static String positionKeyFromFen(String fen) {
    final fields = fen.trim().split(RegExp(r'\s+'));
    if (fields.length < 4) return fen.trim();
    return fields.take(4).join(' ');
  }

  static void ensureExplorerSchema(Database db) {
    db.execute('''
      CREATE TABLE IF NOT EXISTS explorer_move_stats (
        position_key TEXT NOT NULL,
        move_san TEXT NOT NULL,
        move_uci TEXT NOT NULL,
        games_count INTEGER NOT NULL DEFAULT 0,
        white_wins INTEGER NOT NULL DEFAULT 0,
        draws INTEGER NOT NULL DEFAULT 0,
        black_wins INTEGER NOT NULL DEFAULT 0,
        white_elo_total INTEGER NOT NULL DEFAULT 0,
        white_elo_games INTEGER NOT NULL DEFAULT 0,
        black_elo_total INTEGER NOT NULL DEFAULT 0,
        black_elo_games INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (position_key, move_san, move_uci)
      );
    ''');

    db.execute('''
      CREATE INDEX IF NOT EXISTS idx_explorer_position_games
      ON explorer_move_stats (position_key, games_count DESC);
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS explorer_import_meta (
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
