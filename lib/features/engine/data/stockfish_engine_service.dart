import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:chess_trainer/core/database/app_database.dart';
import 'package:chess_trainer/features/computer/domain/computer_level.dart';
import 'package:chess_trainer/features/engine/domain/engine_analysis_result.dart';

class StockfishEngineException implements Exception {
  final String message;

  const StockfishEngineException(this.message);

  @override
  String toString() => message;
}

class StockfishEngineService {
  static const int defaultDepth = 18;
  static const int defaultMultiPv = 3;

  final StreamController<EngineAnalysisResult> _analysisController =
      StreamController<EngineAnalysisResult>.broadcast();

  Process? _process;
  Future<void>? _startupFuture;
  Future<void> _commandQueue = Future<void>.value();
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  Completer<void>? _uciCompleter;
  Completer<void>? _readyCompleter;
  Completer<void>? _stopCompleter;
  Completer<EngineAnalysisResult>? _directSearchCompleter;
  int? _directSearchId;

  final Map<int, EngineAnalysisLine> _latestLinesByMultiPv = {};

  String _currentFen = '';
  String _latestRawSummary = '';
  int _currentSearchId = 0;
  int _nextSearchId = 0;
  int _configuredMultiPv = defaultMultiPv;
  int _suppressedBestMoveCount = 0;
  bool _computerStrengthConfigured = false;
  bool _engineReady = false;
  bool _searchActive = false;
  bool _disposed = false;

  Stream<EngineAnalysisResult> get analysisStream => _analysisController.stream;

  Future<void> startEngine() {
    if (_disposed) {
      throw const StockfishEngineException('Stockfish service is disposed.');
    }

    if (_process != null && _engineReady) {
      return Future<void>.value();
    }

    return _startupFuture ??= _startEngineProcess();
  }

  Future<void> stopEngine() {
    return _enqueueCommand(() async {
      await _stopEngineProcess(completePendingAnalysis: true);
    });
  }

  int analyzeCurrentPosition(
    String fen, {
    int depth = defaultDepth,
    int multiPv = defaultMultiPv,
  }) {
    final searchId = ++_nextSearchId;

    unawaited(
      _enqueueCommand<void>(() async {
        if (_disposed) {
          throw const StockfishEngineException(
              'Stockfish service is disposed.');
        }

        await startEngine();
        await _stopActiveSearch(suppressBestMove: true);
        await _configureAnalysisStrength();
        await _configureMultiPv(multiPv);

        _resetLatestAnalysis(fen, searchId);
        _searchActive = true;

        debugPrint('sending fen: $fen');
        _send('position fen $fen');
        _send('go depth $depth');
      }),
    );

    return searchId;
  }

  Future<void> setComputerLevel(ComputerLevel level) {
    return _enqueueCommand<void>(() async {
      if (_disposed) {
        throw const StockfishEngineException('Stockfish service is disposed.');
      }

      await startEngine();
      await _configureComputerLevel(level);
    });
  }

  Future<EngineAnalysisResult> getBestMoveForFen({
    required String fen,
    required ComputerLevel level,
    Duration? movetime,
    int? depth,
  }) {
    final searchId = ++_nextSearchId;

    return _enqueueCommand<EngineAnalysisResult>(() async {
      if (_disposed) {
        throw const StockfishEngineException('Stockfish service is disposed.');
      }

      await startEngine();
      await _stopActiveSearch(suppressBestMove: true);
      await _configureComputerLevel(level);

      final completer = Completer<EngineAnalysisResult>();
      _directSearchCompleter = completer;
      _directSearchId = searchId;
      _resetLatestAnalysis(fen, searchId);
      _searchActive = true;

      debugPrint('sending best-move fen: $fen');
      _send('position fen $fen');
      _send(_bestMoveSearchCommand(
        level: level,
        movetime: movetime,
        depth: depth,
      ));

      return completer.future.timeout(
        const Duration(seconds: 45),
        onTimeout: () {
          if (identical(_directSearchCompleter, completer)) {
            _directSearchCompleter = null;
            _directSearchId = null;
          }
          unawaited(cancelCurrentSearch());
          throw const StockfishEngineException(
            'Stockfish timed out while choosing a move.',
          );
        },
      ).whenComplete(() {
        if (identical(_directSearchCompleter, completer)) {
          _directSearchCompleter = null;
          _directSearchId = null;
        }
      });
    });
  }

  Future<EngineAnalysisResult> searchPosition(
    String fen, {
    int depth = 14,
  }) {
    final searchId = ++_nextSearchId;

    return _enqueueCommand<EngineAnalysisResult>(() async {
      if (_disposed) {
        throw const StockfishEngineException('Stockfish service is disposed.');
      }

      await startEngine();
      await _stopActiveSearch(suppressBestMove: true);
      await _configureAnalysisStrength();
      await _configureMultiPv(1);

      final completer = Completer<EngineAnalysisResult>();
      _directSearchCompleter = completer;
      _directSearchId = searchId;
      _resetLatestAnalysis(fen, searchId);
      _searchActive = true;

      _send('position fen $fen');
      _send('go depth $depth');

      return completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          if (identical(_directSearchCompleter, completer)) {
            _directSearchCompleter = null;
            _directSearchId = null;
          }
          unawaited(cancelCurrentSearch());
          throw const StockfishEngineException(
            'Coach analysis timed out.',
          );
        },
      ).whenComplete(() {
        if (identical(_directSearchCompleter, completer)) {
          _directSearchCompleter = null;
          _directSearchId = null;
        }
      });
    });
  }

  Future<EngineAnalysisResult> analyzeFen(
    String fen, {
    int depth = defaultDepth,
    int multiPv = defaultMultiPv,
  }) {
    final completer = Completer<EngineAnalysisResult>();
    late StreamSubscription<EngineAnalysisResult> subscription;
    final searchId = analyzeCurrentPosition(
      fen,
      depth: depth,
      multiPv: multiPv,
    );

    subscription = analysisStream.listen(
      (result) {
        if (result.searchId != searchId || !result.isFinal) return;
        if (!completer.isCompleted) {
          completer.complete(result);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      },
    );

    return completer.future.timeout(
      const Duration(seconds: 45),
      onTimeout: () {
        unawaited(cancelCurrentSearch());
        throw const StockfishEngineException(
          'Stockfish timed out while analyzing the position.',
        );
      },
    ).whenComplete(subscription.cancel);
  }

  Future<void> cancelCurrentSearch() {
    final directSearch = _directSearchCompleter;
    if (directSearch != null && !directSearch.isCompleted) {
      try {
        if (_process != null && _searchActive) {
          _send('stop');
        }
      } catch (error) {
        debugPrint('engine error: $error');
      }
      _completeDirectSearchCanceled();
      return Future<void>.value();
    }

    return _enqueueCommand<void>(() async {
      await _stopActiveSearch(suppressBestMove: true);
    });
  }

  void dispose() {
    _disposed = true;
    unawaited(
      _stopEngineProcess(completePendingAnalysis: true).whenComplete(() {
        unawaited(_analysisController.close());
      }),
    );
  }

  Future<void> _startEngineProcess() async {
    final executable = await _resolveStockfishExecutable();
    if (executable == null) {
      _startupFuture = null;
      final message = _missingStockfishMessage();
      debugPrint('engine error: $message');
      throw StockfishEngineException(message);
    }

    try {
      debugPrint('starting engine: ${executable.path}');

      _uciCompleter = Completer<void>();
      _readyCompleter = Completer<void>();
      final process = await Process.start(executable.path, []);
      _process = process;

      _stdoutSubscription = process.stdout
          .transform(systemEncoding.decoder)
          .transform(const LineSplitter())
          .listen(_handleStdoutLine, onError: _handleEngineError);
      _stderrSubscription = process.stderr
          .transform(systemEncoding.decoder)
          .transform(const LineSplitter())
          .listen(_handleStderrLine, onError: _handleEngineError);

      process.exitCode.then((code) {
        if (_disposed || !identical(_process, process)) return;

        _process = null;
        _startupFuture = null;
        _engineReady = false;
        _searchActive = false;
        _emitEngineError(
          StockfishEngineException('Stockfish exited unexpectedly: $code'),
        );
      });

      _send('uci');
      await _withTimeout(_uciCompleter!.future, 'uci');

      _send('setoption name MultiPV value $defaultMultiPv');
      _configuredMultiPv = defaultMultiPv;
      _computerStrengthConfigured = false;

      _send('isready');
      await _withTimeout(_readyCompleter!.future, 'isready');

      _send('ucinewgame');
      _readyCompleter = Completer<void>();
      _send('isready');
      await _withTimeout(_readyCompleter!.future, 'ucinewgame isready');

      _engineReady = true;
    } catch (error) {
      debugPrint('engine error: $error');
      await _stopEngineProcess(completePendingAnalysis: true);
      rethrow;
    } finally {
      _startupFuture = null;
    }
  }

  Future<void> _configureMultiPv(int multiPv) async {
    final normalizedMultiPv = multiPv.clamp(1, 8).toInt();
    if (_configuredMultiPv == normalizedMultiPv) return;

    _send('setoption name MultiPV value $normalizedMultiPv');
    _configuredMultiPv = normalizedMultiPv;
    _readyCompleter = Completer<void>();
    _send('isready');
    await _withTimeout(_readyCompleter!.future, 'multipv isready');
  }

  Future<void> _configureComputerLevel(ComputerLevel level) async {
    await _configureMultiPv(1);

    _send('setoption name Skill Level value ${level.skillLevel}');
    _send('setoption name UCI_LimitStrength value true');
    _send('setoption name UCI_Elo value ${level.elo}');
    _readyCompleter = Completer<void>();
    _send('isready');
    await _withTimeout(_readyCompleter!.future, 'computer level isready');
    _computerStrengthConfigured = true;
  }

  Future<void> _configureAnalysisStrength() async {
    if (!_computerStrengthConfigured) return;

    _send('setoption name Skill Level value 20');
    _send('setoption name UCI_LimitStrength value false');
    _readyCompleter = Completer<void>();
    _send('isready');
    await _withTimeout(_readyCompleter!.future, 'analysis strength isready');
    _computerStrengthConfigured = false;
  }

  String _bestMoveSearchCommand({
    required ComputerLevel level,
    Duration? movetime,
    int? depth,
  }) {
    final depthLimit = depth ?? level.depth;
    if (depthLimit != null) {
      return 'go depth $depthLimit';
    }

    final moveTimeLimit = movetime ?? level.movetime;
    return 'go movetime ${moveTimeLimit.inMilliseconds}';
  }

  Future<void> _stopActiveSearch({required bool suppressBestMove}) async {
    if (_process == null || !_searchActive) return;

    final completer = Completer<void>();
    _stopCompleter = completer;

    if (suppressBestMove) {
      _suppressedBestMoveCount++;
    }

    _send('stop');

    try {
      await completer.future.timeout(const Duration(seconds: 3));
    } catch (_) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    } finally {
      if (identical(_stopCompleter, completer)) {
        _stopCompleter = null;
      }
      _searchActive = false;
    }
  }

  void _handleStdoutLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return;

    if (trimmed == 'uciok') {
      _completeIfPending(_uciCompleter);
      return;
    }

    if (trimmed == 'readyok') {
      _completeIfPending(_readyCompleter);
      return;
    }

    if (trimmed.startsWith('info ')) {
      _parseInfoLine(trimmed);
      return;
    }

    if (trimmed.startsWith('bestmove ')) {
      _parseBestMove(trimmed);
    }
  }

  void _handleStderrLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isNotEmpty) {
      debugPrint('engine error: $trimmed');
    }
  }

  void _parseInfoLine(String line) {
    if (_currentFen.isEmpty || _currentSearchId == 0) return;

    final parts = line.split(RegExp(r'\s+'));
    var multiPv = 1;
    int? depth;
    int? rawCentipawns;
    int? rawMateIn;
    List<String>? principalVariation;

    for (var i = 0; i < parts.length; i++) {
      final token = parts[i];

      if (token == 'depth' && i + 1 < parts.length) {
        depth = int.tryParse(parts[i + 1]);
      } else if (token == 'multipv' && i + 1 < parts.length) {
        multiPv = int.tryParse(parts[i + 1]) ?? multiPv;
      } else if (token == 'score' && i + 2 < parts.length) {
        if (parts[i + 1] == 'cp') {
          rawCentipawns = int.tryParse(parts[i + 2]);
          rawMateIn = null;
        } else if (parts[i + 1] == 'mate') {
          rawMateIn = int.tryParse(parts[i + 2]);
          rawCentipawns = null;
        }
      } else if (token == 'pv' && i + 1 < parts.length) {
        principalVariation = parts.sublist(i + 1);
        break;
      }
    }

    if (depth == null && rawCentipawns == null && rawMateIn == null) return;

    final whitePerspectiveMultiplier = _whitePerspectiveMultiplier(_currentFen);
    final evaluationPawns = rawCentipawns == null
        ? null
        : (rawCentipawns / 100.0) * whitePerspectiveMultiplier;
    final mateIn =
        rawMateIn == null ? null : rawMateIn * whitePerspectiveMultiplier;
    final existing = _latestLinesByMultiPv[multiPv];
    final pv = principalVariation ?? existing?.principalVariation ?? const [];
    final bestMove = pv.isEmpty ? existing?.bestMoveUci : pv.first;

    _latestLinesByMultiPv[multiPv] = EngineAnalysisLine(
      multiPv: multiPv,
      bestMoveUci: bestMove,
      evaluationPawns: evaluationPawns ?? existing?.evaluationPawns,
      mateIn: rawMateIn == null ? existing?.mateIn : mateIn,
      principalVariation: pv,
      depth: depth ?? existing?.depth ?? 0,
      rawSummary: line,
    );
    _latestRawSummary = line;

    _publishSnapshot(isFinal: false);
  }

  void _parseBestMove(String line) {
    final parts = line.split(RegExp(r'\s+'));
    final bestMove = parts.length > 1 ? parts[1] : 'none';
    String? ponderMove;

    for (var i = 2; i < parts.length - 1; i++) {
      if (parts[i] == 'ponder') {
        ponderMove = parts[i + 1];
        break;
      }
    }

    debugPrint('received bestmove: $bestMove');

    final suppressBestMove = _suppressedBestMoveCount > 0;
    if (suppressBestMove) {
      _suppressedBestMoveCount--;
    }

    _searchActive = false;
    _completeIfPending(_stopCompleter);
    _stopCompleter = null;

    if (suppressBestMove) return;

    final result = _publishSnapshot(
      isFinal: true,
      bestMoveOverride: bestMove,
      ponderMoveUci: ponderMove,
      rawSummary: [
        if (_latestRawSummary.isNotEmpty) _latestRawSummary,
        line,
      ].join('\n'),
    );
    _completeDirectSearch(result);
  }

  EngineAnalysisResult? _publishSnapshot({
    required bool isFinal,
    String? bestMoveOverride,
    String? ponderMoveUci,
    String? rawSummary,
  }) {
    if (_analysisController.isClosed || _currentFen.isEmpty) return null;

    final result = EngineAnalysisResult.fromLines(
      lines: _latestLinesByMultiPv.values.toList(),
      fen: _currentFen,
      searchId: _currentSearchId,
      isFinal: isFinal,
      bestMoveOverride: bestMoveOverride,
      ponderMoveUci: ponderMoveUci,
      rawSummary: rawSummary ?? _latestRawSummary,
    );

    _analysisController.add(result);
    return result;
  }

  void _send(String command) {
    final process = _process;
    if (process == null) {
      throw const StockfishEngineException('Stockfish is not running.');
    }

    process.stdin.writeln(command);
  }

  Future<File?> _resolveStockfishExecutable() async {
    for (final candidatePath in AppDatabase.stockfishExecutableCandidatePaths) {
      final candidate = File(candidatePath);
      if (await candidate.exists()) {
        return candidate.absolute;
      }
    }

    return null;
  }

  String _missingStockfishMessage() {
    final lines = <String>[
      'Stockfish executable not found. Checked:',
      '',
      for (var i = 0;
          i < AppDatabase.stockfishExecutableCandidatePaths.length;
          i++)
        '${i + 1}. ${AppDatabase.stockfishExecutableCandidatePaths[i]}',
    ];

    return lines.join('\n');
  }

  Future<T> _withTimeout<T>(
    Future<T> future,
    String step, {
    Duration timeout = const Duration(seconds: 15),
  }) {
    return future.timeout(
      timeout,
      onTimeout: () {
        throw StockfishEngineException(
          'Stockfish timed out while waiting for $step.',
        );
      },
    );
  }

  Future<T> _enqueueCommand<T>(Future<T> Function() action) {
    final operation = _commandQueue.then((_) => action());
    _commandQueue = operation.then<void>((_) {}).catchError(
      (Object error, StackTrace stackTrace) {
        _emitEngineError(error);
      },
    );
    return operation;
  }

  void _handleEngineError(Object error) {
    _emitEngineError(error);
  }

  void _emitEngineError(Object error) {
    debugPrint('engine error: $error');
    _completeDirectSearchError(error);

    if (!_analysisController.isClosed) {
      _analysisController.addError(error);
    }
  }

  void _completeDirectSearch(EngineAnalysisResult? result) {
    if (result == null || result.searchId != _directSearchId) return;

    final completer = _directSearchCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete(result);
    }
  }

  void _completeDirectSearchError(Object error) {
    final completer = _directSearchCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(error);
    }
    _directSearchCompleter = null;
    _directSearchId = null;
  }

  void _completeDirectSearchCanceled() {
    final completer = _directSearchCompleter;
    final searchId = _directSearchId ?? _currentSearchId;
    final fen = _currentFen;

    if (completer != null && !completer.isCompleted) {
      completer.complete(
        EngineAnalysisResult(
          bestMoveUci: 'none',
          ponderMoveUci: null,
          evaluationPawns: null,
          mateIn: null,
          principalVariation: const [],
          depth: 0,
          rawSummary: 'Search canceled.',
          fen: fen,
          searchId: searchId,
          isFinal: true,
        ),
      );
    }

    _directSearchCompleter = null;
    _directSearchId = null;
  }

  void _completeIfPending(Completer<void>? completer) {
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  Future<void> _stopEngineProcess({
    bool completePendingAnalysis = false,
  }) async {
    final process = _process;
    _process = null;
    _startupFuture = null;
    _engineReady = false;
    _searchActive = false;
    _currentFen = '';
    _currentSearchId = 0;
    _latestLinesByMultiPv.clear();

    if (completePendingAnalysis) {
      _completeDirectSearchError(
        const StockfishEngineException('Stockfish search was stopped.'),
      );
      _completeIfPending(_stopCompleter);
      _completeIfPending(_uciCompleter);
      _completeIfPending(_readyCompleter);
    }

    if (process != null) {
      final exitFuture = process.exitCode;

      try {
        process.stdin.writeln('stop');
        process.stdin.writeln('quit');
        await process.stdin.flush();
      } catch (_) {
        // The process may already be closed.
      }

      process.kill();

      try {
        await exitFuture.timeout(const Duration(seconds: 2));
      } catch (_) {
        // Best-effort cleanup only.
      }
    }

    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    _stdoutSubscription = null;
    _stderrSubscription = null;
    _uciCompleter = null;
    _readyCompleter = null;
    _stopCompleter = null;
  }

  void _resetLatestAnalysis(String fen, int searchId) {
    _currentFen = fen;
    _currentSearchId = searchId;
    _latestRawSummary = '';
    _latestLinesByMultiPv.clear();
  }

  int _whitePerspectiveMultiplier(String fen) {
    final fields = fen.split(RegExp(r'\s+'));
    if (fields.length > 1 && fields[1] == 'b') return -1;
    return 1;
  }
}
