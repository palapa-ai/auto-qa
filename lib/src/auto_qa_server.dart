// auto_qa_server.dart — an MCP server that wraps `flutter_driver`, exposing a
// live Flutter app as a set of tools an LLM can call to *drive* it: screenshot,
// tap, type, scroll, wait, and describe. Point it at any driver-enabled Flutter
// app and an MCP client (e.g. Claude Code) can navigate and inspect it for
// AI-assisted QA.
//
// The pure protocol/option logic lives in `mcp_protocol.dart` (no flutter_driver
// dependency, unit-tested); this file holds the I/O loop and the
// FlutterDriver-backed tool implementations.
//
// It speaks MCP over stdio as newline-delimited JSON-RPC 2.0 (no framing
// headers — that's the MCP stdio contract), hand-rolled so it pulls in **no
// extra dependencies** beyond the Flutter SDK. `flutter_driver`'s *connect* side
// runs in a plain Dart VM — exactly how `flutter drive` runs a driver script —
// so `dart run auto_qa` holds a single FlutterDriver connection to the app.
//
// stdout is reserved for the protocol; ALL diagnostics go to stderr.
//
// Two ways to reach the app (the connection is lazy — established on the first
// tool call, so the MCP `initialize` handshake never blocks on a native build):
//   --launch              spawn `flutter run --target=<target>` ourselves, parse
//                         its VM Service URI, connect, and own the app's
//                         lifecycle (kill it on shutdown).
//   --vm-service-uri=URI  attach to an already-running driver-enabled app.
//
// Other flags:
//   --defines-file=PATH   JSON array of `--dart-define=…` strings (launch mode).
//   --dart-define=K=V     forwarded straight to `flutter run` (repeatable).
//   --device=NAME         flutter device id (default: macos).
//   --target=PATH         entrypoint (default: test_driver/app.dart).
//   --tap-key=KEY         after connect, tap the widget with this ValueKey
//                         (e.g. to dismiss a splash or sign in).
//   --ready-delay-ms=N    wait N ms after connect before the first interaction.
//   --artifacts=DIR       where `screenshot` writes PNGs (default: a temp dir).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

import 'mcp_protocol.dart';

/// The stdio MCP server. Construct with parsed [AutoQaOptions] and call
/// [serve]; it runs until stdin closes (the MCP shutdown signal).
class AutoQaServer {
  /// Creates the server with parsed [AutoQaOptions]. Call [serve] to run it.
  AutoQaServer(this._opts);

  final AutoQaOptions _opts;

  FlutterDriver? _driver;
  Future<void>? _connecting;
  Process? _flutterProc;
  var _shotCount = 0;

  // --- lifecycle ----------------------------------------------------------

  /// Runs the stdio MCP loop: reads JSON-RPC requests from stdin, writes
  /// responses to stdout, and returns when stdin closes (MCP shutdown).
  Future<void> serve() async {
    // Bring the app down with us however we exit (the client closes our stdin,
    // or sends a signal). EOF on stdin is the normal MCP shutdown.
    ProcessSignal.sigterm.watch().listen((_) => unawaited(_shutdown(0)));
    ProcessSignal.sigint.watch().listen((_) => unawaited(_shutdown(0)));

    final lines = stdin.transform(utf8.decoder).transform(const LineSplitter());
    // `await for` + an inline `await _handle` processes one message to
    // completion before pulling the next — exactly the in-order serialisation
    // driver calls require (they cannot overlap). Incoming lines buffer in the
    // stream while a slow call (connect, screenshot) is in flight.
    await for (final line in lines) {
      if (line.trim().isEmpty) continue;
      await _handle(line);
    }
    // stdin closed → the client is done with us.
    await _shutdown(0);
  }

  Future<Never> _shutdown(int code) async {
    try {
      _flutterProc?.kill(ProcessSignal.sigterm);
    } catch (_) {}
    try {
      await _driver?.close();
    } catch (_) {}
    await stdout.flush();
    exit(code);
  }

  // --- JSON-RPC plumbing --------------------------------------------------

  void _send(Object id, Map<String, dynamic> result) =>
      _write({'jsonrpc': '2.0', 'id': id, 'result': result});

  void _write(Map<String, dynamic> msg) => stdout.writeln(jsonEncode(msg));

  Future<void> _handle(String line) async {
    final Map<String, dynamic> msg;
    try {
      msg = (jsonDecode(line) as Map).cast<String, dynamic>();
    } catch (e) {
      stderr.writeln('[auto-qa] bad JSON: $e');
      return;
    }
    final method = msg['method'] as String?;
    final id = msg['id'];
    final params = (msg['params'] as Map?)?.cast<String, dynamic>() ?? {};

    // `tools/call` needs the live driver (async); everything else is pure
    // dispatch in mcp_protocol.dart.
    if (method == 'tools/call') {
      if (id != null) await _handleToolCall(id as Object, params);
    } else {
      final response = handleControlMessage(msg);
      if (response != null) _write(response);
    }
    // stdout to a pipe is block-buffered; flush so the client sees each
    // response as soon as it's produced rather than only at shutdown.
    await stdout.flush();
  }

  Future<void> _handleToolCall(Object id, Map<String, dynamic> params) async {
    final name = params['name'] as String? ?? '';
    final args = (params['arguments'] as Map?)?.cast<String, dynamic>() ?? {};
    try {
      final content = await _callTool(name, args);
      _send(id, {'content': content});
    } catch (e, st) {
      stderr.writeln('[auto-qa] tool "$name" failed: $e\n$st');
      _send(id, {
        'content': [_text('ERROR: $e')],
        'isError': true,
      });
    }
  }

  Future<List<Map<String, dynamic>>> _callTool(
    String name,
    Map<String, dynamic> args,
  ) async {
    final d = await _ensureConnected();
    switch (name) {
      case 'screenshot':
        return _screenshot(d, args);
      case 'describe':
        return _describe(d);
      case 'tap':
        await d.runUnsynchronized(
          () => d.tap(_finder(args), timeout: const Duration(seconds: 12)),
        );
        return [_text('tapped ${_finderDesc(args)}')];
      case 'enter_text':
        return _enterText(d, args);
      case 'scroll':
        return _scroll(d, args);
      case 'wait_for':
        return _waitFor(d, args);
      default:
        throw ArgumentError('unknown tool: $name');
    }
  }

  Future<List<Map<String, dynamic>>> _screenshot(
    FlutterDriver d,
    Map<String, dynamic> args,
  ) async {
    final bytes = await d.screenshot();
    final dir = _opts.artifactsDir ?? Directory.systemTemp.path;
    Directory(dir).createSync(recursive: true);
    final n = (++_shotCount).toString().padLeft(3, '0');
    final label = screenshotSlug(args['label'] as String? ?? 'shot');
    final path = '$dir/$n-$label.png';
    File(path).writeAsBytesSync(bytes);
    stderr.writeln('[auto-qa] screenshot → $path (${bytes.length} bytes)');
    return [
      _text('saved: $path'),
      {'type': 'image', 'data': base64Encode(bytes), 'mimeType': 'image/png'},
    ];
  }

  Future<List<Map<String, dynamic>>> _describe(FlutterDriver d) async {
    try {
      final tree = await d.getRenderTree();
      final raw = tree.tree ?? '(empty render tree)';
      const limit = 8000;
      final text = raw.length > limit
          ? '${raw.substring(0, limit)}\n…(truncated; rely on screenshot)'
          : raw;
      return [_text(text)];
    } catch (e) {
      return [
        _text('describe unavailable ($e) — use screenshot to read the screen.'),
      ];
    }
  }

  Future<List<Map<String, dynamic>>> _enterText(
    FlutterDriver d,
    Map<String, dynamic> args,
  ) async {
    final focusText = args['focus_text'] as String?;
    final focusKey = args['focus_key'] as String?;
    if (focusText != null || focusKey != null) {
      final f =
          focusText != null ? find.text(focusText) : find.byValueKey(focusKey);
      await d.runUnsynchronized(
        () => d.tap(f, timeout: const Duration(seconds: 12)),
      );
    }
    final text = args['text'] as String? ?? '';
    await d.runUnsynchronized(() => d.enterText(text));
    return [_text('entered ${jsonEncode(text)}')];
  }

  Future<List<Map<String, dynamic>>> _scroll(
    FlutterDriver d,
    Map<String, dynamic> args,
  ) async {
    final hasTarget = args['text'] != null || args['key'] != null;
    final finder = hasTarget ? _finder(args) : find.byType('Scrollable');
    final dx = (args['dx'] as num?)?.toDouble() ?? 0;
    final dy = (args['dy'] as num?)?.toDouble() ?? -300;
    final ms = (args['duration_ms'] as num?)?.toInt() ?? 300;
    await d.runUnsynchronized(
      () => d.scroll(finder, dx, dy, Duration(milliseconds: ms)),
    );
    return [_text('scrolled dx=$dx dy=$dy')];
  }

  Future<List<Map<String, dynamic>>> _waitFor(
    FlutterDriver d,
    Map<String, dynamic> args,
  ) async {
    final finder = _finder(args);
    final timeout = Duration(
      seconds: (args['timeout_s'] as num?)?.toInt() ?? 8,
    );
    final absent = args['absent'] as bool? ?? false;
    try {
      await d.runUnsynchronized(
        () => absent
            ? d.waitForAbsent(finder, timeout: timeout)
            : d.waitFor(finder, timeout: timeout),
      );
      return [_text(absent ? 'absent' : 'present')];
    } catch (_) {
      return [_text('timeout')];
    }
  }

  // --- connection ---------------------------------------------------------

  Future<FlutterDriver> _ensureConnected() async {
    await (_connecting ??= _connect());
    final d = _driver;
    if (d == null) throw StateError('driver failed to connect');
    return d;
  }

  Future<void> _connect() async {
    final uri = _opts.vmServiceUri ?? await _launchAppForUri();
    stderr.writeln('[auto-qa] connecting to $uri');
    _driver = await FlutterDriver.connect(dartVmServiceUrl: uri);
    // Give apps with async startup (network, auth) a moment before the first
    // interaction. Default is 0 — prefer `wait_for` where you can.
    if (_opts.readyDelayMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: _opts.readyDelayMs));
    }
    final tapKey = _opts.tapKey;
    if (tapKey != null) await _tryTap(tapKey);
  }

  Future<String> _launchAppForUri() async {
    if (!_opts.launch) {
      throw StateError(
        'no --vm-service-uri and --launch not set — nothing to connect to',
      );
    }
    final defines = [
      ...readDefinesFile(_opts.definesFile),
      ..._opts.dartDefines,
    ];
    stderr.writeln(
      '[auto-qa] flutter run -d ${_opts.device} --target=${_opts.target} '
      '(${defines.length} dart-defines)',
    );
    final proc = await Process.start('flutter', [
      'run',
      '-d',
      _opts.device,
      '--target=${_opts.target}',
      ...defines,
    ]);
    _flutterProc = proc;
    final uri = Completer<String>();
    final re = RegExp(r'Dart VM Service[^\n]*available at:\s*(http://[^\s]+)');
    proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((
      line,
    ) {
      stderr.writeln('[flutter] $line');
      final m = re.firstMatch(line);
      if (m != null && !uri.isCompleted) {
        uri.complete(m.group(1)?.trim() ?? '');
      }
    });
    proc.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => stderr.writeln('[flutter:err] $line'));
    // Fail fast: if `flutter run` exits before printing a URI (e.g. the native
    // build failed), don't sit on the timeout — surface it immediately.
    unawaited(
      proc.exitCode.then((code) {
        if (!uri.isCompleted) {
          uri.completeError(
            StateError(
              'flutter run exited ($code) before the app was ready — likely a '
              'build failure; see the [flutter:err] lines above.',
            ),
          );
        }
      }),
    );
    return uri.future.timeout(
      const Duration(minutes: 6),
      onTimeout: () =>
          throw StateError('timed out waiting for the Dart VM Service URI'),
    );
  }

  Future<void> _tryTap(String key) async {
    final d = _driver;
    if (d == null) return;
    final f = find.byValueKey(key);
    try {
      await d.runUnsynchronized(
        () => d.waitFor(f, timeout: const Duration(seconds: 6)),
      );
      await d.runUnsynchronized(() => d.tap(f));
      stderr.writeln('[auto-qa] tapped startup key "$key"');
      await Future<void>.delayed(const Duration(seconds: 2));
    } catch (e) {
      stderr.writeln('[auto-qa] startup tap of "$key" skipped ($e)');
    }
  }

  // --- helpers ------------------------------------------------------------

  SerializableFinder _finder(Map<String, dynamic> args) {
    final text = args['text'] as String?;
    final key = args['key'] as String?;
    final tooltip = args['tooltip'] as String?;
    if (text != null) return find.text(text);
    if (key != null) return find.byValueKey(key);
    if (tooltip != null) return find.byTooltip(tooltip);
    throw ArgumentError('provide one of: text, key, tooltip');
  }

  String _finderDesc(Map<String, dynamic> args) {
    final entry = args.entries.firstWhere(
      (e) => const {'text', 'key', 'tooltip'}.contains(e.key),
      orElse: () => const MapEntry('?', '?'),
    );
    return '${entry.key}=${jsonEncode(entry.value)}';
  }

  Map<String, dynamic> _text(String s) => {'type': 'text', 'text': s};
}
