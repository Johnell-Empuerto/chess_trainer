import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:chess_trainer/features/coach/domain/coach_move_review.dart';
import 'package:chess_trainer/features/coach/domain/move_quality.dart';

enum AiStatus { initializing, unavailable, running, failed }

class AiExplainerService {
  static const int _serverPort = 8081;
  static const String _serverHost = '127.0.0.1';
  static const Duration _requestTimeout = Duration(seconds: 30);
  Process? _serverProcess;
  AiStatus _status = AiStatus.initializing;
  bool _startAttempted = false;

  AiStatus get status => _status;
  bool get isAvailable => _status == AiStatus.running;

  Future<void> initialize() async {
    if (_startAttempted) return;
    _startAttempted = true;

    try {
      final aiDir = _resolveAiDirectory();

      if (aiDir == null) {
        debugPrint('AI explainer: ai folder not found in any search path');
        _status = AiStatus.unavailable;
        return;
      }

      debugPrint('AI explainer: ai folder -> ${aiDir.path}');

      final missing = await _checkRequiredFiles(aiDir);
      if (missing.isNotEmpty) {
        debugPrint('AI explainer: missing files -> $missing');
        _status = AiStatus.unavailable;
        return;
      }

      final alreadyRunning = await _checkPortReady();
      if (alreadyRunning) {
        debugPrint('AI explainer: server already running on port $_serverPort');
        _status = AiStatus.running;
        return;
      }

      await _startServer(aiDir);
    } catch (error) {
      debugPrint('AI explainer init error: $error');
      _status = AiStatus.failed;
    }
  }

  Directory? _resolveAiDirectory() {
    final candidates = <String>[];

    try {
      final exeDir = Directory(Platform.resolvedExecutable).parent.path;
      candidates.add('$exeDir${Platform.pathSeparator}ai');
    } catch (_) {}

    try {
      candidates.add('${Directory.current.path}${Platform.pathSeparator}ai');
    } catch (_) {}

    try {
      final scriptDir = Directory(Platform.script.toFilePath()).parent.path;
      candidates.add('${scriptDir}${Platform.pathSeparator}ai');
    } catch (_) {}

    final seen = <String>{};
    for (final path in candidates) {
      if (seen.contains(path)) continue;
      seen.add(path);

      final dir = Directory(path);
      if (dir.existsSync()) {
        return dir;
      }
    }

    return null;
  }

  Future<List<String>> _checkRequiredFiles(Directory aiDir) async {
    final requiredFiles = [
      'coach-model.gguf',
      'llama-server.exe',
      'llama-server-impl.dll',
      'llama.dll',
      'llama-common.dll',
      'ggml.dll',
      'ggml-base.dll',
    ];

    final missing = <String>[];
    for (final fileName in requiredFiles) {
      final file = File('${aiDir.path}${Platform.pathSeparator}$fileName');
      final exists = await file.exists();
      if (!exists) {
        missing.add(fileName);
      }
    }

    return missing;
  }

  Future<bool> _checkPortReady() async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 3);

      final request = await client.post(
        _serverHost,
        _serverPort,
        '/v1/chat/completions',
      );

      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'messages': [
          {
            'role': 'system',
            'content': 'You are a helpful chess coach.',
          },
          {
            'role': 'user',
            'content': 'Say ready.',
          },
        ],
        'max_tokens': 10,
        'temperature': 0.2,
      }));

      final response =
          await request.close().timeout(const Duration(seconds: 5));
      final body = await response.transform(systemEncoding.decoder).join();
      client.close();

      debugPrint('AI explainer: port check HTTP ${response.statusCode}');

      if (response.statusCode == 200) {
        try {
          final data = jsonDecode(body) as Map<String, dynamic>;
          final choices = data['choices'] as List?;
          if (choices != null && choices.isNotEmpty) {
            final message = choices[0] as Map<String, dynamic>?;
            final content = message?['message'] as Map<String, dynamic>?;
            if (content?['content'] != null) {
              debugPrint('AI explainer: existing server responded with ready');
              return true;
            }
          }
        } catch (e) {
          debugPrint('AI explainer: port check parse failed: $e');
        }
      }

      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _startServer(Directory aiDir) async {
    final runnerPath = '${aiDir.path}${Platform.pathSeparator}llama-server.exe';
    final runnerFile = File(runnerPath);

    debugPrint('AI explainer: server path -> $runnerPath');
    debugPrint('AI explainer: working dir -> ${aiDir.path}');

    try {
      _serverProcess = await Process.start(
        runnerFile.absolute.path,
        [
          '--model',
          'coach-model.gguf',
          '--host',
          _serverHost,
          '--port',
          '$_serverPort',
          '--ctx-size',
          '512',
          '--threads',
          '2',
        ],
        workingDirectory: aiDir.path,
        mode: ProcessStartMode.detachedWithStdio,
      );

      debugPrint(
          'AI explainer: server process started (pid: ${_serverProcess!.pid})');

      _serverProcess!.stdout
          .transform(systemEncoding.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        debugPrint('AI stdout: $line');
        _checkReadyLine(line);
      });

      _serverProcess!.stderr
          .transform(systemEncoding.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        debugPrint('AI stderr: $line');
        _checkReadyLine(line);
      });

      _serverProcess!.exitCode.then((code) {
        debugPrint('AI explainer: server exited with code $code');
        if (_status == AiStatus.running) {
          _status = AiStatus.failed;
        }
        _serverProcess = null;
      });

      await Future.delayed(const Duration(seconds: 2));

      if (_serverProcess != null && _status != AiStatus.running) {
        try {
          final code = await _serverProcess!.exitCode
              .timeout(const Duration(seconds: 1));
          debugPrint('AI explainer: server exited quickly with code $code');
          _status = AiStatus.failed;
          _serverProcess = null;
        } catch (_) {
          _status = AiStatus.running;
          debugPrint('AI explainer: server appears to be running');
        }
      }
    } catch (error) {
      debugPrint('AI explainer: server start error -> $error');
      _status = AiStatus.failed;
    }
  }

  void _checkReadyLine(String line) {
    final lower = line.toLowerCase();
    if (lower.contains('server is listening') ||
        lower.contains('model loaded') ||
        lower.contains('listening on http://$_serverHost:$_serverPort')) {
      _status = AiStatus.running;
      debugPrint('AI explainer: server ready');
    }
  }

  Future<String?> generateExplanation(CoachMoveReview review) async {
    if (!isAvailable) return null;

    try {
      final result = await _sendChatRequest(review);
      return result;
    } catch (error) {
      debugPrint('AI explainer: generation error -> $error');
      return null;
    }
  }

  Future<String?> _sendChatRequest(CoachMoveReview review) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);

      final request = await client.post(
        _serverHost,
        _serverPort,
        '/v1/chat/completions',
      );

      request.headers.contentType = ContentType.json;

      final qualityLabel = review.quality.label.toLowerCase();
      final openingInfo =
          review.openingName != null && review.openingName!.isNotEmpty
              ? 'Opening: ${review.openingName}\n'
              : '';

      final userContent = '''
Played move: ${review.playedSan} (${review.playedUci})
Move quality: $qualityLabel
Eval before: ${review.evalBefore?.toStringAsFixed(1) ?? 'unknown'}
Eval after: ${review.evalAfter?.toStringAsFixed(1) ?? 'unknown'}
Eval loss: ${review.evalLoss?.toStringAsFixed(1) ?? 'unknown'} pawns
Stockfish best move: ${review.bestMoveUci.isNotEmpty ? review.bestMoveUci : 'unknown'}
Stockfish PV: ${review.pvLine.isNotEmpty ? review.pvLine.take(6).join(' ') : 'none'}
${openingInfo}Short reason: ${review.fallbackExplanation}
'''
          .trim();

      final body = jsonEncode({
        'messages': [
          {
            'role': 'system',
            'content':
                'You are a chess coach. Use only the provided Stockfish facts. Do not invent chess lines. Explain clearly and briefly for a beginner.',
          },
          {
            'role': 'user',
            'content': userContent,
          },
        ],
        'max_tokens': 160,
        'temperature': 0.7,
      });

      request.write(body);

      final response = await request.close().timeout(_requestTimeout);
      final responseBody =
          await response.transform(systemEncoding.decoder).join();
      client.close();

      debugPrint('AI explainer: chat HTTP ${response.statusCode}');

      if (response.statusCode != 200) {
        debugPrint('AI explainer: non-200 status -> $responseBody');
        return null;
      }

      try {
        final data = jsonDecode(responseBody) as Map<String, dynamic>;
        final choices = data['choices'] as List?;

        if (choices == null || choices.isEmpty) {
          debugPrint('AI explainer: no choices in response');
          return null;
        }

        final firstChoice = choices[0] as Map<String, dynamic>;
        final message = firstChoice['message'] as Map<String, dynamic>?;

        if (message == null) {
          debugPrint('AI explainer: no message in choice');
          return null;
        }

        final content = message['content'] as String?;
        if (content == null || content.trim().isEmpty) {
          debugPrint('AI explainer: empty content');
          return null;
        }

        return content.trim();
      } catch (e) {
        debugPrint('AI explainer: response parse failed: $e');
        debugPrint('AI explainer: response body: $responseBody');
        return null;
      }
    } catch (error) {
      debugPrint('AI explainer: request error -> $error');
      return null;
    }
  }

  Future<void> dispose() async {
    final process = _serverProcess;
    if (process != null) {
      _serverProcess = null;
      _status = AiStatus.unavailable;

      try {
        process.stdin.writeln('');
        process.kill();
        await process.exitCode.timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
  }
}
