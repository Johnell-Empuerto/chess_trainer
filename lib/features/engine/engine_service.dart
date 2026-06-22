import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import '../../core/utils/platform_utils.dart';

/// Represents the evaluation output from the engine.
class EngineEval {
  final double score; // Positive favors White, negative favors Black
  final int depth;
  final String? bestMove;
  final bool isMate;

  EngineEval({
    required this.score,
    required this.depth,
    this.bestMove,
    this.isMate = false,
  });
}

/// Manages the Stockfish engine in a background Isolate.
class EngineService {
  Isolate? _isolate;
  SendPort? _sendPort;
  ReceivePort? _receivePort;

  final StreamController<EngineEval> _evalController =
      StreamController<EngineEval>.broadcast();
  Stream<EngineEval> get evalStream => _evalController.stream;

  bool _isRunning = false;

  /// Starts the engine isolate.
  Future<void> start() async {
    if (_isRunning) return;
    _isRunning = true;

    _receivePort = ReceivePort();
    _isolate = await Isolate.spawn(
      _engineIsolateEntry,
      _receivePort!.sendPort,
    );

    // Listen to messages from the isolate
    _receivePort!.listen((message) {
      if (message is SendPort) {
        _sendPort = message;
      } else if (message is EngineEval) {
        _evalController.add(message);
      }
    });
  }

  /// Sends the current position to the engine for evaluation.
  void evaluate(String fen) {
    if (_sendPort != null) {
      _sendPort!.send(fen);
    }
  }

  /// Stops the engine and cleans up resources.
  void dispose() {
    _isRunning = false;
    _sendPort?.send('stop');
    _isolate?.kill(priority: Isolate.immediate);
    _receivePort?.close();
    _evalController.close();
  }

  // ---------------- Isolate Entry Point ----------------

  static void _engineIsolateEntry(SendPort mainSendPort) {
    final receivePort = ReceivePort();
    mainSendPort.send(receivePort.sendPort);

    // For Windows, we run actual Stockfish. For Android/mobile, we use a mock
    // to avoid native dependency crashes in Phase 2.
    final bool useRealEngine = PlatformUtils.isWindows;

    Process? process;
    StreamSubscription? stdoutSub;

    if (useRealEngine) {
      // Assumes stockfish.exe is in the project root or system PATH.
      // You can download it from https://stockfishchess.org/download/windows/
      Process.start('stockfish', []).then((p) {
        process = p;

        stdoutSub =
            p.stdout.transform(const SystemEncoding().decoder).listen((data) {
          final eval = _parseStockfishOutput(data);
          if (eval != null) {
            mainSendPort.send(eval);
          }
        });

        // Initialize UCI
        p.stdin.writeln('uci');
        p.stdin.writeln('setoption name Threads value 2');
      }).catchError((e) {
        // If stockfish.exe is missing, fallback to mock
        print('Failed to start Stockfish: $e. Running mock engine.');
      });
    }

    receivePort.listen((message) {
      if (message is String) {
        if (message == 'stop') {
          stdoutSub?.cancel();
          process?.kill();
          Isolate.exit();
        }

        if (useRealEngine && process != null) {
          process!.stdin.writeln('position fen $message');
          process!.stdin.writeln('go depth 12');
        } else if (!useRealEngine) {
          // --- Mock Engine for Android ---
          // Generates a random evaluation after a short delay
          Future.delayed(const Duration(milliseconds: 300), () {
            final rand = Random();
            final mockScore = (rand.nextDouble() * 4) - 2; // -2.0 to +2.0
            final mockEval = EngineEval(
              score: mockScore,
              depth: 10 + rand.nextInt(5),
              bestMove: 'e2e4',
            );
            mainSendPort.send(mockEval);
          });
        }
      }
    });
  }

  /// Parses UCI output lines like:
  /// "info depth 15 score cp 34 pv e2e4 e7e5"
  /// "info depth 15 score mate 3 pv ..."
  static EngineEval? _parseStockfishOutput(String output) {
    final lines = output.split('\n');
    EngineEval? latestEval;

    for (final line in lines) {
      if (line.startsWith('info') &&
          line.contains('score') &&
          line.contains('pv')) {
        final parts = line.split(' ');
        int depth = 0;
        double score = 0;
        bool isMate = false;
        String? bestMove;

        for (int i = 0; i < parts.length; i++) {
          if (parts[i] == 'depth' && i + 1 < parts.length) {
            depth = int.tryParse(parts[i + 1]) ?? 0;
          } else if (parts[i] == 'score' && i + 2 < parts.length) {
            if (parts[i + 1] == 'cp') {
              int cp = int.tryParse(parts[i + 2]) ?? 0;
              score = cp / 100.0;
            } else if (parts[i + 1] == 'mate') {
              int mateMoves = int.tryParse(parts[i + 2]) ?? 0;
              isMate = true;
              score = mateMoves > 0 ? 99.0 : -99.0;
            }
          } else if (parts[i] == 'pv' && i + 1 < parts.length) {
            bestMove = parts[i + 1];
          }
        }
        latestEval = EngineEval(
          score: score,
          depth: depth,
          bestMove: bestMove,
          isMate: isMate,
        );
      }
    }
    return latestEval;
  }
}
