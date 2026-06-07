// Pure protocol + option logic for the auto_qa MCP server (`auto_qa_server.dart`).
// Split out so it carries **no `flutter_driver` / Flutter dependency** and can be
// unit-tested without a live app: JSON-RPC dispatch for the control methods, the
// tool catalogue, CLI option parsing, and the small file/string helpers. The
// stateful bits that actually talk to the running app (the FlutterDriver
// connection, screenshots, taps) stay in `auto_qa_server.dart`.
import 'dart:convert';
import 'dart:io';

/// MCP protocol revision this server speaks.
const autoQaProtocolVersion = '2025-06-18';

/// Server name advertised in the `initialize` handshake. This is the key clients
/// (e.g. Claude Code's `.mcp.json`) use to namespace the tools.
const autoQaServerName = 'auto_qa';

/// Server version advertised in the `initialize` handshake. Keep in sync with
/// `pubspec.yaml`.
const autoQaServerVersion = '0.1.0';

/// Parsed `--flag=value` / `--flag` options for the MCP server.
///
/// Two ways to reach the app:
///   * [launch] — spawn `flutter run --target=<target>` ourselves, parse its VM
///     Service URI, connect, and own the app's lifecycle.
///   * [vmServiceUri] — attach to an already-running driver-enabled app.
class AutoQaOptions {
  AutoQaOptions({
    this.vmServiceUri,
    this.launch = false,
    this.definesFile,
    this.dartDefines = const [],
    this.device = 'macos',
    this.target = 'test_driver/app.dart',
    this.tapKey,
    this.readyDelayMs = 0,
    this.artifactsDir,
  });

  /// Attach to an already-running app at this `http://…` Dart VM Service URI.
  final String? vmServiceUri;

  /// Spawn `flutter run` ourselves and own the app's lifecycle.
  final bool launch;

  /// Path to a JSON array of `--dart-define=…` strings, forwarded to
  /// `flutter run` in [launch] mode. Useful when you have many defines.
  final String? definesFile;

  /// Raw `--dart-define=…` flags passed straight through to `flutter run` in
  /// [launch] mode. Collected from the server's own argv so a `.mcp.json` can
  /// inline its defines without a separate file.
  final List<String> dartDefines;

  /// Flutter device id to run on in [launch] mode (e.g. `macos`, `chrome`).
  final String device;

  /// The driver-enabled entrypoint to run in [launch] mode.
  final String target;

  /// Optional ValueKey to tap once, right after connecting — handy to dismiss a
  /// splash screen or sign in before the agent takes over.
  final String? tapKey;

  /// Milliseconds to wait after connecting before the first interaction, for
  /// apps with async startup (network, auth). Prefer `wait_for` where you can.
  final int readyDelayMs;

  /// Directory the `screenshot` tool writes PNGs to (default: a temp dir).
  final String? artifactsDir;

  static AutoQaOptions parse(List<String> args) {
    String? valueOf(String flag) => args
        .where((a) => a.startsWith('$flag='))
        .map((a) => a.substring(flag.length + 1))
        .firstOrNull;
    return AutoQaOptions(
      vmServiceUri: valueOf('--vm-service-uri'),
      launch: args.contains('--launch'),
      definesFile: valueOf('--defines-file'),
      dartDefines: args.where((a) => a.startsWith('--dart-define=')).toList(),
      device: valueOf('--device') ?? 'macos',
      target: valueOf('--target') ?? 'test_driver/app.dart',
      tapKey: valueOf('--tap-key'),
      readyDelayMs: int.tryParse(valueOf('--ready-delay-ms') ?? '') ?? 0,
      artifactsDir: valueOf('--artifacts'),
    );
  }
}

/// The MCP tool catalogue advertised by `tools/list`. Pure data (no driver),
/// so it's asserted directly in tests.
final List<Map<String, dynamic>> autoQaTools = [
  {
    'name': 'screenshot',
    'description':
        'Capture the current screen as a PNG (returned inline as an image, '
            'and saved to disk). Returns the saved file path on the first line — '
            'cite that path in the report. This is your PRIMARY way to see the '
            'app; take one whenever the screen changes.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'label': {
          'type': 'string',
          'description': 'Short slug for the filename, e.g. "dashboard_open".',
        },
      },
    },
  },
  {
    'name': 'describe',
    'description': 'Dump the render tree as text (supplementary structure — the '
        'screenshot is the source of truth). Useful to discover exact widget '
        'keys/labels to target. May be truncated.',
    'inputSchema': {'type': 'object', 'properties': <String, dynamic>{}},
  },
  {
    'name': 'tap',
    'description':
        'Tap a widget found by visible text, ValueKey, or tooltip. Provide '
            'exactly one of: text, key, tooltip.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'text': {'type': 'string'},
        'key': {'type': 'string'},
        'tooltip': {'type': 'string'},
      },
    },
  },
  {
    'name': 'enter_text',
    'description':
        'Type into the currently focused text field. Tap the field first '
            '(or pass focus_text / focus_key to tap it as part of this call).',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'text': {'type': 'string'},
        'focus_text': {'type': 'string'},
        'focus_key': {'type': 'string'},
      },
      'required': ['text'],
    },
  },
  {
    'name': 'scroll',
    'description':
        'Scroll a scrollable (found by text/key, else the screen). Negative '
            'dy scrolls down. Defaults: dx=0, dy=-300, duration_ms=300.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'text': {'type': 'string'},
        'key': {'type': 'string'},
        'dx': {'type': 'number'},
        'dy': {'type': 'number'},
        'duration_ms': {'type': 'integer'},
      },
    },
  },
  {
    'name': 'wait_for',
    'description':
        'Wait until a widget (by text/key/tooltip) is present, or absent if '
            'absent=true. Returns present|absent|timeout. Use to confirm a screen '
            'rendered or a state cleared.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'text': {'type': 'string'},
        'key': {'type': 'string'},
        'tooltip': {'type': 'string'},
        'timeout_s': {'type': 'integer'},
        'absent': {'type': 'boolean'},
      },
    },
  },
];

/// Pure JSON-RPC dispatch for the **control** methods (everything except
/// `tools/call`, which needs the live driver and is handled in the server).
/// Returns the response map to write back, or `null` for a notification / a
/// request with no `id`. The caller routes `tools/call` separately.
Map<String, dynamic>? handleControlMessage(Map<String, dynamic> msg) {
  final method = msg['method'] as String?;
  final Object? id = msg['id'];
  // No method → it's a response to us (we never send requests); ignore.
  if (method == null) return null;
  switch (method) {
    case 'initialize':
      final params =
          (msg['params'] as Map?)?.cast<String, dynamic>() ?? const {};
      return _result(id, {
        'protocolVersion':
            params['protocolVersion'] as String? ?? autoQaProtocolVersion,
        'capabilities': {'tools': <String, dynamic>{}},
        'serverInfo': {
          'name': autoQaServerName,
          'version': autoQaServerVersion,
        },
      });
    case 'notifications/initialized':
      return null; // notification — no reply
    case 'ping':
      return id == null ? null : _result(id, const {});
    case 'tools/list':
      return id == null ? null : _result(id, {'tools': autoQaTools});
    default:
      return id == null
          ? null
          : _error(id, -32601, 'Method not found: $method');
  }
}

Map<String, dynamic> _result(Object? id, Map<String, dynamic> result) => {
      'jsonrpc': '2.0',
      'id': id,
      'result': result,
    };

Map<String, dynamic> _error(Object id, int code, String message) => {
      'jsonrpc': '2.0',
      'id': id,
      'error': {'code': code, 'message': message},
    };

/// Filename-safe slug for a screenshot label.
String screenshotSlug(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
    .replaceAll(RegExp(r'^_+|_+$'), '');

/// Reads a JSON array of `--dart-define=…` strings (the `--defines-file` flag's
/// payload), forwarded to `flutter run` in launch mode. Null path → no defines.
/// Missing file → a `StateError`.
List<String> readDefinesFile(String? path) {
  if (path == null) return const [];
  final file = File(path);
  if (!file.existsSync()) {
    throw StateError(
      'defines file not found: $path\n'
      'It must be a JSON array of "--dart-define=KEY=VALUE" strings, or pass\n'
      'the defines directly as --dart-define=… flags instead.',
    );
  }
  final decoded = jsonDecode(file.readAsStringSync());
  return (decoded as List).map((e) => e.toString()).toList();
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
