// Unit tests for the pure protocol/option logic of the auto-qa MCP server.
// These cover everything that does NOT need a live app or a FlutterDriver
// connection — option parsing, the JSON-RPC control dispatch, the tool
// catalogue, and the small helpers — so they run under plain `flutter test`.
// The driver-backed tool implementations live in `lib/src/auto_qa_server.dart`.
import 'dart:convert';
import 'dart:io';

import 'package:auto_qa/auto_qa.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AutoQaOptions.parse', () {
    test('defaults when no flags are given', () {
      final o = AutoQaOptions.parse([]);
      expect(o.vmServiceUri, isNull);
      expect(o.launch, isFalse);
      expect(o.definesFile, isNull);
      expect(o.dartDefines, isEmpty);
      expect(o.device, 'macos');
      expect(o.target, 'test_driver/app.dart');
      expect(o.tapKey, isNull);
      expect(o.readyDelayMs, 0);
      expect(o.artifactsDir, isNull);
    });

    test('parses every flag', () {
      final o = AutoQaOptions.parse([
        '--launch',
        '--defines-file=/tmp/defines.json',
        '--device=chrome',
        '--target=test_driver/app.dart',
        '--tap-key=signIn',
        '--ready-delay-ms=2000',
        '--artifacts=/tmp/shots',
      ]);
      expect(o.launch, isTrue);
      expect(o.definesFile, '/tmp/defines.json');
      expect(o.device, 'chrome');
      expect(o.tapKey, 'signIn');
      expect(o.readyDelayMs, 2000);
      expect(o.artifactsDir, '/tmp/shots');
    });

    test('collects passthrough --dart-define flags in order', () {
      final o = AutoQaOptions.parse([
        '--launch',
        '--dart-define=API_URL=https://example.test',
        '--dart-define=FLAVOR=dev',
      ]);
      expect(o.dartDefines, [
        '--dart-define=API_URL=https://example.test',
        '--dart-define=FLAVOR=dev',
      ]);
    });

    test('keeps "=" inside a flag value (VM Service URIs have one)', () {
      final o = AutoQaOptions.parse([
        '--vm-service-uri=http://127.0.0.1:50943/aBc123=/',
      ]);
      expect(o.vmServiceUri, 'http://127.0.0.1:50943/aBc123=/');
      // --launch absent → attach mode
      expect(o.launch, isFalse);
    });

    test('non-numeric --ready-delay-ms falls back to 0', () {
      expect(AutoQaOptions.parse(['--ready-delay-ms=soon']).readyDelayMs, 0);
    });
  });

  group('autoQaTools', () {
    test('advertises exactly the six driving tools', () {
      expect(autoQaTools.map((t) => t['name']), [
        'screenshot',
        'describe',
        'tap',
        'enter_text',
        'scroll',
        'wait_for',
      ]);
    });

    test('every tool has a description and an object inputSchema', () {
      for (final t in autoQaTools) {
        expect(t['name'], isA<String>());
        expect(t['description'], isA<String>());
        final schema = t['inputSchema'] as Map<String, dynamic>;
        expect(schema['type'], 'object');
        expect(schema['properties'], isA<Map<String, dynamic>>());
      }
    });

    test('enter_text marks text as required', () {
      final enterText = autoQaTools.firstWhere(
        (t) => t['name'] == 'enter_text',
      );
      expect((enterText['inputSchema'] as Map)['required'], ['text']);
    });
  });

  group('handleControlMessage', () {
    Map<String, dynamic>? handle(Map<String, dynamic> msg) =>
        handleControlMessage(msg);

    test(
      'initialize echoes the client protocol version + advertises tools',
      () {
        final r = handle({
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'initialize',
          'params': {'protocolVersion': '2025-06-18'},
        });
        expect(r, isNotNull);
        expect(r!['id'], 1);
        final result = r['result'] as Map<String, dynamic>;
        expect(result['protocolVersion'], '2025-06-18');
        expect(result['serverInfo'], {
          'name': autoQaServerName,
          'version': autoQaServerVersion,
        });
        expect((result['capabilities'] as Map).containsKey('tools'), isTrue);
      },
    );

    test('initialize without a protocol version falls back to the default', () {
      final r = handle({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': <String, dynamic>{},
      });
      expect((r!['result'] as Map)['protocolVersion'], autoQaProtocolVersion);
    });

    test('tools/list returns the full catalogue', () {
      final r = handle({'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list'});
      expect((r!['result'] as Map)['tools'], same(autoQaTools));
    });

    test('ping with an id returns an empty result', () {
      final r = handle({'jsonrpc': '2.0', 'id': 3, 'method': 'ping'});
      expect(r, {'jsonrpc': '2.0', 'id': 3, 'result': <String, dynamic>{}});
    });

    test('notifications/initialized produces no response', () {
      expect(
        handle({'jsonrpc': '2.0', 'method': 'notifications/initialized'}),
        isNull,
      );
    });

    test('a notification (no id) never gets a response', () {
      expect(handle({'jsonrpc': '2.0', 'method': 'ping'}), isNull);
    });

    test('an unknown method with an id returns method-not-found (-32601)', () {
      final r = handle({'jsonrpc': '2.0', 'id': 9, 'method': 'frobnicate'});
      expect(r!['error'], {
        'code': -32601,
        'message': 'Method not found: frobnicate',
      });
    });

    test('a message with no method (a response to us) is ignored', () {
      expect(handle({'jsonrpc': '2.0', 'id': 1, 'result': {}}), isNull);
    });
  });

  group('screenshotSlug', () {
    test('lowercases and replaces runs of non-alphanumerics with one _', () {
      expect(screenshotSlug('Dashboard Open!'), 'dashboard_open');
      expect(screenshotSlug('a / b   c'), 'a_b_c');
    });

    test('trims leading and trailing underscores', () {
      expect(screenshotSlug('  --- x --- '), 'x');
      expect(screenshotSlug('CHAT'), 'chat');
    });
  });

  group('readDefinesFile', () {
    test('null path → no defines', () {
      expect(readDefinesFile(null), isEmpty);
    });

    test('missing file → StateError', () {
      expect(
        () => readDefinesFile('/no/such/defines.json'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('defines file not found'),
          ),
        ),
      );
    });

    test('reads a JSON array of dart-define strings', () {
      final file =
          File('${Directory.systemTemp.path}/auto_qa_defines_test_$pid.json')
            ..writeAsStringSync(
              jsonEncode([
                '--dart-define=API_URL=https://example.test',
                '--dart-define=FLAVOR=dev',
              ]),
            );
      addTearDown(() => file.deleteSync());
      expect(readDefinesFile(file.path), [
        '--dart-define=API_URL=https://example.test',
        '--dart-define=FLAVOR=dev',
      ]);
    });
  });
}
